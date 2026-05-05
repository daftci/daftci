#!/usr/bin/env bash
# run.sh
# DAFt integration test dispatcher: find and run every .bats file under
# scripts/test/integration/. Skips with warning if `bats` is not installed.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_integration.log'
declare -r ROOT='scripts/test/integration'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  ensure_bats
  run_bats
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

function ensure_bats() {
  if command -v bats >/dev/null 2>&1; then
    return 0
  fi
  log '⚠️  bats not installed; skipping integration tests'
  log '    install: brew install bats-core  (macOS)'
  log '             apt-get install -y bats (Linux)'
  exit 0
}

function run_bats() {
  log '🧪 running DAFt integration tests...'
  bats --recursive --formatter pretty "${ROOT}"
}

main "${@:-}"
