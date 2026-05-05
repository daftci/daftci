#!/usr/bin/env bash
# runner_list.sh
# List all registered runners with heartbeat age and current job. Read-only.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner_list.log'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  print_header
  print_rows
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

function print_header() {
  printf '%-32s %-20s %-20s %s\n' 'RUNNER_ID' 'HOSTNAME' 'LAST_SEEN_AT' 'CURRENT_JOB'
}

function print_one() {
  local -r dir="${1}"
  local id host last_seen current
  id="$(yq -r '.id // ""' "${dir}/identity.json" 2>/dev/null)"
  host="$(yq -r '.hostname // ""' "${dir}/identity.json" 2>/dev/null)"
  last_seen="$(yq -r '.last_seen_at // "never"' "${dir}/heartbeat.json" 2>/dev/null)"
  current="$(yq -r '.current_job_id // "—"' "${dir}/heartbeat.json" 2>/dev/null)"
  printf '%-32s %-20s %-20s %s\n' "${id:-?}" "${host:-?}" "${last_seen}" "${current}"
}

function print_rows() {
  if [ ! -d .daft/runners ]; then
    return 0
  fi
  local d
  for d in .daft/runners/*/; do
    [ -d "${d}" ] || continue
    [ -f "${d}/identity.json" ] || continue
    print_one "${d%/}"
  done
}

main "${@:-}"
