#!/usr/bin/env bash
# janitor.sh
# Stale-lock recovery for THIS runner only. Sweeps .daft/active/<my-id>/<*>/ and
# returns any orphan job to .daft/queue/x86_64/. Idempotent. Called once at runner
# startup AND standalone-runnable for tests.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner_janitor.log'
declare -r SERVICE='daft-runner'

# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh
# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/logger.sh
. scripts/lib/daft/logger.sh
# shellcheck source=scripts/lib/daft/time.sh
. scripts/lib/daft/time.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  janitor_run
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

function janitor_run() {
  local id
  id="$(read_runner_id)" || { log '❌ no runner id'; exit 1; }
  log "🧹 janitor: scanning active/${id}/"
  local recovered
  recovered="$(scan_my_active "${id}")"
  if [ "${recovered}" -gt 0 ]; then
    log "  ✅ recovered ${recovered} orphan(s) → queue"
    commit_local_or_push "janitor: ${id} recovered ${recovered}" 3
  fi
}

function scan_my_active() {
  local -r id="${1}"
  local count=0 d
  if [ ! -d ".daft/active/${id}" ]; then printf '0'; return 0; fi
  for d in ".daft/active/${id}/"*/; do
    [ -d "${d}" ] || continue
    [ -f "${d}/job.json" ] || continue
    recover_orphan "${d}" "${id}"
    count=$(( count + 1 ))
  done
  printf '%s\n' "${count}"
}

function recover_orphan() {
  local -r dir="${1}"
  local -r runner_id="${2}"
  local job_id
  job_id="$(basename "${dir}")"
  mkdir -p .daft/queue/x86_64
  mv "${dir}/job.json" ".daft/queue/x86_64/${job_id}.json"
  rm -rf "${dir}"
  log_json "${SERVICE}" 'warn' 'orphan job recovered by janitor' \
    "$(printf '"runner_id":"%s","job_id":"%s"' "${runner_id}" "${job_id}")"
}

main "${@:-}"
