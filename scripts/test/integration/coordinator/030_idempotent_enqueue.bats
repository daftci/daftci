#!/usr/bin/env bats
# 030_idempotent_enqueue.bats
# Once a job exists in queue, active, or archive, the coordinator must not
# re-enqueue it for the same sha.

load '../lib/setup'

setup() { daft_test_setup; }
teardown() { daft_test_teardown; }

@test "job in active is not re-enqueued" {
  local bare="${TMPDIR_TEST}/upstream-idem.git"
  local work="${TMPDIR_TEST}/work-idem"
  make_local_bare "${bare}"
  build_workdir_with_job_script "${work}" 0 "${bare}"
  bash scripts/daft/repo_add.sh idem "${bare}" 'refs/heads/main'
  bash scripts/coordinator/tick.sh

  local job_file job_id
  job_file="$(find .daft/queue/x86_64 -type f -name 'idem-*.json' | head -1)"
  job_id="$(basename "${job_file}" .json)"
  mkdir -p ".daft/active/fake-runner/${job_id}"
  mv "${job_file}" ".daft/active/fake-runner/${job_id}/job.json"

  bash scripts/coordinator/tick.sh
  [ "$(count_queue_jobs)" = '0' ]
}
