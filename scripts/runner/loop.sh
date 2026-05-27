#!/usr/bin/env bash
# loop.sh
# Outer runner loop: run janitor once at startup, then while not stopped; tick;
# sleep RUNNER_INTERVAL_SECONDS. Stop file is `.daft/workspace/runner-<id>.stop`.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner.log'
declare -r STOP_FILE='.daft/workspace/runner.stop'

# shellcheck source=scripts/lib/daft/intervals.sh
. scripts/lib/daft/intervals.sh
intervals_load

declare -rx RUNNER_INTERVAL_SECONDS="${RUNNER_INTERVAL_SECONDS:-5}"

# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local id
  id="$(read_runner_id)" || { log '❌ no runner id'; exit 1; }
  setup_signals
  log "🚀 runner loop start (id=${id})"
  bash scripts/runner/janitor.sh || log '⚠️  janitor failed'
  loop
  log '✅ runner loop exit'
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

function loop() {
  while [ ! -f "${STOP_FILE}" ]; do
    bash scripts/runner/tick.sh || log '⚠️  tick exited non-zero'
    [ -f "${STOP_FILE}" ] && break
    sleep "${RUNNER_INTERVAL_SECONDS}" || true
  done
  rm -f "${STOP_FILE}"
}

main "${@:-}"
