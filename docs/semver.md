# Semantic Versioning (SEMVER)

**Status:** Design — Turd/Task spec.
**Depends on:** CRS Group 4 (the land loop is where release tags get applied), `scripts/lib/` shared
bash library convention.
**Replaces:** ad-hoc `VERSION` file editing in MVP (`0.1.337-mvp`).

## 1. Context

DAFt's substrate is git, and tags are git-native. A version string is just a name on a commit; the
chain of versioned commits is the release history. There is no separate "release database" — the
output of `git tag --list 'v*' --sort=-v:refname` is the release database.

What's missing is a deterministic mechanism to **decide** the next version when a submission lands.
The decision must be reproducible (same inputs → same output), auditable (the decision is recorded
in the substrate), and overridable (a maintainer cutting an intentional `2.0.0` is not blocked by a
classifier that only saw a patch-shaped diff).

This spec defines:

1. The **bump decision algorithm** — how the next version is computed from the diff, commit history,
   and submission metadata.
2. The **override protocol** — how a developer signals "I want this to be `1.4.0-rc.1`" via the
   pre-PR source branch.
3. The **tag lifecycle** — when (and only when) a tag is applied, signed, and pushed.
4. The **library contract** — the small set of bash functions that compose into the decision +
   tagging flow, callable from the land loop and from local dev.

