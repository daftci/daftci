#!/usr/bin/env bash
# tick.sh
# One runner iteration: bump tick counter; pull_rebase; if heartbeat is due, push
# heartbeat; attempt one claim; on success, execute + release.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner_tick.log'
declare -rx HEARTBEAT_INTERVAL_TICKS="${HEARTBEAT_INTERVAL_TICKS:-6}"

# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh
# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh

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
  local id tick
  id="$(read_runner_id)" || { log '❌ no runner id'; exit 1; }
  tick="$(bump_tick "${id}")"
  if has_origin_remote; then
    pull_rebase >/dev/null 2>&1 || true
  fi
  maybe_heartbeat "${tick}"
  attempt_claim_and_run
}

function bump_tick() {
  local -r id="${1}"
  local -r path=".daft/workspace/runner-${id}.tick"
  local current=0
  mkdir -p .daft/workspace
  if [ -f "${path}" ]; then current="$(cat "${path}")"; fi
  current=$(( current + 1 ))
  printf '%s\n' "${current}" > "${path}"
  printf '%s' "${current}"
}

function maybe_heartbeat() {
  local -r tick="${1}"
  if [ "$(( tick % HEARTBEAT_INTERVAL_TICKS ))" -ne 0 ]; then
    return 0
  fi
  bash scripts/runner/heartbeat.sh || log '⚠️  heartbeat failed'
}

function attempt_claim_and_run() {
  local id job_id out_file
  id="$(read_runner_id)" || return 0
  out_file=".daft/workspace/.last_claim_${id}.txt"
  if ! bash scripts/runner/claim.sh; then
    return 0
  fi
  if [ ! -f "${out_file}" ]; then return 0; fi
  job_id="$(cat "${out_file}")"
  if [ -z "${job_id}" ]; then return 0; fi
  bash scripts/runner/execute.sh "${job_id}" || log "⚠️  execute failed for ${job_id}"
  bash scripts/runner/release.sh "${job_id}" || log "⚠️  release failed for ${job_id}"
}

main "${@:-}"
