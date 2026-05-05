#!/usr/bin/env bats
# 020_edge_triggered_reachability.bats
# Verify that reachability transitions are logged exactly once per edge,
# and that steady-state silence holds.

load '../lib/setup'

setup() { daft_test_setup; }
teardown() { daft_test_teardown; }

@test "unreachable repo logs 'unreachable' exactly once across multiple ticks" {
  bash scripts/daft/repo_add.sh ghost "${TMPDIR_TEST}/does-not-exist.git" 'refs/heads/main'

  bash scripts/coordinator/tick.sh
  bash scripts/coordinator/tick.sh
  bash scripts/coordinator/tick.sh

  local count
  count="$(grep -c '"new_reachability":"unreachable".*"repo_name":"ghost"' .daft/workspace/daft-coordinator.jsonl 2>/dev/null || printf '0')"
  [ "${count}" = '1' ]
}

@test "becoming reachable logs 'recovered' exactly once" {
  local bare="${TMPDIR_TEST}/upstream-flap.git"
  local work="${TMPDIR_TEST}/work-flap"
  bash scripts/daft/repo_add.sh flap "${TMPDIR_TEST}/upstream-flap.git" 'refs/heads/main'

  bash scripts/coordinator/tick.sh
  grep -q '"new_reachability":"unreachable"' .daft/workspace/daft-coordinator.jsonl

  make_local_bare "${bare}"
  build_workdir_with_job_script "${work}" 0 "${bare}"

  bash scripts/coordinator/tick.sh
  bash scripts/coordinator/tick.sh

  local recovered
  recovered="$(grep -c '"new_reachability":"reachable".*"repo_name":"flap"' .daft/workspace/daft-coordinator.jsonl)"
  [ "${recovered}" = '1' ]
}
