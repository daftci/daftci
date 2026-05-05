#!/usr/bin/env bash
# heartbeat.sh
# Write the current runner's heartbeat to .daft/runners/<id>/heartbeat.json, then
# commit and push (with rebase-retry). Per-runner path → no contention with peers.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner_heartbeat.log'

# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh
# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/time.sh
. scripts/lib/daft/time.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  do_heartbeat
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

function do_heartbeat() {
  local id
  id="$(read_runner_id)" || { log '❌ no runner id (run daft-runner-init or set DAFT_RUNNER_ID)'; exit 1; }
  write_heartbeat "${id}"
  commit_local_or_push "heartbeat: ${id}" 3
}

function write_heartbeat() {
  local -r id="${1}"
  local -r dir=".daft/runners/${id}"
  local now epoch tick current
  mkdir -p "${dir}"
  now="$(utc_rfc3339_ns)"
  epoch="$(epoch_seconds)"
  tick="$(read_tick_count "${id}")"
  current="$(read_current_job "${id}")"
  printf '{"runner_id":"%s","last_seen_at":"%s","last_seen_epoch":%s,"tick_count":%s,"current_job_id":%s}\n' \
    "${id}" "${now}" "${epoch}" "${tick}" "${current}" > "${dir}/heartbeat.json"
}

function read_tick_count() {
  local -r id="${1}"
  local -r path=".daft/workspace/runner-${id}.tick"
  if [ ! -f "${path}" ]; then printf '0'; return 0; fi
  cat "${path}"
}

function read_current_job() {
  local -r id="${1}"
  local job
  job="$(find ".daft/active/${id}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
  if [ -z "${job}" ]; then printf 'null'; return 0; fi
  printf '"%s"' "$(basename "${job}")"
}

main "${@:-}"
