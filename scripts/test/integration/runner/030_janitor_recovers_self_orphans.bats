#!/usr/bin/env bats
# 030_janitor_recovers_self_orphans.bats
# The runner janitor sweeps its own active/ namespace and returns orphans to queue.

load '../lib/setup'

setup() { daft_test_setup; }
teardown() { daft_test_teardown; }

@test "janitor recovers a hand-crafted orphan back to queue" {
  local id
  id="$(bash scripts/daft/runner_init.sh | tail -1)"
  export DAFT_RUNNER_ID="${id}"

  mkdir -p ".daft/active/${id}/orphan-job"
  printf '{"job_id":"orphan-job"}\n' > ".daft/active/${id}/orphan-job/job.json"

  bash scripts/runner/janitor.sh

  [ -f .daft/queue/x86_64/orphan-job.json ]
  [ ! -d ".daft/active/${id}/orphan-job" ]
}

@test "janitor with empty active is a no-op" {
  local id
  id="$(bash scripts/daft/runner_init.sh | tail -1)"
  export DAFT_RUNNER_ID="${id}"

  bash scripts/runner/janitor.sh

  [ "$(count_queue_jobs)" = '0' ]
}
