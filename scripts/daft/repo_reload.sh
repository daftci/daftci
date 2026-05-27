#!/usr/bin/env bash
# repo_reload.sh
# Manually bump the reload tick so watching daemons drop caches on next tick.
# Idempotent (each invocation produces a new bump).

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_repo_reload.log'

# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/reload.sh
. scripts/lib/daft/reload.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  bump_and_commit
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

function bump_and_commit() {
  log '🔔 bumping reload tick'
  reload_bump_pending
  commit_local_or_push 'repo_reload: bump' 3
  log "✅ reload tick now $(reload_current_tick)"
}

main "${@:-}"
