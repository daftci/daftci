#!/usr/bin/env bash
# up.sh
# Start coordinator + reaper as background processes with PID files. Idempotent:
# if a daemon's pidfile exists and the process is alive, leave it running.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_orchestrator_up.log'

# shellcheck source=scripts/lib/daft/intervals.sh
. scripts/lib/daft/intervals.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  log '🚀 orchestrator up'
  intervals_load
  start_all
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

function start_all() {
  mkdir -p .daft/workspace
  start_one 'coordinator' 'scripts/coordinator/loop.sh'
  start_one 'reaper' 'scripts/reaper/loop.sh'
  log '✅ orchestrator up'
}

function start_one() {
  local -r name="${1}"
  local -r script="${2}"
  local -r pidfile=".daft/workspace/${name}.pid"
  if already_running "${pidfile}"; then
    log "  ℹ️  ${name} already running (pid=$(cat "${pidfile}"))"
    return 0
  fi
  spawn "${name}" "${script}" "${pidfile}"
}

function already_running() {
  local -r pidfile="${1}"
  [ -f "${pidfile}" ] && kill -0 "$(cat "${pidfile}")" 2>/dev/null
}

function spawn() {
  local -r name="${1}"
  local -r script="${2}"
  local -r pidfile="${3}"
  local -r out_log=".daft/workspace/${name}.out"
  nohup bash "${script}" >>"${out_log}" 2>&1 &
  printf '%s\n' "${!}" > "${pidfile}"
  log "  🚀 ${name} started (pid=$(cat "${pidfile}"), log=${out_log})"
}

main "${@:-}"
