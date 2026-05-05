#!/usr/bin/env bats
# 010_reaps_stale_runner.bats
# A runner whose heartbeat is older than threshold is reaped: its active jobs
# are returned to the queue, and reaped.json is written.

load '../lib/setup'

setup() { daft_test_setup; }
teardown() { daft_test_teardown; }

@test "stale heartbeat causes runner to be reaped" {
  local id='runner-stale-001'
  mkdir -p ".daft/runners/${id}" ".daft/active/${id}/byiq-foo-abc1234"
  printf '{"id":"%s","hostname":"test","isa":"x86_64","created_at":"2026-01-01T00:00:00.000000000Z"}\n' "${id}" \
    > ".daft/runners/${id}/identity.json"
  printf '{"runner_id":"%s","last_seen_at":"old","last_seen_epoch":1,"tick_count":0,"current_job_id":null}\n' "${id}" \
    > ".daft/runners/${id}/heartbeat.json"
  printf '{"job_id":"byiq-foo-abc1234","repo_name":"byiq-foo","clone_url":"x","ref":"refs/heads/main","sha":"abc1234","isa":"x86_64","enqueued_at":"x","job_script_path":".daft/jobs/build"}\n' \
    > ".daft/active/${id}/byiq-foo-abc1234/job.json"

  REAPER_THRESHOLD_SECONDS=1 bash scripts/reaper/tick.sh

  [ -f ".daft/runners/${id}/reaped.json" ]
  [ -f .daft/queue/x86_64/byiq-foo-abc1234.json ]
  [ ! -d ".daft/active/${id}/byiq-foo-abc1234" ]
}

@test "fresh heartbeat is not reaped" {
  local id='runner-fresh-001'
  local epoch
  epoch="$(date -u '+%s')"
  mkdir -p ".daft/runners/${id}"
  printf '{"id":"%s","hostname":"test","isa":"x86_64","created_at":"now"}\n' "${id}" \
    > ".daft/runners/${id}/identity.json"
  printf '{"runner_id":"%s","last_seen_at":"now","last_seen_epoch":%s,"tick_count":1,"current_job_id":null}\n' \
    "${id}" "${epoch}" > ".daft/runners/${id}/heartbeat.json"

  REAPER_THRESHOLD_SECONDS=90 bash scripts/reaper/tick.sh

  [ ! -f ".daft/runners/${id}/reaped.json" ]
}

@test "second reaper tick is idempotent (already-reaped runner not double-reaped)" {
  local id='runner-twice-001'
  mkdir -p ".daft/runners/${id}" ".daft/active/${id}/jid-001"
  printf '{"id":"%s"}\n' "${id}" > ".daft/runners/${id}/identity.json"
  printf '{"runner_id":"%s","last_seen_epoch":1}\n' "${id}" > ".daft/runners/${id}/heartbeat.json"
  printf '{"job_id":"jid-001"}\n' > ".daft/active/${id}/jid-001/job.json"

  REAPER_THRESHOLD_SECONDS=1 bash scripts/reaper/tick.sh
  REAPER_THRESHOLD_SECONDS=1 bash scripts/reaper/tick.sh

  [ -f ".daft/runners/${id}/reaped.json" ]
  local count
  count="$(grep -c 'runner reaped' .daft/workspace/daft-reaper.jsonl 2>/dev/null || printf '0')"
  [ "${count}" = '1' ]
}
