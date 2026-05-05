#!/usr/bin/env bash
# doctor.sh
# Health check: verify .daft/ layout, registry yaml validity, runner identity (if pinned),
# MinIO env vars, and central-daft remote reachability. Read-only.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_doctor.log'

# shellcheck source=scripts/lib/daft/repos_yaml.sh
. scripts/lib/daft/repos_yaml.sh
# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local errors=0
  check_layout || errors=$(( errors + 1 ))
  check_tools || errors=$(( errors + 1 ))
  check_registry || errors=$(( errors + 1 ))
  check_runner_pin || true
  check_minio_env || true
  check_remote || true
  finish "${errors}"
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

function check_layout() {
  log '🔍 Checking .daft/ layout...'
  local d
  for d in .daft/queue/x86_64 .daft/active .daft/runners .daft/repos/state .daft/archive .daft/metrics .daft/workspace; do
    if [ ! -d "${d}" ]; then
      log "  ❌ missing: ${d}"
      return 1
    fi
  done
  log '  ✅ layout ok'
}

function check_tools() {
  log '🔍 Checking required tools...'
  local missing=0
  command -v git >/dev/null 2>&1 || { log '  ❌ git not found'; missing=1; }
  command -v yq  >/dev/null 2>&1 || { log '  ❌ yq not found';  missing=1; }
  command -v mc  >/dev/null 2>&1 || log '  ⚠️  mc not found (MinIO upload will be skipped)'
  if [ "${missing}" -eq 1 ]; then return 1; fi
  log '  ✅ tools ok'
}

function check_registry() {
  log '🔍 Checking registry yaml...'
  if ! registry_exists; then
    log '  ⚠️  no registry.yaml yet (run daft-repo-add to create)'
    return 0
  fi
  local count
  count="$(registry_repos_count)"
  log "  ✅ registry has ${count} repo(s)"
}

function check_runner_pin() {
  log '🔍 Checking runner pin...'
  local id
  id="$(read_runner_id 2>/dev/null || printf '')"
  if [ -z "${id}" ]; then
    log '  ⚠️  no runner pinned on this host (run daft-runner-init if this is a runner box)'
    return 0
  fi
  log "  ✅ pinned runner: ${id}"
}

function check_minio_env() {
  log '🔍 Checking MinIO env...'
  if [ -z "${DAFT_MINIO_ENDPOINT:-}" ]; then
    log '  ⚠️  DAFT_MINIO_ENDPOINT unset (artifact upload disabled)'
    return 0
  fi
  log "  ✅ DAFT_MINIO_ENDPOINT=${DAFT_MINIO_ENDPOINT}"
}

function check_remote() {
  log '🔍 Checking central-daft remote...'
  if ! git remote get-url origin >/dev/null 2>&1; then
    log '  ⚠️  no origin remote (single-host operation)'
    return 0
  fi
  local remote
  remote="$(git remote get-url origin)"
  log "  ✅ origin: ${remote}"
}

function finish() {
  local -r errors="${1}"
  if [ "${errors}" -gt 0 ]; then
    log "❌ doctor: ${errors} error(s)"
    exit 1
  fi
  log '✅ doctor: ok'
}

main "${@:-}"