The design follows [semver.org 2.0.0](https://semver.org/spec/v2.0.0.html) for parsing, precedence,
pre-release identifiers, and build metadata. Where semver.org defers to project policy (what counts
as a "public API change"), this spec fills in the rules for a Bash-task system like DAFt.

## 2. Glossary

| Term | Definition |
| --- | --- |
| **Current version** | Latest semver-shaped reachable tag from HEAD, computed as `git describe --tags --abbrev=0 --match 'v*'`. Falls back to `v0.0.0` if no tag is reachable. |
| **Computed bump** | The classifier's verdict — `major`, `minor`, `patch`, or `none` — derived from diff + commit messages + PR metadata. |
| **Computed next** | `bump(current, computed_bump)` — what the system would tag absent override. |
| **Desired version** | The contents of `.daft/desired-version` in the source branch, if present. The submitter's explicit request. |
| **Reconciled version** | `max(computed_next, desired)` per semver.org §11 precedence — the version actually applied. Strictly monotonic: a desired version lower than computed is rejected. |
| **Release tag** | A signed annotated tag of the form `vMAJOR.MINOR.PATCH` (or with pre-release / build metadata) on a landed merge commit. |
| **Build metadata** | The `+...` suffix from semver.org §10. Ignored for precedence. DAFt uses it for traceability (sha, build job id). |
| **Pre-release identifier** | The `-...` suffix from semver.org §9 (`-alpha.1`, `-beta.2`, `-rc.1`). Lower precedence than the same `MAJOR.MINOR.PATCH` without pre-release. |

## 3. Tag Format

Tags are signed annotated tags created with `git tag -s`. The tag name is **`v<semver>`** — the `v`
prefix is the kernel/git/Rust/Go convention and disambiguates from non-version tags.

```text
vMAJOR.MINOR.PATCH                                # release
vMAJOR.MINOR.PATCH-PRE                            # pre-release
vMAJOR.MINOR.PATCH+BUILD                          # release with build metadata
vMAJOR.MINOR.PATCH-PRE+BUILD                      # pre-release with build metadata
```

The semver portion (everything after the `v`) MUST match semver.org §2's regex:

```text
^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$
```

Any input failing this regex is rejected before any further processing.

## 4. Bump Decision Algorithm

Given `current_version`, the classifier inspects four inputs and emits the **most severe** verdict
across all of them.

### 4.1 Inputs

| # | Input | Source | Detects |
| --- | --- | --- | --- |
| 1 | **Conventional Commits** in commit messages | `git log target_sha..source_sha --format='%B'` | `feat!:` / `fix!:` / `BREAKING CHANGE:` trailer → major. `feat:` → minor. `fix:` / `perf:` / `refactor:` → patch. |
| 2 | **API surface diff** | `daft_semver_surface` over `target_sha` vs `source_sha` | Removed/renamed exported function → major. Removed/type-changed required parameter → major. Added required parameter → major. New exported function → minor. New optional parameter → minor. |
| 3 | **PR / submission metadata** | `submissions/<id>/manifest.json` `forge_context`, plus structured trailers in commit messages | `Breaking-Change: yes` trailer → major. PR labels (`breaking`, `feature`, `bugfix`) when forge plugin populates them. |
| 4 | **In-tree comments** | `git diff target_sha source_sha` for added comment markers | A new `# DAFT-BREAKING:` or `// DAFT-BREAKING:` comment in source → major. A new `# DAFT-FEATURE:` comment → minor. |

### 4.2 Verdict precedence

```text
major  >  minor  >  patch  >  none
```

If any input emits `major`, the verdict is `major`. Otherwise the highest verdict from any input.
A verdict of `none` (no commits, no surface change, no markers) blocks tagging — submissions that
land with no detected change get no new tag (the prior tag still describes the new HEAD via
`git describe`).

### 4.3 Bump rule

```text
case verdict of
  major  → MAJOR+1.0.0
  minor  → MAJOR.MINOR+1.0
  patch  → MAJOR.MINOR.PATCH+1
  none   → no tag applied
```

Pre-release suffix on `current_version` is **dropped** before bumping. `1.4.0-rc.1` + `patch` →
`1.4.1`, not `1.4.0-rc.2`. To advance a pre-release, the submitter MUST use the override protocol
(§5) — the classifier never invents pre-release identifiers.

### 4.4 Major-zero special case (pre-1.0)

semver.org §4 says anything may change in `0.y.z`. The widely-followed convention (npm, Cargo, Go
modules) treats `0.MAJOR.MINOR` as if it were `MAJOR.MINOR.PATCH`:

| Verdict | While at `0.x.y` | Once at `≥1.0.0` |
| --- | --- | --- |
| major | bump minor (`0.1.5` → `0.2.0`) | bump major |
| minor | bump patch (`0.1.5` → `0.1.6`) | bump minor |
| patch | bump patch | bump patch |

Crossing `1.0.0` requires the override protocol (§5). The classifier never auto-promotes `0.x.y` to
`1.0.0`.

### 4.5 API surface — what counts

For DAFt's Bash-task substrate, the public API surface is:

- Exported functions in `scripts/lib/*.sh` (matched by `^[a-zA-Z_][a-zA-Z0-9_]*\(\)` plus `export
  -f`).
- Function signatures, defined as the set of consumed positional parameters and the names of read
  environment variables (extracted by static analysis of the function body).
- `Makefile` targets listed in `.PHONY` (consumed by humans and CI).
- File paths and JSON schemas under `.daft/` documented as contracts (manifest schemas,
  capabilities.json, lifecycle plugin contracts).
- Documented exit codes from CLI entry points.

The `daft_semver_surface` extractor produces a JSON manifest of all of these. Two manifests diffed
yield additions (minor candidates) and removals/type-changes (major candidates).

Out of scope (intentionally): private helpers, internal scripts not under `scripts/lib/`, anything
not exported.

## 5. Override Protocol

The submitter expresses an explicit desired version by committing **`.daft/desired-version`** to
the source branch. This file is the override.

### 5.1 File format

A single line, the desired semver string, no `v` prefix, no trailing whitespace:

```text
1.4.0
```

Or with pre-release / build metadata:

```text
2.0.0-rc.1
1.4.0-beta.3+sha.deadbee
```

Validated against the semver.org regex (§3). Malformed → submission fails with
`semver_desired_invalid`.

### 5.2 Reconciliation

At land time, the system computes `computed_next` (§4) and reads `desired` from
`.daft/desired-version` (or empty if absent).

| `desired` | `computed_next` | Outcome |
| --- | --- | --- |
| empty | any | apply `computed_next` |
| `>` `computed_next` (semver.org §11) | any | apply `desired` |
| `=` `computed_next` | any | apply either (identical) |
| `<` `computed_next` | any | **reject** — submission fails with `semver_downgrade_attempt` |

Strict monotonicity: a maintainer can leap forward (`0.x.y` → `1.0.0`, `1.4.5` → `2.0.0-rc.1`,
`1.4.5` → `1.5.0` when classifier said patch) but cannot go backwards. This protects the linear
release history that downstream consumers depend on.

### 5.3 Override removal

`.daft/desired-version` is consumed at tag time. The merger (or a post-land hook) deletes the file
in a follow-up commit so it doesn't continue to assert a desired version against the next
submission. Forgetting to remove it is non-fatal — the next submission's reconciliation still
works, but the file becomes noise. A `daft-semver-lint` check warns when the file is present and
`<= current_version`.

### 5.4 Why a file, not a branch name or commit trailer

- A file lives in `.daft/` with the rest of the substrate, signed by the same commit signature.
- Branch names are forge-flavored and not always available (pure-CLI submitters have no branch
  names visible to the central daft repo).
- Commit trailers get squashed/rebased away.
- A file is greppable: `git log -p -- .daft/desired-version` shows the full history of who asked
  for what version, when.

## 6. Tag Lifecycle

Tags are applied **only after tests pass**. The two test gates that produce tags:

```text
B1 green → no tag (workspace commit is not part of target's history)
B2 green + push-with-lease accepted → release tag on the merge commit M
```

Pre-release tags are not auto-emitted by B1. The merge commit M is the only commit that gets a
release tag; this preserves the invariant "every `v*` tag points to a commit on a target branch."

### 6.1 The land-time tagging step

Inside the CRS land loop (`canonical_build_running` → `landed`), after the push-with-lease is
accepted:

```text
1. current = `git describe --tags --abbrev=0 --match 'v*'` (on M's parent, which is T)
   → fallback to v0.0.0 if no prior tag
2. computed_bump = daft_semver_classify T S
3. computed_next = daft_semver_bump current computed_bump
4. desired = daft_semver_read_desired S      (or empty)
5. final = daft_semver_reconcile computed_next desired
   → fail submission with semver_downgrade_attempt if invalid
6. if computed_bump = none AND desired empty:
     → no tag, exit cleanly
   else:
     → git tag -s v$final -m "Released by submission <id>" M
     → git push origin v$final
7. record decision in submissions/<id>/semver_decision.json
```

The tag push happens after the merge push, in a separate atomic operation. If the tag push fails
(name collision — extremely rare, indicates concurrent release), the loop logs and reopens the
submission as `landing_failed_tag_collision`. The merge is already in target's history, so this
failure is a tagging-only failure, not a code-landing failure; ops can resolve manually.

### 6.2 Build metadata

The release tag is plain (`v1.4.0`, no build suffix) on the merge commit. Build metadata is
attached separately as commit notes (`git notes add -ref=daft-build`) for the build job id, runner
fingerprint, and SBOM hash. This keeps tag names short and stable while preserving traceability.

If a submitter sets `desired = v1.4.0+build.42`, the build metadata is preserved verbatim in the
tag name (semver.org §10 allows it; precedence ignores it). The system does not append additional
build metadata in this case.

### 6.3 Signing

`git tag -s` requires a signing key. The key used is the merger's key (the role that initiated the
land loop), not the submitter's. The signed annotated tag stores: tagger identity, timestamp, the
submission id, and a one-line release message. `git tag -v v1.4.0` verifies the signature against
`.daft/authz/keys/users/`.

