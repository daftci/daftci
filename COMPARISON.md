# DAFt vs. Major CI/CD — Where DAFt Wins or Ties

This is a positioning document for the segment **DAFt CICD** is built for: solo developers and 5-person shops
running 50–200 jobs/day on self-hosted infrastructure. It compares DAFt against two cohorts:

- **SaaS:** GitHub Actions hosted runners, CircleCI, Buildkite, GitLab Premium, Harness.
- **Self-hosted FOSS:** Jenkins.

All claims assume the full DAFt roadmap (Groups 1–7) has shipped.

The document only lists the dimensions where DAFt is **structurally better** or **at feature parity**.
Dimensions where the alternatives lead are not in scope here; see the project README and roadmap for an
honest side-by-side.

## Part 1 — DAFt vs. SaaS CI/CD

## Where DAFt Is Structurally Better Than SaaS

These are advantages SaaS providers cannot easily copy without abandoning the SaaS model itself.

### Audit Trail

DAFt records every state transition as a signed git commit. The audit log is the repository — forever,
reproducible by `git log --reverse`, exportable to any other git host, and verifiable against the original
public keys.

SaaS dashboards keep logs in vendor-controlled stores subject to retention windows, plan-tier limits, and
proprietary export formats. The audit trail evaporates the day you cancel.

### Cost at Solo / Small-Team Scale

DAFt cost equals your hardware bill plus electricity. There is no per-seat fee, no per-minute meter, no
warm-pool surcharge. Adding the eleventh runner is free.

SaaS pricing typically combines per-minute compute (`$0.008–$0.04`/min for hosted runners), per-seat fees
(`$30+/seat/month` on CircleCI / Harness tiers), and warm-pool premiums. At 200 jobs/day across a small team
the SaaS bill is real money; DAFt's marginal cost is zero.

### Hot-Runner Cost Is Zero

The DAFt Shepherd allocates a cloud VM only when a job is in queue and tears it down within seconds of idle.
A cloud runner that is not currently executing, draining, or bootstrapping does not exist.

Every SaaS provider has either a minimum-runtime billing window or a warm-pool surcharge. The "instant pickup"
UX they sell is paid for by you, hour after hour, even when no job is running.

### Heterogeneous Hardware Pool

DAFt treats hardware as a queue attribute, not a vendor menu. Mix:

- Cloud x86_64 (AWS, Hetzner, Fly)
- ARM64 on a sleeping Mac mini woken via wake-on-LAN
- A GPU host from a GPU-only provider
- Bare-metal in a closet

…in the same logical pool, scoped by ISA and capability.

SaaS providers offer the runners they curate. ARM Mac for iOS builds is a separate plan tier; GPU is a
different vendor; on-prem hardware is "self-hosted runner" — which silently drops you out of half the
managed features.

### No DSL, No Marketplace Lock-In

A DAFt job is a bash script at `.daft/jobs/build` in the work repo. There is no YAML schema bound to a vendor,
no `actions/setup-X` ceremony, no marketplace dependency to audit for supply-chain risk.

Forking off a SaaS provider means rewriting the workflow YAML, re-validating every action you depended on, and
re-onboarding the team to the new dashboard. Forking off DAFt is `git remote set-url`.

### Filesystem-as-API Debuggability

Inspecting any DAFt state uses tools every developer already has muscle memory for:

- `ls .daft/queue/x86_64/` — what's pending
- `find .daft/active -mmin +60` — stale claims
- `git log -- .daft/compliance/` — every signed deployment in history
- `cat .daft/archive/2026-05-06/<job-id>/status.json` — exact outcome
- `du -sh .daft/workspace/` — log-buffer size

SaaS debugging is reading dashboard logs and filing support tickets when the dashboard tells you nothing useful.

### Offline-Friendly Operation

Approvals, ticket updates, repo registrations, and job submissions all happen as commits. They queue locally
and sync the next time `git push` succeeds. A developer on a flight can approve a deploy; the deploy executes
when the runner box reconnects.

