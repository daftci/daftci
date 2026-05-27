#!/usr/bin/env bash
# tick.sh
# One reaper iteration: scan all .daft/runners/<id>/heartbeat.json, mark stale runners
# (older than REAPER_THRESHOLD_SECONDS), and return their active jobs to the queue.
# Writes runners/<id>/reaped.json to mark idempotency.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_reaper_tick.log'
declare -rx REAPER_THRESHOLD_SECONDS="${REAPER_THRESHOLD_SECONDS:-90}"
declare -r SERVICE='daft-reaper'

# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/metrics.sh
. scripts/lib/daft/metrics.sh
# shellcheck source=scripts/lib/daft/time.sh
. scripts/lib/daft/time.sh
# shellcheck source=scripts/lib/daft/logger.sh
. scripts/lib/daft/logger.sh
# shellcheck source=scripts/lib/daft/reload.sh
. scripts/lib/daft/reload.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  run_tick
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -gt 1 ] || [ -n "${1:-}" ]; then
    log '❌ Error: Unexpected argument'
    exit 1
  fi
}

function run_tick() {
  log '🔄 reaper tick start'
  metric_inc 'reaper_runs_total'
  if has_origin_remote; then
    pull_rebase >/dev/null 2>&1 || log '⚠️  pull_rebase warning'
  fi
  maybe_handle_reload
  scan_and_recover
  commit_local_or_push 'reaper: tick' 3 || log '⚠️  push failed; will retry next tick'
  log '✅ reaper tick end'
}

function maybe_handle_reload() {
  if ! reload_changed_for 'reaper'; then return 0; fi
  local cur
  cur="$(reload_current_tick)"
  log "🔔 reload signal seen (tick=${cur}); dropping caches"
  reload_caches
  reload_write_last_seen 'reaper' "${cur}"
}

function reload_caches() {
  :
}

function scan_and_recover() {
  if [ ! -d .daft/runners ]; then
    return 0
  fi
  local d
  for d in .daft/runners/*/; do
    [ -d "${d}" ] || continue
    [ -f "${d}/heartbeat.json" ] || continue
    if already_reaped "${d}"; then continue; fi
    if is_stale "${d}/heartbeat.json"; then
      recover_runner "$(basename "${d%/}")"
    fi
  done
}

function already_reaped() {
  [ -f "${1}/reaped.json" ]
}

function is_stale() {
  local -r heartbeat_file="${1}"
  local last_epoch now_epoch age
  last_epoch="$(yq -r '.last_seen_epoch // 0' "${heartbeat_file}")"
  if [ "${last_epoch}" = '0' ]; then return 1; fi
  now_epoch="$(epoch_seconds)"
  age=$(( now_epoch - last_epoch ))
  [ "${age}" -gt "${REAPER_THRESHOLD_SECONDS}" ]
}

function recover_runner() {
  local -r runner_id="${1}"
  local -r runner_dir=".daft/runners/${runner_id}"
  local jobs_count
  jobs_count="$(recover_jobs_for "${runner_id}")"
  write_reaped_json "${runner_dir}" "${runner_id}" "${jobs_count}"
  log "  💀 reaped ${runner_id}: ${jobs_count} job(s) recovered"
  log_json "${SERVICE}" 'warn' 'runner reaped' \
    "$(printf '"runner_id":"%s","jobs_recovered":%s' "${runner_id}" "${jobs_count}")"
  metric_inc 'reaper_jobs_recovered_total'
}

function recover_jobs_for() {
  local -r runner_id="${1}"
  local count=0 d
  for d in ".daft/active/${runner_id}/"*/; do
    [ -d "${d}" ] || continue
    [ -f "${d}/job.json" ] || continue
    move_job_back "${d}"
    count=$(( count + 1 ))
  done
  printf '%s\n' "${count}"
}

function move_job_back() {
  local -r dir="${1}"
  local job_id
  job_id="$(basename "${dir}")"
  mkdir -p .daft/queue/x86_64
  mv "${dir}/job.json" ".daft/queue/x86_64/${job_id}.json"
  rm -rf "${dir}"
}

function write_reaped_json() {
  local -r runner_dir="${1}"
  local -r runner_id="${2}"
  local -r count="${3}"
  local now reaper_id
  now="$(utc_rfc3339_ns)"
  reaper_id="reaper-$(hostname -s 2>/dev/null || hostname)"
  printf '{"reaped_at":"%s","reaper_id":"%s","runner_id":"%s","jobs_recovered":%s}\n' \
    "${now}" "${reaper_id}" "${runner_id}" "${count}" > "${runner_dir}/reaped.json"
}

main "${@:-}"