## 7. Library Contract

All semver work is done by pure(-ish) bash functions in `scripts/lib/semver.sh`, callable from the
land loop, the local CLI, and tests.

| Function | Inputs | Output | Side effects |
| --- | --- | --- | --- |
| `daft_semver_parse VERSION` | semver string | five lines: `MAJOR\nMINOR\nPATCH\nPRE\nBUILD` | none |
| `daft_semver_compare A B` | two semver strings | `-1`, `0`, or `1` per §11 | none |
| `daft_semver_validate VERSION` | semver string | exit 0 if valid, 1 otherwise | none |
| `daft_semver_current [REF]` | git ref (default HEAD) | latest reachable release tag, or `v0.0.0` | none |
| `daft_semver_describe [REF]` | git ref | `git describe --tags --match 'v*'` output (with `-N-gSHA` suffix between releases) | none |
| `daft_semver_surface REF` | git ref | API surface JSON manifest | none |
| `daft_semver_classify TARGET_SHA SOURCE_SHA` | two shas | one of `major`, `minor`, `patch`, `none` | none |
| `daft_semver_bump CURRENT KIND` | current version + verdict | next version per §4.3, with §4.4 special case | none |
| `daft_semver_read_desired SOURCE_PATH` | path to source checkout | contents of `.daft/desired-version`, or empty | none |
| `daft_semver_reconcile COMPUTED DESIRED` | two semver strings (DESIRED may be empty) | reconciled version, exit 0; exit 1 with reason on stderr if downgrade | none |
| `daft_semver_apply_release MERGE_SHA VERSION` | merge sha + version | applies signed annotated tag, pushes | `git tag -s`, `git push origin v<version>` |
| `daft_semver_record_decision SUBMISSION_ID DECISION_JSON` | submission id + JSON blob | writes `semver_decision.json` | git add+commit under `.daft/submissions/<id>/` |

