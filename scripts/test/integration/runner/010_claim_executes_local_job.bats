#!/usr/bin/env bats
# 010_claim_executes_local_job.bats
# A runner claims a queued job, executes daft/jobs/build, captures its output, and
# leaves a status reflecting the exit code.

load '../lib/setup'

setup() { daft_test_setup; }
teardown() { daft_test_teardown; }

@test "runner tick claims, executes, and releases a successful job" {
  local bare="${TMPDIR_TEST}/upstream-ok.git"
  local work="${TMPDIR_TEST}/work-ok"
  make_local_bare "${bare}"
  build_workdir_with_job_script "${work}" 0 "${bare}"
  bash scripts/daft/repo_add.sh ok "${bare}" 'refs/heads/main'
  bash scripts/coordinator/tick.sh

  local id
  id="$(bash scripts/daft/runner_init.sh | tail -1)"
  export DAFT_RUNNER_ID="${id}"

  bash scripts/runner/tick.sh

  local today
  today="$(date -u '+%Y-%m-%d')"
  local archived
  archived="$(find ".daft/archive/${today}" -type d -name 'ok-*' | head -1)"
  [ -n "${archived}" ]
  grep -q '"phase":"succeeded"' "${archived}/status.json"
  grep -q 'hello from build' "${archived}/job.log"
}

@test "runner tick captures non-zero exit as failed phase" {
  local bare="${TMPDIR_TEST}/upstream-fail.git"
  local work="${TMPDIR_TEST}/work-fail"
  make_local_bare "${bare}"
  build_workdir_with_job_script "${work}" 7 "${bare}"
  bash scripts/daft/repo_add.sh fail "${bare}" 'refs/heads/main'
  bash scripts/coordinator/tick.sh

  local id
  id="$(bash scripts/daft/runner_init.sh | tail -1)"
  export DAFT_RUNNER_ID="${id}"

  bash scripts/runner/tick.sh

  local today archived
  today="$(date -u '+%Y-%m-%d')"
  archived="$(find ".daft/archive/${today}" -type d -name 'fail-*' | head -1)"
  [ -n "${archived}" ]
  grep -q '"phase":"failed"' "${archived}/status.json"
  grep -q '"exit_code":7' "${archived}/status.json"
}