SaaS is online-or-nothing.

### Compliance By Construction

Every DAFt job emits a signed compliance manifest into `.daft/compliance/` containing:

- The signed event that requested the work
- The runner identity (signed) that executed it
- Scrubbed logs
- An SBOM via `syft`

The chain of custody is a `git log` away — sufficient for SOC2 / ISO 27001 / supply-chain provenance evidence,
without proprietary dashboards or upsell tiers.

SaaS providers gate equivalent compliance reporting behind enterprise plans.

### No Vendor Lock-In

DAFt is FOSS bash. Worst case: copy `.daft/` and `scripts/` to any git host, point runners at the new remote,
keep going. There is no proprietary state, no managed-service migration project.

SaaS migration is a multi-week rewrite of YAML, secrets, integrations, and team onboarding for every move.

## Where DAFt Is At Feature Parity With SaaS

These are the features the segment actually uses day-to-day. After Groups 1–7 ship, DAFt covers them in full.

### Multi-Architecture Builds

Multi-ISA queues (`x86_64`, `arm64`, `riscv64`) with per-ISA runner pools. Equivalent to GH Actions matrix
runners and Buildkite agent tags.

### Container-Based Isolation

Isolation levels span `BARE` → Linux namespaces → Bubblewrap → Podman/OCI → Firecracker MicroVM. Equivalent to
the container/VM isolation modes of every modern CI provider.

### Matrix Builds and Fan-In

A matrix generator consumes a template (e.g. `versions: [18, 20, 22]`) and emits one concrete job per cell.
A fan-in coordinator gates a job until all prerequisites complete. Equivalent to GH Actions `strategy.matrix`
and CircleCI workflow fan-out / fan-in.

### Webhook Triggers

Push-triggered ingestion via VCS webhooks (in addition to the polling baseline). Equivalent latency to any
SaaS provider's webhook-driven build start.

### Approval Gates

Human-in-the-loop pipeline gate that pauses until a ticket is mutated to `approved`. Equivalent to GH Actions
environments-with-required-reviewers and CircleCI manual-approval jobs.

### Observability — RED Metrics, OTel, SLOs

Every service exposes Rate / Errors / Duration metrics scraped by Prometheus. OpenTelemetry tracing carries
real `trace_id` / `span_id` across coordinator → runner → release. SLO definitions and burn-rate alerts are
first-class. Equivalent to the observability story shipped by enterprise CI tiers.

### OCI Registry / Artifact Caching

Container images and binary artifacts are addressed in a content-addressed store (CAS) with metadata in git.
Local caching mirrors prevent repeated cloud pulls. Equivalent to GH Container Registry plus per-runner image
cache.

### ChatOps and Web UI

Slack/Teams bridge for command-driven deploys (`/deploy app-foo prod`). Web dashboard wraps `git log` and `ls`
into a browsable UI with retry buttons and live log tails. Equivalent to the ChatOps and dashboard UX of any
mainstream provider for the small-team segment.

### Live Log Tailing

`tail -f` semantics over an HTTP endpoint, sourced from `.daft/workspace/<job-id>.log`. Equivalent to the
real-time log streaming every SaaS provides.

### Dynamic Cloud Provisioning

The Shepherd allocates EC2, Hetzner Cloud, Fly.io machines, Firecracker microVMs, podman containers, or
wake-on-LAN'd bare-metal hosts on demand. Suicide timer and out-of-band Reaper guarantee no idle billing.
Equivalent to GH Actions hosted runners or CircleCI's auto-scaling fleet — without the warm-pool surcharge.

### Signed Identity / RBAC

Public-key registry under `.daft/authz/keys/`, per-user and per-runner keys, double-handshake authz on every
claim. Equivalent to the OIDC + RBAC story of GH Actions / GitLab CI Premium.

### Compliance Manifests + SBOM

