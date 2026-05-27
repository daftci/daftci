#!/usr/bin/env bash
# tick_show.sh
# Print current effective tick intervals (file value, env override, and default)
# for each daemon. Read-only; does not start, stop, or signal any process.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_tick_show.log'

# shellcheck source=scripts/lib/daft/intervals.sh
. scripts/lib/daft/intervals.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  intervals_load
  print_all
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

function print_all() {
  log '📊 tick intervals'
  log "   file: ${INTERVALS_FILE}"
  print_one 'COORDINATOR_INTERVAL_SECONDS'
  print_one 'REAPER_INTERVAL_SECONDS'
  print_one 'RUNNER_INTERVAL_SECONDS'
}

function print_one() {
  local -r key="${1}"
  local val def file_val
  val="$(intervals_value_for "${key}")"
  def="$(intervals_default_for "${key}")"
  file_val="$(intervals_file_value_for "${key}")"
  log "   ${key}=${val}s  (default ${def}s, file ${file_val:-unset})"
}

main "${@:-}"
