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
        help

## ── Universal canonical targets (required by keelcore/standards ci.md) ──────

build:
	@echo '✅ Nothing to build (CI/CD specification + Bash orchestration repository)'

lint: lint-newlines lint-bash lint-md

test: unit-test integration-test

unit-test:
	@echo '✅ No unit tests yet'

integration-test:
	@echo '✅ No integration tests yet'

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
