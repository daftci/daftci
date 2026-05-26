# Code Review Submissions (CRS)

**Status:** Design — target Group 4 of the project roadmap.
**Depends on:** Group 2 (signed-event authz + age vault), Group 3 (isolation levels).
**Replaces:** the "tickets" / human-in-the-loop gate item in the original Group 7 polish list.

## 1. Context

DAFt's substrate is git: refs, commits, signed pushes. "Pull request" / "merge request" is a forge concept
layered on top of git — every forge (GitHub, GitLab, Gitea, Sourcehut, Bitbucket) has its own shape, ref
naming, and event vocabulary. Modeling PRs as a forge concern and treating CI as ref-driven works for the
substrate but leaves a structural gap: **code review before merge is an engineering invariant, not a forge
implementation detail.** Every modern team has it whether they use a forge or not.

CRS is DAFt's first-class abstraction for "code arrives, gets validated, gets reviewed, gets merged." It is
forge-agnostic: a team running pure git-over-SSH gets the full review-and-merge workflow, signed audit
trail, and CI gates with no forge dependency. Forge integrations (GitHub PRs, GitLab MRs, etc.) become thin
translation plugins that mirror forge events into CRS state and CRS state back to the forge. The substrate
does not know or care which forge — if any — is involved.

The design optimizes for three properties:

1. **Cheap checks before expensive ones.** Submitter validity, then static analysis, then build, then human
   time, in that order. Reviewers never look at code that has not at least built against current target.
2. **Trust gated by humans, not by machines.** Static checks passing and a build going green prove "this
   code probably works." Only a human reviewer's signed approval grants the code access to trusted secrets.
3. **Audit trail is the git log.** Every state transition is a signed commit on the central daft repo.
   `git log -- .daft/submissions/<id>/` reproduces the complete history of a submission with no proprietary
   dashboard.

## 2. Glossary

| Term | Definition |
| --- | --- |
| **Submitter** | Human author of a submission. Identified by a long-term age public key whose fingerprint is the canonical handle. |
| **Approver** | Human authorized by org policy to approve a submitter. Authority defined in `.daft/authz/policies/submitter-approval.sh`. |
| **Reviewer** | Human authorized to approve or request changes on a submission. Authority defined in `.daft/authz/policies/<repo-or-org>-review.sh`. |
| **Merger** | Human or automated role authorized to land approved submissions. Authority in `.daft/authz/policies/land-policy.sh`. |
| **Source repo / source ref / source sha** | The submitter's branch — the change being proposed. |
| **Target repo / target ref / target sha** | The branch the change wants to land on. |
| **Workspace** | The result of merging current target into source. The unit B1 builds and tests. |
| **Submission** | A first-class CRS object, identified by `<submission-id>`, holding manifest, build results, reviews, and status. Lives under `.daft/submissions/<id>/`. |
| **Quarantine pool** | Runners whose age keys can decrypt user-tier and build-tier secrets but **not** trusted-tier secrets. Run G2 and B1. |
| **Trusted pool** | Runners whose age keys can decrypt build-tier and trusted-tier secrets. Run B2. |
| **Trust gate** | Human review approval. The single point where "machine-validated" becomes "trusted." |

## 3. Workflow Overview

A submission moves through five gates in strict order. Each gate is cheaper than the next; each protects the
resources of the next.

```text
G1: Submitter Approval        (human, one-time per author)
G2: Static Checks             (machine, no secrets, no network)
B1: Workspace Build           (machine, Quarantine pool, submitter+build vault)
R:  Human Review              ← THE TRUST GATE
B2: Canonical Build           (machine, Trusted pool, build+org vault, post-merge)
```

| # | Gate | Pool | Vault scope | Verifies |
| --- | --- | --- | --- | --- |
| **G1** | Submitter Approval | n/a | n/a | Author key currently approved |
| **G2** | Static Checks | Quarantine | None | Lint, style, security scan, license, supply-chain |
| **B1** | Workspace Build | Quarantine | `users/<fpr>/` + `build/` | `target → source` merges, builds, non-trusted tests pass |
| **R** | Human Review | n/a | n/a | Code quality, intent, design |
| **B2** | Canonical Build | Trusted | `build/` + `org/` | Pre-push build of trial-merge workspace in a retry loop; push lands the merge atomically only if target hasn't drifted during the build |

Each gate is described in detail in §5.

## 4. Forge-Agnostic Foundation

CRS treats forge integration as translation, not as a feature. The substrate works without any forge:

- A team running git over SSH with bare repos uses CRS directly via the CLI (`make daft-crs-submit`,
  `make daft-crs-review`, etc.).
- A team using GitHub installs the GitHub forge plugin (`.daft/plugins/forges/github/`); GitHub PR events
  translate into CRS submissions, CRS state translates back to GitHub check-runs.
