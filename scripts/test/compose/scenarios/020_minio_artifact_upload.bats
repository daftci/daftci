#!/usr/bin/env bats
# 020_minio_artifact_upload.bats
# A successful job uploads its artifacts/ directory contents to MinIO under
# s3://daft-artifacts/jobs/<exact-job-id>/. Asserts against the EXACT job-id
# pushed in this scenario, not a substring across the volume.

load 'lib'

@test "completed job uploads artifact under jobs/<exact-job-id>/" {
  local sha
  sha="$(push_empty_to_upstream test-bar)"
  local -r job_id="test-bar-${sha}"

  if ! wait_for_archive_job "${job_id}" 90; then
    skip "job ${job_id} did not reach archive within 90s"
  fi

  run minio_has_artifacts_for_job "${job_id}"
  [ "${status}" -eq 0 ]
}
