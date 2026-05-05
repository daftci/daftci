# daftci — Build Orchestrator
# All CI concerns are invoked through this file.
# Workflow YAML calls `make <target>`; developers call the same targets locally.

.PHONY: build lint lint-newlines lint-bash lint-md lint-all \
        test unit-test integration-test clean audit \
        coverage ci-coverage-delta \
        ci-pr-policy ci-secret-scan ci-dco \
        check-legal-drift \
        format pre-commit \
        setup-markdownlint setup-shellcheck setup-syft \
        bootstrap-standards install-hooks \
        daft-init daft-repo-add daft-repo-remove daft-repo-list daft-runner-init \
        daft-coordinator daft-coordinator-tick daft-coordinator-check-repo \
        daft-reaper daft-reaper-tick \
        daft-runner daft-runner-janitor daft-runner-tick \
        daft-runner-claim daft-runner-execute daft-runner-release daft-runner-heartbeat \
        daft-doctor daft-status daft-tail-log daft-coordinator-status daft-runner-list \
        integration-test-compose compose-up compose-down compose-purge \
        compose-lifecycle compose-bootstrap compose-entrypoint-info \
        help

## ── Universal canonical targets (required by keelcore/standards ci.md) ──────

build:
	@echo '✅ Nothing to build (CI/CD specification + Bash orchestration repository)'

lint: lint-newlines lint-bash lint-md

test: unit-test integration-test

unit-test:
	@echo '✅ No unit tests yet'

integration-test:
	@echo '🧪 Running DAFt integration tests...'
	bash scripts/test/integration/run.sh

clean:
	@echo '🧹 Nothing to clean'

audit:
	@echo '🔍 Running CI/Makefile audit...'
	bash scripts/ci/audit-make-targets.sh

coverage:
	@echo '📊 Generating coverage report...'
	bash scripts/test/coverage.sh

ci-coverage-delta:
	@echo '📊 Checking coverage delta...'
	bash scripts/test/coverage-delta.sh

ci-pr-policy:
	@echo '🔍 Running PR policy check...'
	bash scripts/ci/pr-policy.sh

ci-secret-scan:
	@echo '🔍 Running secret scan...'
	bash scripts/ci/secret-scan.sh

ci-dco:
	@echo '🔍 Running DCO sign-off check...'
	bash scripts/ci/dco-check.sh

lint-newlines:
	@echo '🔍 Checking trailing newlines...'
	bash scripts/lint/newlines.sh

check-legal-drift:
	@echo '⚖️  Checking legal file drift...'
	bash scripts/check-legal-drift.sh

## ── Additional lint targets ──────────────────────────────────────────────────

lint-bash:
	@echo '🔍 Running shellcheck (bash)...'
	bash scripts/lint/shellcheck.sh

lint-md:
	@echo '🔍 Running markdown lint...'
	bash scripts/lint/md.sh

lint-all:
	@echo '🔍 Running all linters (full suite)...'
	bash scripts/lint.sh

## ── Dev utilities ────────────────────────────────────────────────────────────

format:
	@echo '🖊️  Formatting repository...'
	bash scripts/format.sh

pre-commit:
	@echo '🪝 Running pre-commit checks...'
	bash scripts/git_precommit.sh

## ── Setup targets ────────────────────────────────────────────────────────────

setup-markdownlint:
	@echo '🔧 Installing markdownlint-cli...'
	bash scripts/ci/setup-markdownlint.sh

setup-shellcheck:
	@echo '🔧 Installing shellcheck...'
	bash scripts/ci/setup-shellcheck.sh

setup-syft:
	@echo '🔧 Installing syft...'
	bash scripts/ci/setup-syft.sh

bootstrap-standards:
	@echo '🔧 Bootstrapping standards integration...'
	bash .standards/scripts/bootstrap-standards.sh

install-hooks:
	@echo '🪝 Installing git hooks...'
	ln -sf ../../scripts/git_precommit.sh .git/hooks/pre-commit

## ── DAFt MVP — setup ─────────────────────────────────────────────────────────

daft-init:
	bash scripts/daft/init.sh

daft-repo-add:
	bash scripts/daft/repo_add.sh "$(NAME)" "$(URL)" "$(REF)"

daft-repo-remove:
	bash scripts/daft/repo_remove.sh "$(NAME)"

daft-repo-list:
	bash scripts/daft/repo_list.sh

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

