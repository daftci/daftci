#!/usr/bin/env bash
# claim.sh
# Attempt to claim ONE job from .daft/queue/x86_64/ for this runner.
# Implements the §7 reset-on-rejection protocol: on git-push rejection,
# git reset --hard origin/main and try the next candidate.
#
# Exit codes:
#   0 — claimed; prints job-id to stdout
#   1 — no eligible jobs this tick
#   2 — infrastructure error

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -r LOG_FILE='/tmp/daft_runner_claim.log'
declare -r SERVICE='daft-runner'

# shellcheck source=scripts/lib/daft/runner_id.sh
. scripts/lib/daft/runner_id.sh
# shellcheck source=scripts/lib/daft/git_lock.sh
. scripts/lib/daft/git_lock.sh
# shellcheck source=scripts/lib/daft/metrics.sh
. scripts/lib/daft/metrics.sh
# shellcheck source=scripts/lib/daft/time.sh
. scripts/lib/daft/time.sh
# shellcheck source=scripts/lib/daft/logger.sh
. scripts/lib/daft/logger.sh

function main() {
  exec 5>&1
  validate_args "${@:-}"
  claim
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

function claim() {
  local id
  id="$(read_runner_id)" || { log '❌ no runner id'; exit 2; }
  if has_origin_remote; then
    pull_rebase >/dev/null 2>&1 || true
  fi
  iterate_candidates "${id}"
}

function list_candidates() {
  if [ ! -d .daft/queue/x86_64 ]; then return 0; fi
  find .daft/queue/x86_64 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort
}

function iterate_candidates() {
  local -r id="${1}"
  local -r out_file=".daft/workspace/.last_claim_${id}.txt"
  rm -f "${out_file}"
  local f
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    if attempt_one "${id}" "${f}"; then
      printf '%s\n' "$(basename "${f}" .json)" > "${out_file}"
      exit 0
    fi
  done < <(list_candidates)
  exit 1
}

function attempt_one() {
  local -r id="${1}"
  local -r src="${2}"
  local job_id dest_dir
  job_id="$(basename "${src}" .json)"
  dest_dir=".daft/active/${id}/${job_id}"
  mkdir -p "${dest_dir}"
  mv "${src}" "${dest_dir}/job.json"
  write_initial_status "${dest_dir}"
  if ! commit_and_try_push "${id}" "${job_id}"; then
    handle_rejection "${id}" "${job_id}"
    return 1
  fi
  emit_claim_success "${id}" "${job_id}"
  return 0
}

function write_initial_status() {
  local -r dest_dir="${1}"
  local now
  now="$(utc_rfc3339_ns)"
  printf '{"phase":"claimed","claimed_at":"%s"}\n' "${now}" > "${dest_dir}/status.json"
}

function commit_and_try_push() {
  local -r id="${1}"
  local -r job_id="${2}"
  git add -A .daft/
  if git diff --cached --quiet; then return 0; fi
  git commit -m "claim: ${job_id} by ${id}" >/dev/null
  if has_origin_remote; then
    git push >/dev/null 2>&1
    return "${?}"
  fi
  return 0
}

function handle_rejection() {
  local -r id="${1}"
  local -r job_id="${2}"
  log_json "${SERVICE}" 'debug' 'claim push rejected; resetting' \
    "$(printf '"runner_id":"%s","job_id":"%s"' "${id}" "${job_id}")"
  metric_inc 'runner_claim_rejections_total'
  reset_to_origin >/dev/null 2>&1 || true
}

function emit_claim_success() {
  local -r id="${1}"
  local -r job_id="${2}"
  log "  🤝 claimed ${job_id}"
  log_json "${SERVICE}" 'info' 'job claimed' \
    "$(printf '"runner_id":"%s","job_id":"%s"' "${id}" "${job_id}")"
}

main "${@:-}"
