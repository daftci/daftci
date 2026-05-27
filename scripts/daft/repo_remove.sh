#!/usr/bin/env bash
# repo_remove.sh
# Remove a repo entry from .daft/repos/registry.yaml and delete its state file.
# Args: NAME

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_repo_remove.log'
declare -r REGISTRY='.daft/repos/registry.yaml'

# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/repos_yaml.sh
. scripts/lib/daft/repos_yaml.sh
# shellcheck source=scripts/lib/daft/reload.sh
. scripts/lib/daft/reload.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local -r name="${1}"
  remove_repo "${name}"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -ne 1 ] || [ -z "${1:-}" ]; then
    log '❌ Usage: repo_remove.sh NAME'
    exit 1
  fi
}

function ensure_present() {
  local -r name="${1}"
  if ! registry_exists || ! registry_repo_exists "${name}"; then
    log "❌ Repo not registered: ${name}"
    exit 1
  fi
}

function strip_repo() {
  local -r name="${1}"
  yq -i "del(.repos[] | select(.name == \"${name}\"))" "${REGISTRY}"
}

function strip_state_file() {
  local -r name="${1}"
  rm -f ".daft/repos/state/${name}.json"
}

function remove_repo() {
  local -r name="${1}"
  ensure_present "${name}"
  log "🗑️  Removing repo: ${name}"
  strip_repo "${name}"
  strip_state_file "${name}"
  reload_bump_pending
  commit_local_or_push "repo_remove: ${name}" 3
  log "✅ Removed ${name}"
}

main "${@:-}"
