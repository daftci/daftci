#!/usr/bin/env bash
# down.sh
# Tear down the compose stack. Preserves named volumes so a subsequent `up`
# replays state. Use `purge` (separate Make target) for full wipe.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_compose_down.log'
declare -r ENV_FILE='scripts/test/compose/.env'
declare -r COMPOSE_FILE='scripts/test/compose/docker-compose.yaml'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  bring_down
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

function bring_down() {
  if ! command -v docker >/dev/null 2>&1; then
    log 'ℹ️  docker not present; nothing to do'
    return 0
  fi
  if [ ! -f "${ENV_FILE}" ]; then
    log 'ℹ️  no .env file; stack was never up'
    return 0
  fi
  log '🛑 docker compose down (volumes preserved)'
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down --remove-orphans
}

main "${@:-}"
