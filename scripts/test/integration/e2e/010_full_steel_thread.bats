#!/usr/bin/env bats
# 010_full_steel_thread.bats
# End-to-end MVP steel thread: register two upstreams, coordinator-tick to enqueue,
# runner-tick to claim+execute+release, verify archive and status.

load '../lib/setup'

setup() { daft_test_setup; }
teardown() { daft_test_teardown; }

@test "full steel thread: 2 repos, 2 jobs, all archived successfully" {
  local bare_a="${TMPDIR_TEST}/up-a.git"
  local work_a="${TMPDIR_TEST}/wk-a"
  local bare_b="${TMPDIR_TEST}/up-b.git"
  local work_b="${TMPDIR_TEST}/wk-b"
  make_local_bare "${bare_a}"
  make_local_bare "${bare_b}"
  build_workdir_with_job_script "${work_a}" 0 "${bare_a}"
  build_workdir_with_job_script "${work_b}" 0 "${bare_b}"

  bash scripts/daft/repo_add.sh repo-a "${bare_a}" 'refs/heads/main'
  bash scripts/daft/repo_add.sh repo-b "${bare_b}" 'refs/heads/main'

  bash scripts/coordinator/tick.sh
  [ "$(count_queue_jobs)" = '2' ]

  local id
  id="$(bash scripts/daft/runner_init.sh | tail -1)"
  export DAFT_RUNNER_ID="${id}"

  bash scripts/runner/tick.sh
  bash scripts/runner/tick.sh

  local today
  today="$(date -u '+%Y-%m-%d')"
  local count
  count="$(find ".daft/archive/${today}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  [ "${count}" = '2' ]
  [ "$(count_queue_jobs)" = '0' ]

  while IFS= read -r s; do
    grep -q '"phase":"succeeded"' "${s}"
  done < <(find ".daft/archive/${today}" -name status.json -type f)
}
