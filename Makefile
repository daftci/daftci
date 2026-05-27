# Consumer Makefile — delegates canonical targets to .standards/templates/Makefile.canonical.
# Originally cloned from the pre-include-era templates/Makefile; migrated
# by migrate-makefile.sh. The original is preserved at Makefile.pre-migrate.bak.

ifeq (,$(wildcard .standards/templates/Makefile.canonical))
$(error .standards/templates/Makefile.canonical not found. Run: git submodule update --init --recursive)
endif

include .standards/templates/Makefile.canonical

## Consumer-specific content (preserved from the original Makefile).
## Targets whose recipes matched canonical were removed by the migration.
## Targets that drifted from canonical (see migration report) remain below
## and should be reconciled by hand.

.PHONY: build lint-md unit-test integration-test clean coverage bootstrap-standards install-hooks daft-init daft-repo-add daft-repo-remove daft-repo-list daft-repo-reload daft-runner-init daft-coordinator daft-coordinator-tick daft-coordinator-check-repo daft-reaper daft-reaper-tick daft-runner daft-runner-janitor daft-runner-tick daft-runner-claim daft-runner-execute daft-runner-release daft-runner-heartbeat daft-orchestrator-up daft-orchestrator-down daft-orchestrator-status daft-tick-show daft-tick-set-coordinator daft-tick-set-reaper daft-tick-set-runner daft-doctor daft-status daft-tail-log daft-coordinator-status daft-runner-list integration-test-compose compose-up compose-down compose-purge compose-lifecycle compose-bootstrap compose-entrypoint-info help

## ── DAFt MVP — setup ─────────────────────────────────────────────────────────

daft-init:
	bash scripts/daft/init.sh

daft-repo-add:
	bash scripts/daft/repo_add.sh "$(NAME)" "$(URL)" "$(REF)"

daft-repo-remove:
	bash scripts/daft/repo_remove.sh "$(NAME)"

daft-repo-list:
	bash scripts/daft/repo_list.sh

daft-repo-reload:
	bash scripts/daft/repo_reload.sh

daft-runner-init:
	bash scripts/daft/runner_init.sh

## ── DAFt MVP — coordinator ───────────────────────────────────────────────────

daft-coordinator:
	bash scripts/coordinator/loop.sh

daft-coordinator-tick:
	bash scripts/coordinator/tick.sh

daft-coordinator-check-repo:
	bash scripts/coordinator/check_repo.sh "$(NAME)"

## ── DAFt MVP — reaper ────────────────────────────────────────────────────────

daft-reaper:
	bash scripts/reaper/loop.sh

daft-reaper-tick:
	bash scripts/reaper/tick.sh

## ── DAFt MVP — runner ────────────────────────────────────────────────────────

daft-runner:
	bash scripts/runner/loop.sh

daft-runner-janitor:
	bash scripts/runner/janitor.sh

daft-runner-tick:
	bash scripts/runner/tick.sh

daft-runner-claim:
	bash scripts/runner/claim.sh

daft-runner-execute:
	bash scripts/runner/execute.sh "$(JOB)"

daft-runner-release:
	bash scripts/runner/release.sh "$(JOB)"

daft-runner-heartbeat:
	bash scripts/runner/heartbeat.sh

## ── DAFt MVP — orchestrator (coordinator + reaper as background PID-file procs) ─

daft-orchestrator-up:
	bash scripts/orchestrator/up.sh

daft-orchestrator-down:
	bash scripts/orchestrator/down.sh

daft-orchestrator-status:
	bash scripts/orchestrator/status.sh

## ── DAFt MVP — tick intervals (host-local, take effect on next loop restart) ─

daft-tick-show:
	bash scripts/daft/tick_show.sh

daft-tick-set-coordinator:
	bash scripts/daft/tick_set.sh COORDINATOR_INTERVAL_SECONDS "$(INTERVAL)"

daft-tick-set-reaper:
	bash scripts/daft/tick_set.sh REAPER_INTERVAL_SECONDS "$(INTERVAL)"

daft-tick-set-runner:
	bash scripts/daft/tick_set.sh RUNNER_INTERVAL_SECONDS "$(INTERVAL)"

## ── DAFt MVP — ops helpers ───────────────────────────────────────────────────

daft-doctor:
	bash scripts/daft/doctor.sh

daft-status:
	bash scripts/daft/status.sh

daft-tail-log:
	bash scripts/daft/tail_log.sh "$(JOB)"

daft-coordinator-status:
	bash scripts/daft/coordinator_status.sh

daft-runner-list:
	bash scripts/daft/runner_list.sh

## ── DAFt MVP — compose-based integration tests ───────────────────────────────

integration-test-compose:
	bash scripts/test/compose/run.sh

compose-up:
	bash scripts/test/compose/up.sh

compose-down:
	bash scripts/test/compose/down.sh

compose-purge:
	bash scripts/test/compose/purge.sh

compose-lifecycle:
	bash scripts/test/compose/lifecycle.sh "$(ARG)"

compose-bootstrap:
	docker compose --env-file scripts/test/compose/.env \
	  -f scripts/test/compose/docker-compose.yaml \
	  exec -T test-driver bash /repo/scripts/test/compose/bootstrap.sh

compose-entrypoint-info:
	@echo 'scripts/test/compose/entrypoint.sh runs inside coordinator/reaper/runner containers'
	@echo '(invoked automatically; see scripts/test/compose/docker-compose.yaml)'
