#!/usr/bin/env bats
# 010_tick_against_local_bare_repo.bats
# Coordinator tick against a single local bare upstream enqueues a job for a new commit.

load '../lib/setup'

setup() { daft_test_setup; }
teardown() { daft_test_teardown; }

@test "tick enqueues a job after first commit to upstream" {
  local bare="${TMPDIR_TEST}/upstream-foo.git"
  local work="${TMPDIR_TEST}/work-foo"
  make_local_bare "${bare}"
  build_workdir_with_job_script "${work}" 0 "${bare}"

  bash scripts/daft/repo_add.sh foo "${bare}" 'refs/heads/main'

  bash scripts/coordinator/tick.sh
  [ "$(count_queue_jobs)" = '1' ]

  local state_file
  state_file="$(find .daft/repos/state -name 'foo.json' -type f | head -1)"
  [ -n "${state_file}" ]
  grep -q '"reachability":"reachable"' "${state_file}"
}

@test "tick does not enqueue a duplicate when sha unchanged" {
  local bare="${TMPDIR_TEST}/upstream-bar.git"
  local work="${TMPDIR_TEST}/work-bar"
  make_local_bare "${bare}"
  build_workdir_with_job_script "${work}" 0 "${bare}"

  bash scripts/daft/repo_add.sh bar "${bare}" 'refs/heads/main'
  bash scripts/coordinator/tick.sh
  [ "$(count_queue_jobs)" = '1' ]

  bash scripts/coordinator/tick.sh
  [ "$(count_queue_jobs)" = '1' ]
}

@test "tick enqueues a second job after a new commit" {
  local bare="${TMPDIR_TEST}/upstream-baz.git"
  local work="${TMPDIR_TEST}/work-baz"
  make_local_bare "${bare}"
  build_workdir_with_job_script "${work}" 0 "${bare}"

  bash scripts/daft/repo_add.sh baz "${bare}" 'refs/heads/main'
  bash scripts/coordinator/tick.sh
  [ "$(count_queue_jobs)" = '1' ]

  commit_empty_to_workdir "${work}"
  bash scripts/coordinator/tick.sh
  [ "$(count_queue_jobs)" = '2' ]
}
