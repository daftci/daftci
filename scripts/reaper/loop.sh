#!/usr/bin/env bash
# loop.sh
# Outer reaper loop: while not stopped; tick; sleep REAPER_INTERVAL_SECONDS.
# Stop file is `.daft/workspace/reaper.stop` — touch it (or send SIGTERM) to
# request graceful shutdown after the current tick finishes.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_reaper.log'
declare -r STOP_FILE='.daft/workspace/reaper.stop'
declare -r TICK_SCRIPT='scripts/reaper/tick.sh'

# shellcheck source=scripts/lib/daft/intervals.sh
. scripts/lib/daft/intervals.sh
intervals_load

declare -rx REAPER_INTERVAL_SECONDS="${REAPER_INTERVAL_SECONDS:-30}"

function main() {
  exec 5>&1
  validate_args "${@:-}"
  setup_signals
  log '🚀 reaper loop start'
  loop
  log '✅ reaper loop exit'
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

function setup_signals() {
  mkdir -p .daft/workspace
  trap 'touch "${STOP_FILE}"' TERM
  trap 'log "🛑 SIGINT; exiting"; exit 0' INT
}

function should_stop() {
  [ -f "${STOP_FILE}" ]
}

function loop() {
  while ! should_stop; do
    bash "${TICK_SCRIPT}" || log '⚠️  tick exited non-zero'
    if should_stop; then break; fi
    sleep "${REAPER_INTERVAL_SECONDS}" || true
  done
  rm -f "${STOP_FILE}"
}

main "${@:-}"
