#!/usr/bin/env bash
# repo_add.sh
# Add a repo entry to .daft/repos/registry.yaml and commit (or commit+push if remote).
# Args: NAME CLONE_URL REF

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_repo_add.log'
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
  local -r url="${2}"
  local -r ref="${3}"
  add_repo "${name}" "${url}" "${ref}"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -ne 3 ]; then
    log '❌ Usage: repo_add.sh NAME CLONE_URL REF'
    exit 1
  fi
  if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
    log '❌ Error: empty argument'
    exit 1
  fi
}

function validate_name() {
  local -r name="${1}"
  if ! printf '%s' "${name}" | grep -Eq '^[a-z0-9-]+$'; then
    log "❌ Invalid name: ${name} (must match [a-z0-9-]+)"
    exit 1
  fi
}

function ensure_registry() {
  if [ ! -f "${REGISTRY}" ]; then
    mkdir -p .daft/repos
    printf 'version: 1\nrepos: []\n' > "${REGISTRY}"
  fi
}

function ensure_unique() {
  local -r name="${1}"
  if registry_exists && registry_repo_exists "${name}"; then
    log "❌ Repo already registered: ${name}"
    exit 1
  fi
}

function append_repo() {
  local -r name="${1}"
  local -r url="${2}"
  local -r ref="${3}"
  yq -i ".repos += [{\"name\":\"${name}\",\"clone_url\":\"${url}\",\"ref\":\"${ref}\"}]" "${REGISTRY}"
}

function add_repo() {
  local -r name="${1}"
  local -r url="${2}"
  local -r ref="${3}"
  validate_name "${name}"
  ensure_registry
  ensure_unique "${name}"
  log "📥 Adding repo: ${name} ${url} ${ref}"
  append_repo "${name}" "${url}" "${ref}"
  reload_bump_pending
  commit_local_or_push "repo_add: ${name}" 3
  log "✅ Added ${name}"
}

main "${@:-}"
