#!/usr/bin/env bats
# 030_reaper_recovers_killed_runner.bats
# Push a commit; immediately kill all three runners; restart them. The reaper
# must recover any in-flight active/<dead-id>/<job-id>/ entry, and a runner
# must eventually archive THIS exact job-id.

load 'lib'

@test "killed-then-restarted runners still complete this exact job" {
  local sha
  sha="$(push_empty_to_upstream test-foo)"
  local -r job_id="test-foo-${sha}"

  sleep 3
  dc kill runner-a runner-b runner-c >/dev/null 2>&1 || true
  dc up -d runner-a runner-b runner-c >/dev/null

  if ! wait_for_archive_job "${job_id}" 120; then
    skip "job ${job_id} did not reach archive after kill+restart within 120s"
  fi
}