## ── Help ─────────────────────────────────────────────────────────────────────

help:
	@echo 'daftci Build System'
	@echo ''
	@echo 'Universal canonical targets (keelcore/standards ci.md):'
	@echo '  build                   No-op (CI/CD specification repository)'
	@echo '  lint                    lint-newlines + lint-bash + lint-md'
	@echo '  test                    unit-test + integration-test'
	@echo '  unit-test               No-op (no unit tests yet)'
	@echo '  integration-test        No-op (no integration tests yet)'
	@echo '  clean                   No-op'
	@echo '  audit                   CI/Makefile standards compliance auditor'
	@echo '  coverage                Coverage report'
	@echo '  ci-coverage-delta       PR coverage delta gate'
	@echo '  ci-pr-policy            PR policy gate'
	@echo '  ci-secret-scan          Secret scan (gitleaks)'
	@echo '  ci-dco                  DCO Signed-off-by check'
	@echo '  lint-newlines           Trailing newline enforcement'
	@echo '  check-legal-drift       Verify copied legal files match source of truth'
	@echo ''
	@echo 'Additional lint:'
	@echo '  lint-bash               shellcheck (bash) on all *.sh files'
	@echo '  lint-md                 markdownlint on all markdown files'
	@echo '  lint-all                Full linter suite (scripts/lint.sh)'
	@echo ''
	@echo 'Dev utilities:'
	@echo '  format                  Run all formatters'
	@echo '  pre-commit              Run pre-commit checks'
	@echo ''
	@echo 'Setup:'
	@echo '  setup-markdownlint      Install markdownlint-cli'
	@echo '  setup-shellcheck        Install shellcheck'
	@echo '  setup-syft              Install syft'
	@echo '  bootstrap-standards     Reproduce all .standards-derived files'
	@echo '  install-hooks           Install git pre-commit hook'
	@echo ''
	@echo 'DAFt MVP — setup:'
	@echo '  daft-init                       Create .daft/repos|archive|metrics dirs + VERSION'
	@echo '  daft-repo-add NAME=.. URL=.. REF=..  Register an upstream work repo'
	@echo '  daft-repo-remove NAME=..        Deregister a repo'
	@echo '  daft-repo-list                  List registered repos with state'
	@echo '  daft-runner-init                Generate runner identity for this host'
	@echo ''
	@echo 'DAFt MVP — coordinator:'
	@echo '  daft-coordinator                Outer loop (runs forever)'
	@echo '  daft-coordinator-tick           One iteration (testable)'
	@echo '  daft-coordinator-check-repo NAME=..  Single ls-remote against one repo'
	@echo ''
	@echo 'DAFt MVP — reaper:'
	@echo '  daft-reaper                     Outer loop (runs forever)'
	@echo '  daft-reaper-tick                One iteration (testable)'
	@echo ''
	@echo 'DAFt MVP — runner:'
	@echo '  daft-runner                     Outer loop (runs forever)'
	@echo '  daft-runner-janitor             One-shot stale-lock recovery'
	@echo '  daft-runner-tick                One iteration (testable)'
	@echo '  daft-runner-claim               Single claim attempt'
	@echo '  daft-runner-execute JOB=..      Run job script for an already-claimed JOB'
	@echo '  daft-runner-release JOB=..      Release a JOB to archive'
	@echo '  daft-runner-heartbeat           Push a single heartbeat now'
	@echo ''
	@echo 'DAFt MVP — ops:'
	@echo '  daft-doctor                     Health check'
	@echo '  daft-status                     List jobs in queue/active/archive(today)'
	@echo '  daft-tail-log JOB=..            Tail a job log'
	@echo '  daft-coordinator-status         Per-repo reachability summary'
	@echo '  daft-runner-list                List runners with heartbeat info'
	@echo ''
	@echo 'DAFt MVP — compose integration tests:'
	@echo '  integration-test-compose        End-to-end: colima → compose → bats scenarios → down'
	@echo '  compose-up                      Bring up the stack (idempotent)'
	@echo '  compose-down                    Tear down stack (volumes preserved)'
	@echo '  compose-purge                   Full wipe: down -v + colima stop'
	@echo '  compose-lifecycle ARG=up|down|status|purge'
	@echo '                                  Direct colima control'
	@echo '  compose-bootstrap               Re-run bootstrap inside test-driver'
