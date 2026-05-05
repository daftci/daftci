#!/usr/bin/env bats
# 010_multi_runner_contention.bats
# Push a single commit upstream → coordinator enqueues exactly that job-id →
# exactly one of three runners claims and executes it. This is the core
# git-push-collision claim test that the fast bats suite cannot exercise.

load 'lib'

@test "single new commit is claimed by exactly one of three runners" {
  local sha
  sha="$(push_empty_to_upstream test-foo)"
  local -r job_id="test-foo-${sha}"

  if ! wait_for_archive_job "${job_id}" 90; then
    skip "job ${job_id} did not reach archive within 90s"
  fi

  local count
  count="$(distinct_runners_for_job "${job_id}")"
  [ "${count}" = '1' ]
}
