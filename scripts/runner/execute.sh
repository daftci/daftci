#!/usr/bin/env bash
# execute.sh
# Clone work repo at the job's sha, run .daft/jobs/build under timeout, capture
# stdout/stderr to .daft/workspace/<job-id>.log, record exit code.
# Args: JOB_ID (must already be in .daft/active/<my-id>/<JOB_ID>/)

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner_execute.log'
declare -rx DAFT_TIMEOUT_SECONDS="${DAFT_TIMEOUT_SECONDS:-3600}"
declare -r SERVICE='daft-runner'

# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh
# shellcheck source=scripts/lib/daft/clone.sh
. scripts/lib/daft/clone.sh
# shellcheck source=scripts/lib/daft/time.sh
. scripts/lib/daft/time.sh
# shellcheck source=scripts/lib/daft/logger.sh
. scripts/lib/daft/logger.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local -r job_id="${1}"
  do_execute "${job_id}"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a "${LOG_FILE}" >&5
}

function validate_args() {
  if [ "${#}" -ne 1 ] || [ -z "${1:-}" ]; then
    log '❌ Usage: execute.sh JOB_ID'
    exit 1
  fi
}

function do_execute() {
  local -r job_id="${1}"
  local id job_dir
  id="$(read_runner_id)" || { log '❌ no runner id'; exit 1; }
  job_dir=".daft/active/${id}/${job_id}"
  if [ ! -f "${job_dir}/job.json" ]; then
    log "❌ no claimed job at ${job_dir}"
    exit 1
  fi
  run_phase "${id}" "${job_id}" "${job_dir}"
}

function run_phase() {
  local -r id="${1}"
  local -r job_id="${2}"
  local -r job_dir="${3}"
  mark_executing "${job_dir}"
  emit_execute_start "${id}" "${job_id}"
  do_clone_and_run "${id}" "${job_id}" "${job_dir}"
}

function mark_executing() {
  local -r job_dir="${1}"
  local now
  now="$(utc_rfc3339_ns)"
  printf '{"phase":"executing","started_at":"%s"}\n' "${now}" > "${job_dir}/status.json"
}

function emit_execute_start() {
  local -r id="${1}"
  local -r job_id="${2}"
  log "  🛠️  executing ${job_id}"
  log_json "${SERVICE}" 'info' 'job execute start' \
    "$(printf '"runner_id":"%s","job_id":"%s"' "${id}" "${job_id}")"
}

function do_clone_and_run() {
  local -r id="${1}"
  local -r job_id="${2}"
  local -r job_dir="${3}"
  local clone_url ref sha checkout
  clone_url="$(yq -r '.clone_url' "${job_dir}/job.json")"
  ref="$(yq -r '.ref' "${job_dir}/job.json")"
  sha="$(yq -r '.sha' "${job_dir}/job.json")"
  checkout=".daft/workspace/${job_id}.checkout"
  prepare_checkout "${clone_url}" "${sha}" "${checkout}" "${job_dir}" || return 0
  invoke_job_script "${id}" "${job_id}" "${job_dir}" "${checkout}" "${clone_url}" "${ref}" "${sha}"
}

function prepare_checkout() {
  local -r clone_url="${1}"
  local -r sha="${2}"
  local -r checkout="${3}"
  local -r job_dir="${4}"
  if clone_at_sha "${clone_url}" "${sha}" "${checkout}" >/dev/null 2>&1; then
    return 0
  fi
  finalize_status "${job_dir}" 'clone_failed' '125'
  return 1
}

function invoke_job_script() {
  local -r id="${1}"
  local -r job_id="${2}"
  local -r job_dir="${3}"
  local -r checkout="${4}"
  local -r clone_url="${5}"
  local -r ref="${6}"
  local -r sha="${7}"
  local artifacts script
  artifacts="${PWD}/${checkout}/artifacts"
  script="${checkout}/.daft/jobs/build"
  mkdir -p "${artifacts}"
  if [ ! -x "${script}" ]; then
    finalize_status "${job_dir}" 'script_missing' '127'
    return 0
  fi
  run_with_timeout "${id}" "${job_id}" "${job_dir}" "${checkout}" "${clone_url}" "${ref}" "${sha}" "${artifacts}"
}

function run_with_timeout() {
  local -r id="${1}"
  local -r job_id="${2}"
  local -r job_dir="${3}"
  local -r checkout="${4}"
  local -r clone_url="${5}"
  local -r ref="${6}"
  local -r sha="${7}"
  local -r artifacts="${8}"
  local -r log_path="${PWD}/.daft/workspace/${job_id}.log"
  invoke_then_finalize "${job_dir}" "${checkout}" "${log_path}" \
      "${id}" "${job_id}" "${clone_url}" "${ref}" "${sha}" "${artifacts}"
}

function invoke_then_finalize() {
  local -r job_dir="${1}"
  local -r checkout="${2}"
  local -r log_path="${3}"
  shift 3
  local exit_code=0
  invoke_in_checkout "${checkout}" "${log_path}" "$@" || exit_code="${?}"
  finalize_status "${job_dir}" "$(phase_for_exit "${exit_code}")" "${exit_code}"
}

function invoke_in_checkout() {
  local -r checkout="${1}"
  local -r log_path="${2}"
  shift 2
  ( cd "${checkout}" \
      && export_job_env "$@" \
      && with_timeout "${DAFT_TIMEOUT_SECONDS}" ./.daft/jobs/build ) \
      >> "${log_path}" 2>&1
}

function export_job_env() {
  local -r id="${1}"
  local -r job_id="${2}"
  local -r clone_url="${3}"
  local -r ref="${4}"
  local -r sha="${5}"
  local -r artifacts="${6}"
  export DAFT_JOB_ID="${job_id}" DAFT_REPO_NAME="${job_id%-*}" \
         DAFT_CLONE_URL="${clone_url}" DAFT_REF="${ref}" DAFT_SHA="${sha}" \
         DAFT_RUNNER_ID="${id}" DAFT_ARTIFACTS_DIR="${artifacts}"
}

function with_timeout() {
  local -r seconds="${1}"
  shift
  local rc=0
  if command -v timeout >/dev/null 2>&1; then
    timeout "${seconds}" "$@" || rc="${?}"
    return "${rc}"
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${seconds}" "$@" || rc="${?}"
    return "${rc}"
  fi
  "$@" || rc="${?}"
  return "${rc}"
}

function phase_for_exit() {
  local -r code="${1}"
  case "${code}" in
    0)   printf 'succeeded' ;;
    124) printf 'timeout' ;;
    125|126|127) printf 'script_missing' ;;
    *)   printf 'failed' ;;
  esac
}

function finalize_status() {
  local -r job_dir="${1}"
  local -r phase="${2}"
  local -r exit_code="${3}"
  local now
  now="$(utc_rfc3339_ns)"
  printf '{"phase":"%s","exit_code":%s,"finished_at":"%s"}\n' "${phase}" "${exit_code}" "${now}" \
    > "${job_dir}/status.json"
}

main "${@:-}"
