#!/usr/bin/env bash
# artifacts.sh
# MinIO artifact upload helpers for DAFt runners. Requires `mc`.
# Source this file; do not execute directly.

function artifacts_push() {
  local -r job_id="${1}"
  local -r src_dir="${2}"
  if [ -z "${DAFT_MINIO_ENDPOINT:-}" ]; then
    artifacts_skipped 'no_endpoint'
    return 0
  fi
  if [ ! -d "${src_dir}" ]; then
    artifacts_skipped 'no_artifacts_dir'
    return 0
  fi
  artifacts_push_via_mc "${job_id}" "${src_dir}"
}

function artifacts_skipped() {
  local -r reason="${1}"
  printf '{"status":"skipped","reason":"%s","file_count":0}\n' "${reason}"
}

function artifacts_push_via_mc() {
  local -r job_id="${1}"
  local -r src_dir="${2}"
  artifacts_mc_alias_set
  artifacts_mc_cp "${job_id}" "${src_dir}"
}

function artifacts_mc_alias_set() {
  mc alias set 'daft' \
    "${DAFT_MINIO_ENDPOINT}" \
    "${DAFT_MINIO_ACCESS_KEY:-}" \
    "${DAFT_MINIO_SECRET_KEY:-}" \
    >/dev/null 2>&1
}

function artifacts_file_count() {
  local -r src_dir="${1}"
  find "${src_dir}" -type f 2>/dev/null | wc -l | tr -d ' '
}

function artifacts_mc_cp() {
  local -r job_id="${1}"
  local -r src_dir="${2}"
  local -r bucket="${DAFT_MINIO_BUCKET:-daft-artifacts}"
  local file_count
  file_count="$(artifacts_file_count "${src_dir}")"
  if mc cp --recursive --quiet "${src_dir}/" "daft/${bucket}/jobs/${job_id}/" >/dev/null 2>&1; then
    printf '{"status":"uploaded","bucket":"%s","prefix":"jobs/%s/","file_count":%s}\n' "${bucket}" "${job_id}" "${file_count}"
    return 0
  fi
  printf '{"status":"failed","bucket":"%s","prefix":"jobs/%s/","file_count":%s}\n' "${bucket}" "${job_id}" "${file_count}"
}
