# D.A.F.T — Dumb And Fast Tasks

**Your `git` partner.**
A CI/CD system that lives in your repo, runs on your machines, and trusts your signatures.

The "tasks" — small, single-purpose Bash components — are the unit of orchestration. No server. No database. No JVM.
No SaaS bill.

## The Name

**DAFt CICD** is FOSS, built to compete head-on with the paid CI/CD systems that dominate the field today: GitHub
Actions hosted runners, CircleCI, Buildkite, GitLab Premium, Harness, the rest of the SaaS rack.

### Heritage

`DAFT` is `D.A.F.T` is **Dumb and Fast Tasks**.

The whole DAFt philosophy is *history is the audit log, the repo is the database*, so encoding the origin name in
the first commit is not a gimmick — it is consistent with the architecture.
Same repo, different signals for different readers, no contradiction.

This is the Linus precedent in miniature. Linus Torvalds wrote Git because CVS, SCCS, and SVN were not cutting it for
him. He named it Git ("a stupid content tracker", "I'm an egotistical bastard, so I name all my projects after
myself"). Deliberately unserious name on a tool that became infrastructure. There is also a real tradition of
irreverent FOSS naming this slots into — `git`, GIMP, `awk` — tools whose creators refused to dress them
up. DAFt joins that lineage.

The cleaned-up name **DAFt CICD** is what the project answers to in production, in pitches, in Slack channels where
people share tools without having to bowdlerize.

This is the author's legacy. Use it, fork it, ship it.

## What It Is

DAFt CICD is a self-hosted CI/CD system for solo developers and small teams. It does not replace your VCS, sit in
front of it, or mediate it — it rides along with `git` as the substrate. The repository is the database. Git push is
the only atomic lock. Jobs are Bash scripts. Runners are pull-based loops on whatever hardware you already own — and
dynamic cloud runners spin up on demand and tear down when idle, so you never pay for a hot VM that isn't working.

---

## Who This Is For

Solo developers and 5-person shops running 50–200 jobs/day who want self-hosted CI without a SaaS dependency, without
Kubernetes, and without standing up Postgres next to a JVM next to an OAuth provider.

If you're sustaining ~10 jobs/sec, DAFt is the wrong tool. Push contention, repo bloat, and log-streaming
infrastructure are real concerns two orders of magnitude past what this segment will ever generate.

## Market Position

The "I want self-hosted CI without a SaaS dependency" field is grim:

| Tool | Why it's a poor fit for the segment |
| --- | --- |
| Woodpecker / Drone | Server + DB + OAuth setup — the exact friction DAFt avoids |
| Tekton / Argo Workflows | Require Kubernetes; absurd overhead for one human |
| Concourse | Server + Postgres + workers; multi-process orchestration for a solo project |
| Jenkins | JVM, plugins, WAR file, configuration sprawl |
| Forgejo / Gitea Actions | Improving, but you also have to run the forge |
| Buildbot | Functional, but the Python config feels like 2008 |
| Sourcehut builds | Strong philosophy, tied to Sourcehut as the forge in practice |

The realistic competitive set:

- **Laminar** (`laminar.ohwg.net`) — closest spiritual sibling. Minimalist C++ daemon, jobs are bash scripts in a
  directory, no DB, runs on a Pi. Probably the only thing that beats DAFt's "git clone and go" pitch — and only because
  there's no clone, just a single binary.
- **Sourcehut builds** — minimalist, signed manifests, scripts-based. Architecturally adjacent but coupled to Sourcehut.
- **`cron` + `make` + a deploy script** — what many solo devs actually use today. Not wrong; just lacks audit and
  structure.

DAFt's differentiation against this set is the signed-commit audit trail. It's overkill for the segment, but it's
free — which is the right kind of overkill.

## Core Philosophy

- **The repository is the database.** No RAFT, SQL, or Redis. Git handles concurrency (via push collisions), audit
  trails, and state persistence.
- **Dumb execution.** Logic is decoupled from infrastructure. If it runs in Bash, it runs in DAFt.
- **Physics-based provisioning.** Runners are defined by ISA, isolation level, and resources, not provider names.
- **Filesystem as the API.** All communication happens via file mutations and `git mv` operations.
- **No hot cloud runners.** Runners are spun up on demand by the Shepherd and torn down the moment they go idle. A
  cloud VM that is not currently executing, draining, or bootstrapping should not exist.

---

## Architecture

### The `.daft/` Database

The entire DAFt state machine lives under a single top-level directory: **`.daft/`**. This is *the database*. There is
no Postgres, no Redis, no SQLite — the filesystem is the schema, and `git` is the transaction log.

Why a single hidden root:

- **One namespace, no collisions.** The repo root stays clean. Your project's `src/`, `docs/`, `tests/`, `Makefile`,
  whatever — none of it competes with DAFt for top-level real estate. DAFt occupies one slot: `.daft/`. Drop DAFt into
  any existing repo without renaming a single file of yours.
- **One ignore line if you ever want to leave.** `echo .daft/ >> .gitignore` and DAFt is gone from `git status`. No
  litter strewn across the tree.
- **One `chmod`/`chown` boundary for runners.** Hardware runners that need write access to queue/active/workspace get
  scoped to one directory, not eleven.
- **One `find` to inventory the whole state machine.** `find .daft/active -mmin +60` lists stale claims; `git log
  -- .daft/compliance/` shows every signed deployment in history; `du -sh .daft/workspace/` tells you how much log
  buffer you've accumulated. The database is greppable, tailable, and `du`-able with the tools the developer already
  has muscle memory for.
- **The dot prefix is enough.** Each child directory inside `.daft/` (`authz/`, `events/`, `queue/`, …) drops the
  leading dot — they are already inside a hidden namespace, so the visual noise is unnecessary. `.daft/` is hidden;
  its contents don't need to be hidden twice.

Each leaf directory ships with a `.keep` file in commit zero so an empty queue, an empty vault, or an empty compliance
log is still a tracked, well-formed state — runners and ingestors can `cd` into them on day one without `mkdir -p`
ceremony.

### State Machine (Repository Structure)

The filesystem structure defines the global state. Every directory is a bucket or registry.

```text
.daft/                     # Single hidden root — the entire DAFt state machine
├── authz/                 # Identity ledger & RBAC
│   ├── keys/              # Public keys (.pub) for Users and Runners
│   ├── mapping/           # JSON maps: Identity -> Role
│   └── policies/          # Bash scripts returning exit 0/1 for permissions
├── events/                # The Ingestor Inbox (signed JSON payloads)
├── queue/                 # Execution folders (sorted by ISA/Capability)
│   ├── x86_64/
│   ├── arm64/
│   ├── riscv64/           # Heterogeneous swarms welcome
│   └── high-gpu/
├── active/                # Current execution lock-files (claimed via git mv)
├── runners/               # Runner registry (status, identity, ISA, resources)
├── registry/              # Metadata for OCI and blobs (CAS pointers)
│   ├── oci/               # Manifests for container images
│   └── artifacts/         # Hashes and locations for binaries/caches
├── tickets/               # Gatekeeper: ticket/issue status (approved/blocked)
├── vault/                 # age-encrypted secrets per Runner public key
├── workspace/             # Shared log buffers and artifact transit
├── compliance/            # Signed build manifests (audit-ready chain of custody)
└── plugins/               # The Task-kit: responders & lifecycle hooks
    ├── lifecycle/         # PROVISION, BOOTSTRAP, DRAIN, TERMINATE
    ├── responders/        # Build, Scan, Deploy, Notify, Matrix, Fan-in
    └── ingestors/         # Webhook, ChatOps, Timer, Alarm scripts
```

All DAFt state lives under `.daft/`. Repo content (your project's source, your tests, your `Makefile`) lives wherever
it normally would — DAFt does not colonize the root namespace.

### Event Sources (Ingestors)

Ingestors convert external intent into a signed `job.json` file.

- **Web hooks** — CGI/Netcat listener for VCS providers. Validates signatures and pushes to `.daft/events/`.
- **ChatOps** — Slack/Teams bridge. Commands (e.g., `/deploy`) are checked against `.daft/authz/` and committed as jobs.
- **Web UI** — A lightweight dashboard wrapper for `git log` and `ls`. Provides a "Run" button for manual triggers.
- **Human-in-the-loop approvals** — Pipeline gate that pauses until `.daft/tickets/TICK-ID.json` is mutated to
  `status: approved`.
- **Systemic events** — Local cron timers, observability alarms (e.g., `AUTO_ROLLBACK` on latency spikes), GitOps drift
  correction.

### Runner Architecture & Lifecycle

Runners are pull-based loops that self-select jobs they are physically capable of running.

**Isolation levels:**

- `BARE` — process-level (trusted tasks)
- `USER` — Linux namespaces (`unshare`)
- `SANDBOX` — Bubblewrap (`bwrap`); no network, private `/tmp`
- `CONTAINER` — Podman/OCI standard
- `MICROVM` — Firecracker; total kernel isolation

**Git alternates** — runners on persistent hardware maintain a `/var/lib/daft/cache` object store and use
`git clone --reference` for near-instant checkouts.

### The Shepherd: On-Demand Runner Provisioning

**Zero hot cloud runners.** DAFt does not keep idle VMs billing in the background. Cloud runners exist only when work
exists. The Shepherd is a first-class architectural component, not an afterthought.

**The Shepherd is a queue-watcher.** It diffs supply against demand on every tick:

- **Demand** — count and shape of jobs in `.daft/queue/<ISA>/<capability>/` (CPU, RAM, GPU, isolation level).
- **Supply** — registered runners in `.daft/runners/` with status `idle` or `executing`, scoped by ISA and capability.
- **Verdict** — for each `(ISA, capability)` bucket where demand exceeds supply, emit a `PROVISION` event matched to a
  provisioner plugin; for excess idle supply past the suicide threshold, runners self-terminate.

**Provisioner plugins.** Spinning up a runner is a plugin contract, not a hardcoded path. Each provisioner answers a
specific shape of demand:

| Provisioner | Spins up |
| --- | --- |
| `provision-aws-ec2` | Spot or on-demand EC2 in a target AZ; tagged for billing attribution |
| `provision-hetzner` | Hetzner Cloud VM; cheapest x86_64/arm64 for general jobs |
| `provision-fly-machine` | Fly.io machine; fast cold-start for short jobs |
| `provision-firecracker-local` | MicroVM on a local hypervisor host |
| `provision-podman-local` | Container on a registered bare-metal host |
| `provision-wake-on-lan` | Wakes a sleeping workstation/Pi for ARM or GPU jobs |
| `provision-gpu-runpod` | GPU-bearing instance from a GPU-only provider |

A provisioner is selected by matching the queued job's `(ISA, isolation, resources)` triplet against each
provisioner's declared capabilities in `.daft/plugins/lifecycle/provisioners/<name>/capabilities.json`. The Shepherd picks
the cheapest match that satisfies the constraints. Adding a new cloud or hardware target is a new plugin directory,
not a code change.

### Dynamic Runner Lifecycle Events

Every dynamic runner — cloud VM, MicroVM, container, woken bare-metal host — moves through the same explicit
lifecycle. Each transition is an event written to Git (`.daft/runners/<runner-id>/lifecycle.log`) and dispatched to plugin
hooks under `.daft/plugins/lifecycle/<phase>/`. This contract is uniform across providers; provisioners differ only in how
they implement each phase.

```text
PROVISION → BOOTSTRAP → REGISTER → CLAIM → EXECUTE → RELEASE → DRAIN → TERMINATE → REAP
```

| Phase | Trigger | Responsibility | Failure mode |
| --- | --- | --- | --- |
| `PROVISION` | Shepherd verdict: demand exceeds supply | Allocate the underlying machine (API call to cloud, WoL packet, podman create). Record provider handle in `.daft/runners/<id>/handle.json`. | Provisioner exits non-zero → Shepherd marks bucket cooldown, retries with next-cheapest provisioner. |
| `BOOTSTRAP` | Machine reachable | Install DAFt runner binary, fetch repo via `git clone --reference` against alternates cache, generate runner keypair, decrypt scoped secrets. | Bootstrap timeout → `TERMINATE` immediately, no registration. |
| `REGISTER` | Bootstrap complete | Push runner public key to `.authz/keys/runners/`, write capabilities to `.daft/runners/<id>/capabilities.json`, set status `idle`. | Push collision → retry with rebase; after N retries, `TERMINATE`. |
| `CLAIM` | Runner loop sees matching job | `git mv .daft/queue/<ISA>/<job> .daft/active/<id>/<job>`; first push wins, losers retry. | Push rejected → loop continues, no state change. |
| `EXECUTE` | Claim succeeded | Run job script under declared isolation level. Stream logs to `.daft/workspace/<job>.log`. | Job non-zero → `RELEASE` with failure status; logs scrubbed and committed. |
| `RELEASE` | Job finished (any outcome) | `git mv .daft/active/<id>/<job> .daft/archive/<date>/<job>`; emit signed manifest into `.daft/compliance/`; reset status to `idle`. | Push collision → rebase and retry; only one path is correct. |
| `DRAIN` | Idle timer fires OR Shepherd issues drain order | Stop claiming new jobs, finish in-flight work, deregister from `.daft/runners/`. | Stuck job → `DRAIN` blocks until job timeout, then forced `RELEASE`. |
| `TERMINATE` | Drain complete | Provisioner-specific teardown: API call to destroy VM, container stop, sleep WoL host. Billing stops here. | Teardown failure → log to `.daft/runners/<id>/orphans.log`; Reaper retries. |
| `REAP` | Runner missed N heartbeats | External Reaper claims orphaned `.daft/active/` locks, returns jobs to `.daft/queue/`, force-terminates the provider handle. | Provider API down → orphan persists; surfaces in `daft doctor`. |

**Plugin authoring contract.** Each lifecycle phase is a directory of executable Bash scripts run in lexical order.
Hooks receive runner state as environment variables and read/write Git-tracked state. A complete provisioner is:

```text
.daft/plugins/lifecycle/provisioners/aws-ec2/
├── capabilities.json        # ISA, isolation levels, max resources, $/hour
├── provision                # Allocate the EC2 instance
├── bootstrap                # Install runner binary, fetch repo
├── register                 # Push key to .daft/authz/, set status idle
├── drain                    # Cordon and finish in-flight
├── terminate                # API call to destroy instance
└── reap                     # Forced cleanup if heartbeat lost
```

Every provisioner — cloud or local — implements the same seven scripts. Anything that can be expressed in Bash and
shells out to a provider CLI can become a runner backend.

**Zero-idle cost guarantees:**

- Suicide timer (default 10m idle) — runner self-issues `DRAIN` → `TERMINATE` without Shepherd involvement.
- Shepherd cooldown — when queue depth drops, Shepherd issues `DRAIN` orders to surplus runners oldest-first.
- Reaper — out-of-band watchdog that catches runners whose `TERMINATE` failed (provider API hiccup, network partition)
  and bills nothing further by force-destroying the provider handle.

The architectural invariant: **a cloud runner that is not currently executing a job, draining, or bootstrapping should
not exist.**

### Plugins (Mutation Responders)

Plugins are executable Bash scripts following the Unix pipe philosophy.

| Category | Responsibility |
| --- | --- |
| **Matrix Generator** | Consumes a template (e.g., `versions: [18, 20, 22]`); emits one concrete job per cell. |
| **Fan-In Coordinator** | Greps Git history; triggers a job only once all prerequisites are `completed`. |
| **Secret Injector** | Decrypts `age` files from `.daft/vault/` and exports to environment. |
| **Log Scrubber** | Real-time `sed` filter to redact secrets from stdout/stderr. |
| **Security Scanner** | SBOM (`syft`), vulnerability scan, license check; results signed into `.daft/compliance/`. |
| **Artifact Manager** | Tars, hashes, and pushes to CAS (S3/Minio/Nginx); updates `.daft/registry/`. |
| **Bouncer** | Policy-as-code script validating the User/Role/Action triplet. |
| **Feedback Bot** | Formats scannable UI cards for Slack/Teams; comments on Git PRs. |

### Auth & Security

- **AuthN (identity)** — Users and runners possess public keys in `.daft/authz/keys/`. All job files must be cryptographically
  signed.
- **AuthZ (permission)** — A "double-handshake" check:
  1. **Runner-to-state** — is the runner authorized to claim from this ISA queue?
  2. **Job-to-action** — does the signing user have the role required for the requested step?
- **Scoped secrets** — secrets are encrypted specifically for the public key of the runner authorized to execute that
  environment (testing vs. prod).

### DAFt Registry (OCI & Blobs)

- **CAS model** — binary blobs are stored in fragmented content-addressed storage. Metadata (JSON manifests) stays in
  Git.
- **Provable origin** — every image is linked back to a Git commit and a specific runner identity in `.daft/registry/`.
- **Local caching** — dedicated hardware runners can act as local mirrors for neighbors to prevent repeated massive
  cloud pulls.

### Compliance & Audit

- **Manifesting** — a `daft-manifest` responder gathers the signed event, runner ID, scrubbed logs, and SBOM into a
  signed bundle in `.daft/compliance/`.
- **Transparency** — the entire history of every deployment is a `git log` away, satisfying SOC2/ISO requirements
  without proprietary dashboards.

### Requirements for Compliance

1. **Git-backed consensus** — `git push` is the only atomic lock.
2. **Stateless orchestration** — no central database; any machine with the repo can act as a runner or shepherd.
3. **Redaction by default** — no log enters `.daft/archive/` or `.daft/compliance/` without passing through the scrubber.
4. **Hardware-first** — ISA and isolation must be respected over provider-specific labels.
5. **Offline-friendly** — approvals, ticket updates, and job submissions can be done offline and synced via `git push`
   later.
6. **On-demand-only cloud capacity** — cloud runners are provisioned in response to queue depth and torn down when the
   queue drains. No persistent hot pool; no idle billing.

---

## What Still Matters at This Scale

Four things that will determine whether DAFt actually lands for solo devs and small teams:

### 1. Bootstrap UX

"`git clone` and stand up a runner" is a few more steps than that:

- Generate signing keys
- Register runner public key in `.daft/authz/`
- Write a systemd unit so the runner survives reboot
- Set up the webhook ingestor with TLS if push-triggered

None of this is hard, but a 10-minute *zero-to-first-green-build* tutorial is the make-or-break artifact for this
audience. Laminar nails this; most competitors don't.

### 2. Live Log Tailing

Still matters with one user. When a build fails, the developer wants `tail -f` semantics, not `git log --grep`. The
runner streaming to `.daft/workspace/$JOB_ID.log` with a `tail -f` endpoint is sufficient at this scale — but it
should be explicit in the spec, not implied.

### 3. Crash Recovery Janitor

Even with one runner, an OOM mid-job leaves a stale `.daft/active/` lock. A 30-line cleanup script on runner startup solves
it:

> Any `.daft/active/` entry whose runner PID is dead → move back to `.daft/queue/`

Trivial to write, but it needs to exist.

### 4. Secret Rotation Friction

`age`-encrypted-per-runner-pubkey is cryptographically clean but operationally annoying. Solo devs will reach for
`.env` files in `.gitignore` regardless of what the docs prescribe. Ship two modes:

- **Lazy mode** — `source .env`, good enough for hobby projects.
- **Paranoid mode** — `age`-per-runner, for anything touching production.

---

## Status

v0.1.337 specification. The market for "self-hosted CI/CD for one human or one small team, no Kubernetes, no SaaS, no JVM,
no per-seat pricing" is genuinely underserved because every serious player chases enterprise scale. **DAFt CICD** is
FOSS, built to compete head-on with the paid systems on the features that actually matter — signed audit trails,
on-demand cloud capacity, and `git clone` to first green build. If it nails the bootstrap UX and ships a
*zero-to-first-green-build in 10 minutes* demo, it has a real audience.

**DAFt — your `git` partner.** Lives in your repo, runs on your machines, trusts your signatures. The author's
legacy. Fork it, ship it, replace your CI bill.