Signed build manifests with SBOM via `syft`, license scan, and vulnerability scan results. Equivalent to the
compliance reporting bundles shipped by Harness / GitLab Ultimate.

## Part 2 — DAFt vs. Jenkins

Jenkins is the incumbent self-hosted FOSS option. The comparison is structurally different from SaaS: both
DAFt and Jenkins are FOSS, both are self-hosted, both store state on the filesystem. The wins for DAFt are
not about cost-vs-vendor — they are about operational simplicity and the cost of running and maintaining the
system itself.

## Where DAFt Is Structurally Better Than Jenkins

### No JVM

Jenkins requires a tuned Java runtime: heap sizing, GC monitoring, JVM upgrade choreography, and the
operational overhead of one of the largest runtimes in production software. DAFt requires bash and git.
Memory footprint is roughly an order of magnitude lower; the operational tax of the JVM does not exist.

### No Master SPOF

Jenkins is master-agent: a single master holds the queue, the configuration, the credentials, the build
history, and the plugin state. If the master dies or is corrupted, everything stops, and rebuilding it from
backup is a multi-hour project.

DAFt has no master. The central daft repo is a bare git repo — highly available by default, trivially
mirrored, and with no in-process state to corrupt. Coordinator and reaper are stateless loops that pull
state from the repo and push back.

### No Plugin Compatibility Hell

Jenkins's value comes from its 1800+ plugins, but plugin compatibility across Jenkins core upgrades is a
running sore. Plugin maintainers vary in quality and responsiveness; "upgrade Jenkins core" is rarely a
one-evening exercise.

DAFt has no plugin substrate to maintain. The system is bash scripts in `.daft/plugins/`, each independent,
each readable in five minutes.

### One Configuration Model, Not Three

Jenkins state is split across:

- The web UI clickops surface (mutates `$JENKINS_HOME/*.xml`)
- Jenkinsfile (Groovy DSL committed to repos)
- Job DSL plugin scripts
- Configuration as Code (JCasC) YAML

…all interacting in subtle ways, and the Configuration as Code coverage is incomplete after years of effort.

DAFt has one configuration model: files in `.daft/`, committed to git. There is no UI state to drift, no
Groovy to interpret, no JCasC plugin to debug.

### No Master-Upgrade Choreography

Upgrading Jenkins core means: stop the master, audit plugin compatibility against the new core, upgrade
plugins, upgrade core, restart, hope nothing broke, roll back if it did. For a busy team this is a
maintenance window event.

DAFt has no master to upgrade. Each runner pulls and rebases independently. Coordinator and reaper restart in
seconds. There is no compatibility matrix.

### Smaller Security Surface

Jenkins has a 15+ year history of high-severity CVEs: Pipeline DSL remote code execution, plugin script
injection, master takeover via crafted job configurations, deserialization vulnerabilities. The Pipeline
sandbox is itself a security boundary that has been bypassed multiple times.

DAFt has no DSL — there is no DSL-injection bug class. There is no sandbox to escape. The substrate (bash +
git) is well-understood and has decades of defensive practice. Job script execution is plain `bash`, so all
the standard hardening (`set -u`, `-e`, isolation levels) applies directly.

### No Config Drift Over Time

A Jenkins master that has run for years accumulates state in `$JENKINS_HOME` that nobody fully understands
any more: orphaned credentials, dead plugins, deprecated job configs, legacy build records. Restoring from
backup or rebuilding from a JCasC export rarely produces an exact replica.

DAFt's entire state is in git. `git clone` reproduces the system byte-for-byte. There is no drift to manage.

### No Idle Agent Tax

Jenkins agents are typically left warm — the master expects them to be available when a job arrives. The
operational burden of "scale agents to zero on idle" is real and non-trivial in Jenkins.

DAFt's Shepherd does this by default: a runner that is not currently executing, draining, or bootstrapping
should not exist. Cloud cost trends to zero between jobs.

### Onboarding Is `git clone`

