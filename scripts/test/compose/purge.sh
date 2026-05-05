#!/usr/bin/env bash
# purge.sh
# Full wipe: docker compose down -v (removes named volumes), then optionally
# stop colima. Useful for "I want a totally clean slate".

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_compose_purge.log'
declare -r ENV_FILE='scripts/test/compose/.env'
declare -r COMPOSE_FILE='scripts/test/compose/docker-compose.yaml'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  do_purge
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

function do_purge() {
  if [ -f "${ENV_FILE}" ] && command -v docker >/dev/null 2>&1; then
    log '🧨 docker compose down -v (volumes destroyed)'
    docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down -v --remove-orphans || true
  fi
  rm -f "${ENV_FILE}"
  bash scripts/test/compose/lifecycle.sh down || true
  log '✅ purge complete'
}

main "${@:-}"