The functions compose top-down: `apply_release` calls `record_decision`, the land loop calls
`classify` → `bump` → `read_desired` → `reconcile` → `apply_release`. No global state; everything
flows through arguments and stdout.

A reference implementation lives under `scripts/lib/semver.sh`; a test harness under
`scripts/test/lib/semver/` exercises each function with bats fixtures (no network, no live git
operations — uses a temp-dir scratch repo).

## 8. State / Audit

Each semver decision is recorded in the submission directory at land time:

```text
.daft/submissions/<id>/semver_decision.json
```

```json
{
  "submission_id": "1234",
  "merge_sha": "merge456def",
  "current_version": "v1.3.7",
  "classifier": {
    "verdict": "minor",
    "evidence": [
      {"input": "conventional_commits", "verdict": "minor", "matches": ["feat: add CRS land loop"]},
      {"input": "api_surface", "verdict": "minor", "matches": ["+exports daft_crs_land"]},
      {"input": "pr_metadata", "verdict": "none", "matches": []},
      {"input": "in_tree_markers", "verdict": "none", "matches": []}
    ]
  },
  "computed_next": "v1.4.0",
  "desired": "",
  "reconciled": "v1.4.0",
  "applied": "v1.4.0",
  "tagged_at": "2026-05-06T15:42:00.000000000Z",
  "tagger_fpr": "mrg789..."
}
```

`git log -- .daft/submissions/<id>/semver_decision.json` reproduces the entire reasoning behind a
release version with no proprietary tooling. `git tag -v v1.4.0` verifies the cryptographic
provenance of the tag itself.

## 9. Failure Modes

| State | Cause | Resolution |
| --- | --- | --- |
| `semver_desired_invalid` | `.daft/desired-version` does not match semver.org regex | Submitter fixes the file, pushes new sha, full re-validation |
| `semver_downgrade_attempt` | `desired < computed_next` | Submitter raises desired to `>= computed_next`, or removes the file |
| `semver_classifier_error` | Classifier crashed (bad git data, surface extractor failure) | Operator-paged; submission re-queueable without code change |
| `landing_failed_tag_collision` | Tag name already exists at push time (race or duplicate desired) | Operator investigates; merge already landed, only the tag is missing |
| `semver_no_change` | Verdict `none`, no override | Non-fatal; submission lands without a new tag (prior tag still reachable via `git describe`) |

## 10. Pre-Release & Build-Stage Suffixes

semver.org §9 allows arbitrary dot-separated identifiers after `-`. DAFt borrows the canonical
conventions:

| Suffix | Meaning | When to use |
| --- | --- | --- |
| `-alpha.N` | Early development; APIs not stabilized | Spike branches, experimental features |
| `-beta.N` | Feature complete; testing in progress | Pre-release validation by early adopters |
| `-rc.N` | Release candidate; promote to release if no regressions | Final stabilization before a real release |
| `-snapshot` | Dev build between releases | Auto-generated for ad-hoc builds; never tagged in CI |

These are emitted **only via the override protocol** (`.daft/desired-version`). The classifier
itself never produces pre-release tags — they're maintainer intent, not classifier output.

Build metadata (semver.org §10, the `+...` suffix) is allowed in `desired-version` and is
preserved verbatim. Common values:

```text
+sha.<short-sha>      # short commit sha (default if omitted)
+build.<job-id>       # CI job id
+date.20260506        # ISO-ish date stamp
```

`git describe --tags 'v*'` produces a synthetic working version between releases:
`v1.4.0-3-gabc1234` (3 commits past `v1.4.0`, current sha `abc1234`). The library function
`daft_semver_describe` returns this verbatim for use in build artifacts that need a unique
identifier per dev build.

## 11. Borrowed Conventions

This spec aligns with established practice rather than inventing:

