#!/usr/bin/env bash
# up.sh
# Render scripts/test/compose/.env from config.yaml, build the daft-runtime
# image, start MinIO, run bootstrap, then start the loop services.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_compose_up.log'
declare -r CONFIG='scripts/test/compose/config.yaml'
declare -r ENV_FILE='scripts/test/compose/.env'
declare -r COMPOSE_FILE='scripts/test/compose/docker-compose.yaml'
declare -r DOCKERFILE='scripts/test/compose/Dockerfile'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  ensure_docker
  write_env
  build_image
  start_stack
  bootstrap
  log '✅ compose stack up'
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

function ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log '❌ docker not found'
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    log '❌ docker daemon not reachable (run: make compose-lifecycle ARG=up)'
    exit 1
  fi
}

function image_uri() {
  local -r key="${1}"
  printf '%s/%s:%s' \
    "$(yq -r ".images.${key}.registry" "${CONFIG}")" \
    "$(yq -r ".images.${key}.repository" "${CONFIG}")" \
    "$(yq -r ".images.${key}.tag" "${CONFIG}")"
}

function write_env() {
  log '📝 rendering .env from config.yaml'
  {
    printf 'COMPOSE_PROJECT_NAME=%s\n' "$(yq -r '.compose.project_name' "${CONFIG}")"
    printf 'BASE_IMAGE=%s\n'  "$(image_uri base)"
    printf 'MINIO_IMAGE=%s\n' "$(image_uri minio)"
    printf 'MC_IMAGE=%s\n'    "$(image_uri mc)"
    write_env_runtime
    write_env_minio
  } > "${ENV_FILE}"
}

function write_env_runtime() {
  printf 'RUNNER_INTERVAL_SECONDS=%s\n'      "$(yq -r '.runtime.runner_interval_seconds' "${CONFIG}")"
  printf 'COORDINATOR_INTERVAL_SECONDS=%s\n' "$(yq -r '.runtime.coordinator_interval_seconds' "${CONFIG}")"
  printf 'REAPER_INTERVAL_SECONDS=%s\n'      "$(yq -r '.runtime.reaper_interval_seconds' "${CONFIG}")"
  printf 'REAPER_THRESHOLD_SECONDS=%s\n'     "$(yq -r '.runtime.reaper_threshold_seconds' "${CONFIG}")"
  printf 'JOB_TIMEOUT_SECONDS=%s\n'          "$(yq -r '.runtime.job_timeout_seconds' "${CONFIG}")"
}

function write_env_minio() {
  printf 'MINIO_ACCESS_KEY=%s\n'        "$(yq -r '.minio.access_key' "${CONFIG}")"
  printf 'MINIO_SECRET_KEY=%s\n'        "$(yq -r '.minio.secret_key' "${CONFIG}")"
  printf 'MINIO_BUCKET=%s\n'            "$(yq -r '.minio.bucket' "${CONFIG}")"
  printf 'MINIO_ENDPOINT_INTERNAL=%s\n' "$(yq -r '.minio.endpoint_internal' "${CONFIG}")"
}

function build_image() {
  log '🛠️  building daft-runtime:test image'
  docker build --quiet \
    --build-arg "BASE_IMAGE=$(image_uri base)" \
    -t daft-runtime:test \
    -f "${DOCKERFILE}" \
    "$(dirname "${DOCKERFILE}")"
}

function compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

function start_stack() {
  log '🚀 starting MinIO and test-driver'
  compose up -d minio test-driver
}

function bootstrap() {
  log '🌱 running bootstrap inside test-driver'
  compose exec -T test-driver bash /repo/scripts/test/compose/bootstrap.sh
  log '🚀 starting coordinator, reaper, runners'
  compose up -d coordinator reaper runner-a runner-b runner-c
}

main "${@:-}"
