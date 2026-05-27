#!/usr/bin/env bash
# status.sh
# Report coordinator + reaper status from .daft/workspace/<name>.pid.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_orchestrator_status.log'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  report_all
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

function report_all() {
  report_one 'coordinator'
  report_one 'reaper'
}

function report_one() {
  local -r name="${1}"
  local -r pidfile=".daft/workspace/${name}.pid"
  if [ ! -f "${pidfile}" ]; then
    log "${name}: not running (no pidfile)"
    return 0
  fi
  inspect "${name}" "${pidfile}"
}

function inspect() {
  local -r name="${1}"
  local -r pidfile="${2}"
  local pid
  pid="$(cat "${pidfile}")"
  if kill -0 "${pid}" 2>/dev/null; then
    log "${name}: running (pid=${pid})"
  else
    log "${name}: stale pidfile (pid=${pid} not alive)"
  fi
}

main "${@:-}"