- Gitea, GitLab, Sourcehut, Bitbucket plugins follow the same shape independently. None of them changes
  substrate semantics.

Forge plugins are out of scope for the CRS substrate work (Group 4); they are Group 5. The substrate must
be complete and useful without any forge plugin loaded.

## 5. The Five Gates

### G1 — Submitter Approval

**Goal:** an unknown human cannot trigger machine work on DAFt runners. Approval is a one-time human-in-the-
loop step that establishes the submitter's right to consume runner resources.

**State directory:**

```text
.daft/authz/submitters/<author-fpr>/
├── approval.json        # signed by approver
└── revocations.json     # append-only signed revocation events
```

**`approval.json` schema:**

```json
{
  "submitter_fpr": "abc123def456...",
  "submitter_name": "Alice Example <alice@example.com>",
  "approved_at": "2026-05-06T14:00:00.000000000Z",
  "approver_fpr": "fed987cba654...",
  "scope": {
    "orgs": ["byiq"],
    "repos": ["*"],
    "expires_at": "2027-05-06T14:00:00.000000000Z"
  }
}
```

**Effective approval** is computed at gate-evaluation time:

1. `approval.json` exists and is signed by a key that satisfies `submitter-approval.sh` policy.
2. `expires_at` is in the future.
3. No entry in `revocations.json` is later than `approved_at`.
4. The current submission's `(org, repo)` is in scope.

**Revocation** is a signed append to `revocations.json`. A submitter can be re-approved later; the next
approval supersedes the prior revocation. Revocation in flight: an existing in-progress submission moves to
`suspended` on next gate evaluation; further state transitions are blocked until re-approval.

**Policy hook:** `.daft/authz/policies/submitter-approval.sh` is an executable script. It receives the
proposed `approval.json` on stdin and exits 0 if the approver is allowed to issue the approval. Common
implementations:

- "Any current org member key can approve" — fingerprint must appear in `.daft/authz/keys/users/<org>/`.
- "Two co-signers required" — the script verifies the approval was co-signed by two distinct keys.
- "Owner-tier only" — the approver's fingerprint must be in `.daft/authz/keys/owners/`.

The script is bash; complex policy is composable.

**Why one-time per author, not per-submission:** approving a human is a costly synchronous operation
(someone reads the approval request, decides, signs). Doing this on every push would gate the entire
workflow on synchronous human time. Doing it once per author bounds the cost.

### G2 — Static Checks

**Goal:** cheap, deterministic, secret-free verdicts on whether the submitted code is fit to consume build
resources. This is the second-cheapest gate and runs before B1 — never spend MICROVM build minutes on code
that has obvious lint, style, security, or licensing issues.

**Two check layers, both run, both must pass:**

#### Org-mandatory checks

`.daft/checks/` in the **central daft repo**. Run against every submission to every target repo, regardless
of repo-local opinion. These are checks the org never wants skipped:

- Secret-leak scan (gitleaks-shaped)
- Known-vulnerability scan against vendored deps (syft → grype-shaped)
- License compliance (no GPL contamination of MIT codebases, etc.)
- Supply-chain provenance (verify any binaries or pre-compiled assets)
- Forbidden-pattern scan (e.g., direct `eval`, `exec` of user input)

#### Repo-local checks

`.daft/checks/` in the **submitted source**. Project-specific rules:

- Linters and style enforcement (`shellcheck`, `gofmt`, `prettier`, etc.)
- Custom validators ("no new direct database calls", "all migrations have downgrades", "no new public APIs
  without OpenAPI spec changes")
- Per-language sanity (Go vet, Rust clippy, etc.)

#### Check contract

Each check is an executable file with this contract:

- Stdin: the absolute path of a fresh checkout of the submitted source.
- Stdout: a JSON report describing the check result.
- Exit code: 0 = pass; non-zero = fail.

```json
{
  "check_name": "gitleaks",
  "passed": false,
  "summary": "2 findings",
  "findings": [
    {"path": "config/secrets.yml", "line": 12, "rule": "aws-access-key", "severity": "high"},
    {"path": "scripts/deploy.sh", "line": 5, "rule": "private-key", "severity": "critical"}
  ]
}
```

#### Runtime

- **Pool:** Quarantine.
- **Vault scope:** none. The check process has no decryption keys loaded. It cannot read any vault entry.
- **Network:** no egress. Checks operate on the source tree and emit verdicts; they do not need internet.
- **Isolation:** MICROVM (or bwrap+netns minimum). A compromised check script — supply-chain attack on a
  popular linter — cannot exfiltrate even with no secrets, because there is no network path out.

#### Output

Per-check result lands in `submissions/<id>/static-checks/<layer>/<check-name>.json`. The pipeline fails
the gate if **any** check returns non-zero. Reports are preserved for the reviewer to read; failed checks
appear in the dashboard with their findings expanded.

#### Failure mode

State transitions to `static_checks_failed` with the per-check reports attached. The next push of a new
source sha re-runs G2 from scratch — there is no caching, because cheap-first is the principle.

### B1 — Workspace Build

**Goal:** verify the submitter's change, with current target merged in, builds and passes the tests that
can run without trusted secrets. This is the build whose result reviewers care about.

#### Merge direction is target → source

The system fetches the target ref, checks out the submitter's source ref, and merges target into source.
The result is the workspace the submitter would have if they had pulled from target before submitting:

```bash
git fetch <target_repo> <target_ref>
git checkout <source_sha>
git merge --no-edit <target_sha>
# If merge conflicts: B1 fails as merge_conflict; submitter must rebase.
# If clean: build the merged workspace.
```

This direction is deliberate:

- **Mirrors what a disciplined submitter does locally.** If conflicts surface here, they are conflicts the
  submitter would have hit anyway, owed to them, not to target's history.
- **The merge commit is owned by the submission, not target.** Target's history is unaffected by the trial
  merge — no synthetic merge commits pollute it.
- **Answers the reviewer-relevant question.** "Does the submitted change integrate with current target?"
  is what reviewers want answered before they spend time reading the diff.

#### Trust scope

- **Pool:** Quarantine.
- **Vault scope:** `users/<submitter-fpr>/` + `build/`. **No `org/` access.**
- **Isolation:** MICROVM. **No internal-network egress.**

The submitter's code has not yet been reviewed by a human. It cannot touch trusted secrets, period. Any
test that requires trusted secrets to run is **deferred to B2**.

#### `users/<submitter-fpr>/` — the submitter's vault

Secrets the submitter contributed to their own builds: personal API tokens, test credentials, scratch
secrets they own. Stored under `.daft/vault/users/<submitter-fpr>/`, age-encrypted to the **quarantine-pool
public key**, not to the submitter's personal key. Rationale: the runner needs to decrypt these during the
build; encrypting to the submitter's personal key would require the submitter to share their private key
with the runner (no). Encrypting to the quarantine-pool key means the runner pool — which the submitter has
already implicitly trusted by submitting code to it — can decrypt them for the duration of the build.

The submitter writes new entries via `make daft-crs-add-secret KEY=foo VALUE=...`, which encrypts the value
to the quarantine-pool public key and commits it. They can delete or rotate at any time.

#### `build/` — the build-tier org vault

Secrets the org has explicitly classified as "safe to expose to any approved submitter's code under MICROVM
isolation." Typical contents:

- Internal package-registry **pull** tokens (no push, no admin)
- Signed-binary verification public keys
- Internal proxy URLs that grant only read access to mirrored package content
- Container-registry pull tokens for base images

Encrypted to **both** the quarantine-pool public key and the trusted-pool public key — so it's available in
both B1 and B2.

The classification is org responsibility. The structural rule: anything in `build/` must be safe to
exfiltrate (it cannot be, because of MICROVM no-egress, but the org should be willing to assume that
boundary fails). If a secret wouldn't be safe in that scenario, it goes in `org/`, not `build/`.

#### Test suite policy

The build script in the source repo declares which test suites need trusted-vault access:

```bash
# .daft/jobs/build (in work repo)
#!/usr/bin/env bash
set -o errexit
set -o pipefail

# Suites tagged 'requires_trusted_vault' are skipped when DAFT_TRUST_TIER != "trusted"
if [ "${DAFT_TRUST_TIER:-quarantine}" = "trusted" ]; then
  ./scripts/test/run.sh --all
else
  ./scripts/test/run.sh --skip-tag requires_trusted_vault
  printf '%s\n' '{"test_suites_skipped": ["integration_db_e2e", "deploy_smoke"]}' \
    > "${DAFT_ARTIFACTS_DIR}/skipped.json"
fi
```

The runner sets `DAFT_TRUST_TIER=quarantine` for B1 and `DAFT_TRUST_TIER=trusted` for B2. The build report
attached to the submission includes `test_suites_skipped[]`, so reviewers know which suites still need to
run in B2 post-merge.

#### Output

`submissions/<id>/builds/workspace/<job-id>.json` — the build report. Multiple entries accumulate over a
submission's lifetime as new shas are pushed and at land time when target may have drifted.

```json
{
  "job_id": "submission-1234-workspace-abc1234",
  "phase": "workspace",
  "target_sha_at_merge": "tgt789xyz",
  "source_sha": "src123abc",
  "merged_workspace_sha": "merge456def",
  "exit_code": 0,
  "started_at": "2026-05-06T14:30:00.000000000Z",
  "finished_at": "2026-05-06T14:42:18.000000000Z",
  "duration_ms": 738000,
  "trust_tier": "quarantine",
  "test_suites_run": ["unit", "integration_local"],
  "test_suites_skipped": ["integration_db_e2e", "deploy_smoke"],
  "artifacts": "s3://daft-artifacts/jobs/submission-1234-workspace-abc1234/"
}
```

#### Failure modes

- **Merge conflict during target → source merge:** state `merge_conflict`. Submitter rebases and pushes a
  new source sha. Re-runs from G2.
- **Build or non-skipped tests fail:** state `workspace_build_failed`. Submitter pushes a fix.
  Re-runs from G2.
- **MICROVM startup failure / infra error:** state `infra_failure`. Operator-paged; submission is
  re-queueable without code changes.

#### Success → `workspace_validated`

State moves to `workspace_validated`. Review opens. The submission becomes visible in reviewers' queues.

### R — Human Review

**Goal:** the trust gate. Humans decide whether the code is good enough to merge and to be entrusted with
trusted secrets at land time.

#### Visibility

Submissions appear in a reviewer's queue **only when** `status >= workspace_validated`. The CLI
(`daft-crs-list`) and dashboard filter by this. Reviewers never see submissions that have failed earlier
gates — those go to the submitter's queue, not the reviewer's.

#### Review events

Each review event is a signed file under `submissions/<id>/reviews/`. Events:

- `<reviewer-fpr>-approve.json`
- `<reviewer-fpr>-request-changes.json`
- `<reviewer-fpr>-comment.json`

```json
{
  "submission_id": "1234",
  "reviewer_fpr": "rvw456...",
  "kind": "approve",
  "issued_at": "2026-05-06T15:00:00.000000000Z",
  "source_sha_reviewed": "src123abc",
  "merged_workspace_sha": "merge456def",
  "summary": "LGTM, integration test for the new path looks good"
}
```

`source_sha_reviewed` is critical: an approval applies to a *specific* sha. If the submitter pushes a new
sha after approval, that approval is invalidated by default policy.

#### Approval policy

`.daft/authz/policies/<repo-or-org>-review.sh` — executable receiving the submission state and review log
on stdin, exits 0 if approval policy is satisfied. Examples:

- "Any single approve, no request-changes outstanding"
- "Two approves from distinct reviewers, no request-changes outstanding"
- "CODEOWNERS-shaped: one approve from each owning team for files changed"
- "Approves from at least one senior reviewer, no request-changes outstanding"

#### Push during review

If the submitter pushes a new source sha during review, the submission state drops back to
`static_checks_running`. All prior approvals are invalidated unless policy explicitly preserves them
(rare, usually a bad idea).

#### Outcome

When approval policy is satisfied → state `approved`. The merger can now act.

### B2 — Canonical Build

**Goal:** with full trusted vault, build and test the trial-merge workspace, and only land the merge if
the build passes AND the push wins the race against any newer commits to target. This is the final
go/no-go and the trust gate's payoff: HIL has approved, so trusted-vault code finally runs on this code.

#### Merger acts — the land loop

The merger (human or automated role per `land-policy.sh`) initiates land. The system enters a retry
loop:

```text
loop:
  1. Snapshot current target sha → T.
  2. Re-trial-merge target@T into source@S.
     - Conflict → state `merge_conflict_at_land`. Submitter rebases; approvals invalidated by default
       policy unless explicitly preserved. Exit loop.
     - Clean, produces merge commit M with parents (T, S).
  3. Run B2 on M:
     - Trusted pool, vault scope = `build/` + `org/`.
     - Full test suite, including suites skipped in B1.
     - B2 fail → state `landing_failed`. Target untouched. Submission reopens with B2 report. Exit
       loop.
  4. Attempt to push M to target with `git push --force-with-lease=<target-ref>:T`.
     - Push accepted (target was still at T) → state `landed`. Exit loop.
     - Push rejected (target moved past T during B2) → log the race; loop.
```

The `--force-with-lease=<ref>:T` is the load-bearing primitive: git refuses the push iff target has
advanced past T since the trial merge. There is no time-of-check-to-time-of-use window — the lease check
and the push are atomic on the receiving side.

#### Race semantics — what the loop actually costs

Each rejected push costs one full B2 re-run, because the merge commit M is anchored to a specific T and
target has moved past T. The new T means a new trial merge and a new build.

For low-to-mid-throughput targets (the segment DAFt addresses, < 200 commits/day to any one target),
collisions during B2 are rare; the loop exits on the first iteration almost always. For high-throughput
targets the loop becomes a livelock risk — B2 can never finish before the next commit arrives. That's
out of scope for the segment; merge-train coordination is the right answer at that scale and is not a
CRS substrate concern.

The submission's build history records every B2 attempt: `submissions/<id>/builds/canonical/<job-id>.json`
accumulates one entry per loop iteration, with `target_sha_at_merge` distinguishing them.

#### Trust scope

- **Pool:** Trusted.
- **Vault scope:** `build/` + `org/` — the full org vault.
- **Isolation:** trusted runner. The code has been HIL-approved per the trust principle (review is the
  trust gate, not merge); trusted vault access is granted from this point forward. MICROVM is no longer
  required, but orgs may keep it as defense-in-depth.

#### Outcomes

- **`landed`:** B2 green AND push-with-lease accepted. The merge commit M is now target's HEAD. Target
  history shows exactly one new commit per submission landing: the merge commit. No reverts, no
  almost-landed commits, no audit pollution.
- **`landing_failed`:** B2 failed. Target was never touched; no commits to revert. Submission reopens
  with the B2 report attached. Submitter pushes a fix, cycle restarts from G2.
- **`merge_conflict_at_land`:** the re-trial-merge inside the loop produced a conflict. Target moved in
  a way that conflicts with source. Submitter rebases.

#### Why "build then push" rather than "merge then build, revert on failure"

The merge-then-build-revert model (what GitHub default PR merges do) is operationally simpler — no race
loop — but pollutes target history with almost-landed commits and revert commits whenever B2 fails.
DAFt's audit-trail principle is "the git log is the truth"; merge commits should mean "this code is
landed and intended to stay." Revert commits as a routine part of the land flow degrade the signal.

The build-then-push model accepts a retry loop in exchange for a clean target history: target's `main`
log only contains commits that actually landed and were never reverted. Submissions that fail B2 leave
no trace in target — they live in the audit trail under `.daft/submissions/<id>/`, not in target's
history.

For DAFt's segment this tradeoff is right: collisions are rare, target history clarity is high-value.

## 6. Vault Tier Model

```text
.daft/vault/
├── users/<submitter-fpr>/   # Submitter-contributed secrets.
│                            # age recipients: quarantine-pool public key.
│                            # → readable in B1 only.
│
├── build/                   # Org BUILD-tier secrets — read-only, low-blast-radius.
│                            # age recipients: quarantine-pool public key, trusted-pool public key.
│                            # → readable in B1 and B2.
│
└── org/                     # Org TRUSTED-tier secrets — full power.
                             # age recipients: trusted-pool public key only.
                             # → readable in B2 only.
```

| Tier | Examples | Recipients | Where readable |
| --- | --- | --- | --- |
| `users/<fpr>/` | Submitter's personal API tokens, scratch test creds | Quarantine pool key | B1 |
| `build/` | Private package-registry pull tokens, signed-binary verification keys, internal proxy URLs | Quarantine pool key + Trusted pool key | B1, B2 |
| `org/` | Deploy keys, DB write creds, release-signing keys, prod admin tokens, notification creds | Trusted pool key only | B2 |

**Structural enforcement:** the boundary is not policy — it is cryptography. A Quarantine-pool runner
cannot decrypt `org/` because the ciphertext does not list the Quarantine pool's public key as a
recipient. age-encrypt-to-pubkey produces ciphertext only openable by the matching private key. There is
no "decrypt anyway" code path.

**Rotation:** rotating a tier's pool key is `age-keygen` + re-encrypting all entries to the new recipient
list + retiring the old runner-pool key. The git history retains the prior ciphertext for audit; the
private key it was encrypted to no longer exists.

## 7. Runner Pool Model

| Pool | Holds private key for | Runs gates |
| --- | --- | --- |
| **Quarantine** | Quarantine pool key (decrypts `users/<*>/`, `build/`) | G2, B1, land-time B1 re-run |
| **Trusted** | Trusted pool key (decrypts `build/`, `org/`) | B2 |

Pool membership is set at runner registration (`make daft-runner-init --pool=quarantine|trusted`). A
runner cannot move between pools without re-registration; its identity is bound to the pool key it holds.

The Shepherd (Group 7) routes jobs to pools based on the gate the job services. Jobs created by G2 or B1
specify `pool: quarantine`; jobs created by B2 specify `pool: trusted`. Runners self-select jobs from
their queue partition.

**Pool size:** independent. An org may run 10 quarantine runners and 2 trusted runners, or vice versa,
based on load shape. Quarantine pools typically larger because B1 throughput dominates.

## 8. State Machine

```text
submitted
   │
   ▼
awaiting_submitter_approval ──approved──→ static_checks_running
   │ revoked                                 │ check fails
   ▼                                         ▼
suspended                            static_checks_failed
                                             │ push new sha
                                             ▼
                                     static_checks_running ──all pass──→ workspace_build_running
                                                                            │ merge conflict       │ build fail        │ ok
                                                                            ▼                      ▼                   ▼
                                                                      merge_conflict     workspace_build_failed   workspace_validated
                                                                            │ rebase+push          │ push new sha       │
                                                                            └──→ static_checks_running ←────────────────┤
                                                                                                                        ▼
                                                                                                                  under_review
                                                                                                                        │ approve
                                                                                                                        ▼
                                                                                                                    approved
                                                                                                                        │ merger acts (begin land loop)
                                                                                                                        ▼
                                                                                                              re_trial_merge_check  ◄──────┐
                                                                                          ┌─────────────────────────────┼─────────────────┐│
                                                                                          ▼ conflict now                ▼ clean → build M ││
                                                                                merge_conflict_at_land            canonical_build_running ││ push rejected
                                                                                          │ rebase+push                  (Trusted pool)   ││ (target advanced
                                                                                          ▼                              │ B2 fail        │ B2 ok during B2)
                                                                                static_checks_running                    ▼                ▼
                                                                                                                   landing_failed  attempting_push
                                                                                                                   (target          (--force-with-lease
                                                                                                                    untouched,       =ref:T)
                                                                                                                    reopen)          │
                                                                                                                                     ├────┘ rejected → loop
                                                                                                                                     │
                                                                                                                                     ▼ accepted
                                                                                                                                  landed
```

**Transitions out of any pre-`landed` state:**

- `abandoned` — submitter closes the submission without landing it.
- `suspended` — submitter approval revoked. Returns to prior state on re-approval, but re-validates
  through the gate that detected the revocation (paranoia: a revoked submitter cannot benefit from prior
  green gates).

**Reset rule:** any push of a new source sha drops state to `static_checks_running`. Cheap-first: never
skip cheap gates because expensive gates passed previously on a different sha.

## 9. Submission Directory Layout

```text
.daft/submissions/<submission-id>/
├── manifest.json                                  # signed: source repo+ref+sha, target repo+ref,
│                                                  # author pubkey-fpr, opened_at, submission-id,
│                                                  # forge-context (optional, set by forge plugin)
├── static-checks/
│   ├── org/<check-name>.json                      # one per org check, latest run
│   └── repo/<check-name>.json                     # one per repo-local check, latest run
├── builds/
│   ├── workspace/<job-id>.json                    # B1 reports — multiple over a submission's lifetime
│   │                                              # (one per push and one per land-time re-run)
│   └── canonical/<job-id>.json                    # B2 reports — one per land attempt
├── reviews/
│   ├── <reviewer-fpr>-approve.json                # signed approve event
│   ├── <reviewer-fpr>-request-changes.json        # signed request-changes event
│   └── <reviewer-fpr>-comment.json                # signed comment event
└── status.json                                    # current submission state, latest sha refs, summary
```

**`manifest.json` schema:**

```json
{
  "submission_id": "1234",
  "submitter_fpr": "abc123...",
  "source": {
    "repo": "git@github.com:byiq/foo.git",
    "ref": "refs/heads/feature/bar",
    "sha": "src123abc"
  },
  "target": {
    "repo": "git@github.com:byiq/foo.git",
    "ref": "refs/heads/main"
  },
  "opened_at": "2026-05-06T13:45:00.000000000Z",
  "forge_context": {
    "kind": "github_pr",
    "url": "https://github.com/byiq/foo/pull/42",
    "number": 42
  }
}
```

`forge_context` is set by a forge ingestor plugin if one is wired in; absent for pure-CLI submissions.

**`status.json` schema:**

```json
{
  "submission_id": "1234",
  "state": "under_review",
  "current_source_sha": "src123abc",
  "current_target_sha_at_merge": "tgt789xyz",
  "latest_workspace_sha": "merge456def",
  "approvals_satisfied": false,
  "approvals_required": 2,
  "approvals_received": 1,
  "request_changes_outstanding": 0,
  "updated_at": "2026-05-06T15:30:00.000000000Z"
}
```

## 10. Submission Lifecycle Flows

### Happy path

1. Submitter pushes branch, runs `make daft-crs-submit SOURCE=...`. Manifest committed; state `submitted`.
2. Submitter is already approved (G1 short-circuit) → `static_checks_running`.
3. Static checks pass → `workspace_build_running`.
4. Workspace builds and tests pass → `workspace_validated`. Visible to reviewers.
5. Two reviewers approve → policy satisfied → `approved`.
6. Merger triggers land. Loop iteration 1: snapshot target sha = T1, re-trial-merge clean → M1.
7. B2 runs on M1 with full trusted vault → green.
8. Push M1 with `--force-with-lease=ref:T1` → target still at T1 → push accepted → `landed`.

Total elapsed time: order of minutes to hours, depending on review latency. Machine time ~5–15 minutes
when the land loop exits on iteration 1 (typical for the segment).

### Push during review

1. Submission is `under_review`, one approval in.
2. Submitter pushes a new sha (fixing a typo a reviewer found).
3. State drops to `static_checks_running`. Existing approvals invalidated (default policy).
4. Cycle repeats from G2 with the new sha.

### Drift at land time (loop iterates once cleanly)

1. Submission is `approved`. Target has advanced 4 commits since B1 last ran, but no conflicts.
2. Merger triggers land. Loop iteration 1: snapshot target sha = T1. Re-trial-merge clean → merge
   commit M1.
3. B2 runs on M1 with full trusted vault. Passes.
4. Push M1 to target with `--force-with-lease=ref:T1`. Target is still at T1 (no further drift during
   B2) → push accepted → `landed`.

### Land-time race — push rejected during land

1. Submission is `approved`. Loop iteration 1: snapshot target sha = T1. Re-trial-merge clean → M1.
2. B2 runs on M1, takes 8 minutes. Passes.
3. While B2 was running, another submission landed: target is now at T2.
4. Push M1 with `--force-with-lease=ref:T1` — rejected (target is no longer at T1).
5. Loop iteration 2: snapshot target sha = T2. Re-trial-merge: clean → M2 (different parent than M1).
6. B2 re-runs on M2. Passes.
7. Push M2 with `--force-with-lease=ref:T2`. Target still at T2 → push accepted → `landed`.

The submission's `builds/canonical/` directory contains both the M1 and M2 build reports as audit
records. Target's history contains only M2 — the actually-landed merge commit.

### Land-time conflict (race produces a conflict)

1. Submission is `approved`. Loop iteration 1: B2 passes on M1 against T1, push rejected.
2. Loop iteration 2: snapshot target sha = T2. Re-trial-merge target@T2 into source: **conflict** (T2
   contains a commit that touches the same lines source modified).
3. State `merge_conflict_at_land`. Submitter must rebase source on top of T2 and push a new sha.
4. State drops to `static_checks_running` for full re-validation against the new source sha.

### Land-time canonical build failure

1. Submission is `approved`. Loop iteration 1: re-trial-merge clean → M1.
2. B2 runs on M1 — fails. A test that was skipped in B1 (because it required trusted vault) breaks.
3. State `landing_failed`. Target was never touched; no revert needed. The merge commit M1 was never
   pushed.
4. Submission reopened with the B2 report attached. Submitter investigates, fixes the failing test,
   pushes a new source sha.
5. Cycle repeats from G2.

### Submitter approval revoked mid-flow

1. Submission is `under_review`. Submitter approval is revoked (signed event).
2. Next gate evaluation detects the revocation → state `suspended`.
3. No further machine work happens. Reviewers see a banner explaining suspension.
4. If submitter is re-approved later → state returns to the gate the revocation interrupted, re-runs from
   G2 for paranoia.

## 11. Forge Integration

Forge plugins are translation layers, not substrate code. Each forge gets a directory of plugins:

```text
.daft/plugins/forges/<forge-name>/
├── ingestor/                           # forge events → CRS state writes
│   ├── on-pr-opened
│   ├── on-pr-synchronized
│   ├── on-pr-closed
│   └── on-review-submitted
├── responder/                          # CRS state changes → forge API calls
│   ├── on-static-checks-failed
│   ├── on-workspace-validated
│   ├── on-canonical-build-failed
│   └── on-landed
└── config.json                         # forge endpoint, auth (in vault), check-run name
```

**Ingestor scripts** receive a forge event payload on stdin and translate it into a signed write to
`.daft/submissions/<id>/`. For GitHub: a `pull_request.opened` webhook becomes a `manifest.json` plus an
initial `status.json`. A `pull_request_review.submitted` event becomes a `reviews/<fpr>-approve.json`.

**Responder scripts** are triggered by CRS state transitions (via the responder plugin contract from
Group 7's plugin formalization) and POST to the forge API. For GitHub: `workspace_validated` triggers a
check-run update with conclusion `success`; `canonical_build_failed` triggers a check-run update with
conclusion `failure` and a comment linking to the build log.

**Per-forge isolation:** GitHub's plugin does not know GitLab exists. Adding Bitbucket support is a new
directory. None of these plugins changes substrate semantics or affects another forge.

**Pure-CLI mode:** if no forge plugin is loaded, the substrate is fully usable via `make daft-crs-*`
targets. A team running git over SSH and reviewing in pull terminal sessions has the full workflow.

## 12. Policy Hooks

All policy is bash scripts under `.daft/authz/policies/`. Each script takes JSON context on stdin and
exits 0 = allowed, non-zero = denied (with reason on stderr).

| Script | Decides |
| --- | --- |
| `submitter-approval.sh` | Is this approver allowed to approve this submitter? |
| `<repo-or-org>-review.sh` | Are the current approvals sufficient to land this submission? |
| `land-policy.sh` | Is this merger allowed to land this submission, and what to do on target drift |
| `<check-name>.sh` (under `.daft/checks/<layer>/`) | Static-check verdict (the check itself) |
| `revocation-authority.sh` | Is this revoker allowed to revoke this submitter's approval? |

**Default policies** ship with the project as bash one-liners covering the common cases. Orgs override
by replacing the file. Policy is not a configuration screen; it is code that lives in git, reviewable in
commits, runnable in tests.

## 13. Audit Trail

Every state transition is a signed commit on the central daft repo. Common commit message conventions:

```text
crs/submit: <id> by <submitter-fpr>
crs/approve-submitter: <submitter-fpr> by <approver-fpr>
crs/static-checks-passed: <id> sha=<source-sha>
crs/workspace-validated: <id> sha=<source-sha> workspace=<merge-sha>
crs/review-approve: <id> by <reviewer-fpr> sha=<source-sha>
crs/review-request-changes: <id> by <reviewer-fpr> sha=<source-sha>
crs/merger-acts: <id> by <merger-fpr>
crs/landed: <id> target-pre=<sha-pre> target-post=<sha-post>
crs/landing-failed: <id> reason=<canonical_build_failed|...>
crs/suspended: <id> reason=submitter-approval-revoked
```

Reproducing a submission's full history:

```bash
git log --reverse --format='%h %s' -- .daft/submissions/<id>/
```

Reproducing all activity by a specific reviewer:

```bash
git log --reverse --format='%h %s' --grep="by <reviewer-fpr>"
```

The signed-event chain is the audit log. There is no separate database, no proprietary dashboard, no
retention window.

## 14. Out of Scope (for the CRS substrate work)

The CRS substrate (Group 4) ships the gate machinery, vault tiers, runner pools, state machine, and
filesystem layout. The following are explicitly deferred:

- **Forge integrations.** Per-forge ingestor + responder pairs are Group 5.
- **Webhook ingestion.** CRS substrate is poll-friendly; webhook listeners come with Group 6.
- **Web dashboard.** A small dashboard surfacing submissions, gates, and builds is Group 6. Until then,
  CLI is the operator interface.
- **Matrix builds within a submission.** B1 is currently one build; matrix expansion is Group 6.
- **Cross-cluster CRS.** Group 9.
- **Migration tooling for existing PRs.** A team adopting CRS with an existing pile of open PRs needs an
  importer (forge → CRS bulk-translation). Group 5.
- **Performance for >1000 active submissions.** The current design is sized for the 50–200-jobs/day
  segment; scaling beyond is post-roadmap.

## 15. Open Questions

These are not blockers for Group 4 but should be settled before substrate freeze:

1. **Approval persistence on rebase.** Default: rebases invalidate prior approvals. Should there be a
   policy option for "approvals carry forward if the diff is unchanged" (some orgs want this)?
2. **Multiple targets per submission.** A submitter wanting to land the same change on `main` and on
   `release/v2`. Current model: one submission per (source, target). Acceptable?
3. **Auto-merge on green.** A merger who tags the submission `auto-land-when-green` and walks away. Land
   fires automatically on satisfaction of approval policy + green B1. Useful but a security
   consideration: what if target drifts dramatically?
4. **Submitter onboarding UX.** First-time submitter's approval workflow needs a discoverable path (CLI
   prompt? Slack bot? Dashboard?) — not in substrate but needed for adoption.
5. **Test-suite requires-trust declaration.** Currently the build script self-reports skips. Should
   there be a substrate-level manifest of "this suite requires trusted vault" so the runner can enforce
   rather than trust?

## 16. Implementation Roadmap (CRS-Specific)

Substrate work, sized within Group 4 (~4 weeks solo):

| Week | Deliverable |
| --- | --- |
| 1 | `.daft/submissions/` filesystem contract; `manifest.json`, `status.json` schemas; CLI scaffolding (`make daft-crs-submit`, `daft-crs-list`, `daft-crs-status`); state-transition commit message conventions |
| 2 | G1 + G2 gate runners (sleep-loop scripts, like coordinator); `authz/submitters/` approval/revocation flow; static-check contract + reference org-mandatory checks (gitleaks, syft, license-scan) |
| 3 | B1 workspace build (Quarantine pool, Build-vault scope, MICROVM); merge mechanics (target → source); `requires_trusted_vault` test-skip protocol; build report schema |
| 4 | Review file format + signed-review verification; merger flow + B2 canonical build (Trusted pool); land-time re-trial-merge logic; revert-on-canonical-failure; integration tests in bats; compose-stack scenarios |

Group 5 (Forge integrations) ships per-forge plugins on top of this substrate; Group 5 is sized
per-forge (~1–2 weeks each).

## 17. References

- Project README (`/README.md`) — overall architecture and project philosophy.
- COMPARISON (`/COMPARISON.md`) — positioning vs SaaS and Jenkins.
- MVP plan (`~/.claude/plans/create-a-thorough-mvp-kind-lovelace.md`) — the foundation CRS is built on.
- Roadmap (in conversation, to be consolidated into `.doc/ROADMAP.md` next) — the eight-group sequence
  this work fits into.
