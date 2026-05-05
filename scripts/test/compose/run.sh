#!/usr/bin/env bash
# run.sh
# Top-level orchestrator for compose-based integration tests.
# Sequence: colima up → docker compose build/up → bootstrap → bats scenarios → down.
# Colima is left running on success so subsequent runs are fast; use the
# `compose-purge` Make target for full teardown.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_compose_run.log'
declare -r SCENARIOS='scripts/test/compose/scenarios'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  ensure_bats
  bash scripts/test/compose/lifecycle.sh up
  bash scripts/test/compose/up.sh
  trap on_exit EXIT
  run_scenarios
  log '✅ compose integration tests passed'
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
  if command -v bats >/dev/null 2>&1; then return 0; fi
  log '❌ bats not installed (brew install bats-core | apt-get install -y bats)'
  exit 1
}

function on_exit() {
  log '🧹 bringing compose stack down (volumes preserved)'
  bash scripts/test/compose/down.sh || true
}

function run_scenarios() {
  log "🧪 running bats scenarios under ${SCENARIOS}"
  bats --recursive --formatter pretty "${SCENARIOS}" 2>&1 | tee -a "${LOG_FILE}"
}

main "${@:-}"
