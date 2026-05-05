#!/usr/bin/env bash
# check_repo.sh
# Single-repo subroutine: git ls-remote a registered repo and emit one JSON line
# describing the result on stdout. No filesystem mutations beyond /tmp log.
# Args: NAME (must be present in .daft/repos/registry.yaml)

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_coordinator_check_repo.log'

# shellcheck source=scripts/lib/daft/repos_yaml.sh
. scripts/lib/daft/repos_yaml.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local -r name="${1}"
  check_one "${name}"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -ne 1 ] || [ -z "${1:-}" ]; then
    log '❌ Usage: check_repo.sh NAME'
    exit 1
  fi
}

function check_one() {
  local -r name="${1}"
  local url ref
  url="$(registry_repo_field "${name}" 'clone_url')"
  ref="$(registry_repo_field "${name}" 'ref')"
  if [ -z "${url}" ] || [ -z "${ref}" ]; then
    emit "${name}" 'false' '' 'unknown_repo'
    return 0
  fi
  do_ls_remote_and_emit "${name}" "${url}" "${ref}"
}

function do_ls_remote_and_emit() {
  local -r name="${1}"
  local -r url="${2}"
  local -r ref="${3}"
  local output
  local exit_code=0
  output="$(GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code "${url}" "${ref}" 2>&1)" || exit_code="${?}"
  classify "${name}" "${exit_code}" "${output}"
}

function classify() {
  local -r name="${1}"
  local -r exit_code="${2}"
  local -r output="${3}"
  if [ "${exit_code}" -eq 0 ]; then
    emit_parsed "${name}" "${output}"
    return 0
  fi
  if [ "${exit_code}" -eq 2 ]; then
    emit "${name}" 'true' '' 'ref_missing'
    return 0
  fi
  emit "${name}" 'false' '' "$(printf '%s' "${output}" | head -1)"
}

function emit_parsed() {
  local -r name="${1}"
  local -r output="${2}"
  local sha
  sha="$(printf '%s' "${output}" | awk 'NR==1{print $1}')"
  if [ -z "${sha}" ]; then
    emit "${name}" 'true' '' 'ref_missing'
    return 0
  fi
  emit "${name}" 'true' "${sha}" ''
}

function emit() {
  local -r name="${1}"
  local -r ok="${2}"
  local -r sha="${3}"
  local -r err="${4}"
  printf '{"name":"%s","ok":%s,"sha":"%s","error":"%s"}\n' \
    "${name}" "${ok}" "${sha}" "${err//\"/\\\"}"
}

main "${@:-}"
