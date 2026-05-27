#!/usr/bin/env bash
# down.sh
# Stop coordinator + reaper by sending SIGTERM to the pids recorded in
# .daft/workspace/<name>.pid. Each daemon drains after its current tick.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_orchestrator_down.log'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  log '🛑 orchestrator down'
  stop_all
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

function stop_all() {
  stop_one 'coordinator'
  stop_one 'reaper'
  log '✅ stop requested (drains after current tick)'
}

function stop_one() {
  local -r name="${1}"
  local -r pidfile=".daft/workspace/${name}.pid"
  if [ ! -f "${pidfile}" ]; then
    log "  ℹ️  ${name}: no pidfile"
    return 0
  fi
  send_term "${name}" "${pidfile}"
}

function send_term() {
  local -r name="${1}"
  local -r pidfile="${2}"
  local pid
  pid="$(cat "${pidfile}")"
  if kill -0 "${pid}" 2>/dev/null; then
    kill -TERM "${pid}"
    log "  🛑 ${name}: SIGTERM sent to pid ${pid}"
  else
    log "  ℹ️  ${name}: pid ${pid} not running; clearing pidfile"
  fi
  rm -f "${pidfile}"
}

main "${@:-}"