| Source | Borrowed convention |
| --- | --- |
| [semver.org 2.0.0](https://semver.org/) | Tag format, regex, precedence rules, pre-release & build metadata semantics |
| [Conventional Commits 1.0.0](https://www.conventionalcommits.org/) | `feat:` / `fix:` / `feat!:` / `BREAKING CHANGE:` trailer mapping to bump verdicts |
| Linux kernel / git itself | `v` prefix on release tags |
| npm, Cargo (Rust), Go modules | `0.x.y` special-case treatment (§4.4) |
| GoReleaser, semantic-release | Auto-derive next version from commit history; manual override file |
| Maven / Gradle | `-SNAPSHOT` for dev builds |
| The `git describe` man page | The `vTAG-N-gSHA` working-version format between releases |

Tools deliberately *not* followed: PEP 440 (Python — different scheme; we are not Python),
CalVer (date-based — different problem), unique snowflake CI release schemes.

## 12. Out of Scope

- **Multi-track release lines.** A team simultaneously maintaining `v1.x` (LTS) and `v2.x` (current)
  needs branch-scoped tag computation. Useful but post-substrate. The current spec computes against
  the target's reachable tag history, which works for single-track release lines.
- **CHANGELOG generation.** A separate Turd consumes commit history + classifier verdicts to
  produce `CHANGELOG.md` entries. Composable with this spec; not part of it.
- **Per-package versioning in monorepos.** This spec versions the repo as a whole. Subdirectory-
  scoped semver (the `scripts/lib/` package vs the `.daft/plugins/` package) is a future concern.
- **Yanking / un-publishing tags.** Tags are immutable in the DAFt model; a regrettable release is
  superseded, not deleted. (`git tag -d` + `git push --delete` is mechanically possible but
  outside spec.)
- **Cross-repo dependency version constraints.** Out of scope; DAFt does not model a package
  graph.

## 13. Open Questions

These are not blockers for the Turd work but should be settled before implementation freeze:

1. **Squash-merge handling.** If the merger squashes source's history into a single commit on
   target, Conventional Commits in the original commits are lost unless the squash message
   preserves them. Default: substrate forbids squash merges (preserves `feat:` / `BREAKING
   CHANGE:` trailers). Acceptable, or do we need a squash-merge classifier path?
2. **Cross-language API surface.** `daft_semver_surface` is shaped for Bash. A polyglot repo
   (Bash + Go + TypeScript) needs per-language extractors registered as plugins. Plugin contract
   design is out of scope here but flagged.
3. **Initial `1.0.0` cutover.** When does a 0.x project become 1.x? The override protocol allows
   it, but the *decision* — "we believe the API is stable enough to commit to backwards
   compatibility" — is not something CI can decide. Documented as "submitter pushes
   `1.0.0` to `.daft/desired-version` when the team is ready", no automation.
4. **Tag-on-pre-release-branch policy.** If a team uses a `release/2.0` branch for stabilization,
   should `landed` submissions on that branch produce `v2.0.0-rc.N` tags automatically? Currently
   no — pre-release tags are explicit-only. Revisit if teams ask.
5. **Surface manifest stability.** The JSON shape of `daft_semver_surface` output is itself an
   API. Versioning the manifest schema is a chicken-and-egg problem — start with `surface_v1`,
   bump on breakage.

## 14. Implementation Roadmap

| Step | Deliverable |
| --- | --- |
| 1 | `scripts/lib/semver.sh` with `parse`, `compare`, `validate`, `bump`, `current` (read-only side); unit tests in bats |
| 2 | `daft_semver_classify` — Conventional Commits + commit-message-trailer scanner (no surface diff yet); reference fixtures |
| 3 | `daft_semver_surface` extractor for Bash (exported function names + Makefile targets); `classify` integrates surface diff |
| 4 | `read_desired` + `reconcile` + decision recording; bats tests covering downgrade rejection, equal, leap-forward |
| 5 | `apply_release` — wires into the CRS land loop's post-push step; signed-tag flow |
| 6 | `daft-semver-lint` Makefile target — validates `.daft/desired-version` in source repo, warns on stale overrides |
| 7 | Documentation pass: README link from this spec to CRS spec at the land-loop step where tagging happens |

## 15. References

- [semver.org 2.0.0](https://semver.org/spec/v2.0.0.html) — primary normative reference.
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) — commit-message
  classification.
- Project README (`/README.md`) — overall architecture.
- CRS spec (`/doc/CRS.md`) — the land loop in §5/§6 is where release tags are applied.
- COMPARISON (`/COMPARISON.md`) — positioning vs SaaS.