Standing up Jenkins from scratch is: install Java, install Jenkins, run the setup wizard, configure
authentication, configure agents, install ~30 plugins, write a Jenkinsfile, debug the Groovy, debug the
plugin compatibility matrix.

Standing up DAFt is: clone the repo, run `make daft-init`, register a work repo, run `make daft-runner`. The
README's stated goal is *zero to first green build in 10 minutes* — and the substrate is small enough that
this is achievable.

### Job Definitions Are Bash, Not Groovy

A Jenkinsfile is Groovy with Pipeline DSL syntax sugar — readable by people who already know both. New hires
spend their first day learning the DSL.

A DAFt job is `.daft/jobs/build` in the work repo, in bash. Every developer in the team can read and modify
it. The lingua franca of CI is shell; DAFt commits to that.

### State Is Inspectable Without Plugins

To answer "what's the longest-running job?" or "what's stuck?" in Jenkins, you reach for the dashboard or a
custom API call. Without the right plugin, certain answers are not available at all.

In DAFt:

- `find .daft/active -mmin +60` — stale claims
- `du -sh .daft/workspace/` — log buffer size
- `git log -- .daft/compliance/` — every signed deployment in history

…using tools every operator already has.

## Where DAFt Is At Feature Parity With Jenkins

### Self-Hosted, FOSS

Both are owned end-to-end by the operator. No SaaS vendor in the path.

### Filesystem-Based State

Both store all state on the filesystem (`$JENKINS_HOME` vs. `.daft/`). No external database is required for
the substrate to function. DAFt's substrate is also git-versioned by default; Jenkins's is not.

### Distributed Builds Across Heterogeneous Hardware

Both support a master-or-coordinator dispatching to a heterogeneous runner pool that can include cloud,
bare-metal, and ARM hosts. DAFt's Shepherd plus on-demand provisioning matches Jenkins's agent-cloud plugin
ecosystem in capability.

### Multi-Architecture Support

Both support `x86_64`, `arm64`, and other ISAs via runner labels (Jenkins) or queue partitioning (DAFt).

### Webhook Triggers

Both ingest VCS webhooks for push-triggered builds.

### Matrix Builds and Fan-In

Both support matrix builds and downstream-job fan-in (Jenkins via the multibranch / matrix plugins; DAFt via
the matrix generator and fan-in coordinator).

### Approval Gates

Both support human-in-the-loop approval (Jenkins via the input step; DAFt via the ticket gate).

### Container-Based Isolation

Both support running jobs inside containers (Jenkins via the docker-pipeline plugin; DAFt via the
`CONTAINER` and `MICROVM` isolation levels).

### Multi-Runner Pool

Both support large pools of runners with capability-based scheduling.

### Compliance Reporting

Both can produce signed manifests, SBOMs, and audit trails sufficient for SOC2 / ISO 27001 evidence — DAFt
by construction (every state transition is a signed commit), Jenkins via the audit-trail plugin and signed
build artifacts.

### Live Log Tailing

Both support real-time log streaming during job execution.

### Plugin / Extension Model

Both have a plugin model. Jenkins's is mature and vast (1800+); DAFt's is intentionally narrow (bash scripts
in `.daft/plugins/`). Functional parity exists for the common cases the small-team segment uses.

## Summary

For the segment DAFt targets — self-hosted, small-team, no SaaS dependency, no Kubernetes, no JVM — DAFt
fully shipped is **better** than every paid offering on the dimensions that drive the choice (cost, audit
trail, hardware flexibility, lock-in) and **at parity** on the day-to-day features that matter at that scale.

Against **Jenkins** specifically, DAFt is **structurally better** on every operational dimension that costs
real money over time (no JVM, no master SPOF, no plugin compatibility, no config drift, smaller security
surface), and **at parity** on the substantive feature set the small-team segment actually uses.

The pitch is therefore not "DAFt does everything every other CI does, cheaper" — it is "for your segment,
DAFt wins on the axes you actually care about, and ties on the rest."
