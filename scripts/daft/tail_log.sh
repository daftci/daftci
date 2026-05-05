#!/usr/bin/env bash
# tail_log.sh
# Tail -F a job's workspace log file by job-id.
# Args: JOB_ID

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_tail_log.log'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local -r job_id="${1}"
  tail_one "${job_id}"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -ne 1 ] || [ -z "${1:-}" ]; then
    log '❌ Usage: tail_log.sh JOB_ID'
    exit 1
  fi
}

function tail_one() {
  local -r job_id="${1}"
  local -r workspace=".daft/workspace/${job_id}.log"
  if [ -f "${workspace}" ]; then
    tail -F "${workspace}"
    return 0
  fi
  tail_archived "${job_id}"
}

function tail_archived() {
  local -r job_id="${1}"
  local archived
  archived="$(find .daft/archive -name "${job_id}" -type d 2>/dev/null | head -1)"
  if [ -z "${archived}" ] || [ ! -f "${archived}/job.log" ]; then
    log "❌ No log found for ${job_id}"
    exit 1
  fi
  cat "${archived}/job.log"
}

main "${@:-}"
