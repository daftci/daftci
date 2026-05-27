#!/usr/bin/env bash
# tick_set.sh
# Update one tick-interval knob in .daft/workspace/intervals.env. Host-local
# (gitignored). Takes effect on next loop restart, not immediately.
#
# Args: KNOB SECONDS
#   KNOB     COORDINATOR_INTERVAL_SECONDS | REAPER_INTERVAL_SECONDS | RUNNER_INTERVAL_SECONDS
#   SECONDS  positive integer

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_tick_set.log'

# shellcheck source=scripts/lib/daft/intervals.sh
. scripts/lib/daft/intervals.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local -r knob="${1}"
  local -r seconds="${2}"
  validate_knob "${knob}"
  validate_seconds "${seconds}"
  apply_set "${knob}" "${seconds}"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -ne 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    log '❌ Usage: tick_set.sh KNOB SECONDS'
    exit 1
  fi
}

function validate_knob() {
  case "${1}" in
    COORDINATOR_INTERVAL_SECONDS|REAPER_INTERVAL_SECONDS|RUNNER_INTERVAL_SECONDS) return 0 ;;
    *) log "❌ Unknown knob: ${1}"; exit 1 ;;
  esac
}

function validate_seconds() {
  if ! printf '%s' "${1}" | grep -Eq '^[1-9][0-9]*$'; then
    log "❌ SECONDS must be a positive integer, got: ${1}"
    exit 1
  fi
}

function apply_set() {
  local -r knob="${1}"
  local -r seconds="${2}"
  intervals_set "${knob}" "${seconds}"
  log "✅ ${knob}=${seconds}s persisted to ${INTERVALS_FILE}"
  log '   (effective on next loop restart: make daft-orchestrator-down && make daft-orchestrator-up)'
}

main "${@:-}"
