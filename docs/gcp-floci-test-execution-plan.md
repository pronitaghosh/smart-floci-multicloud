# GCP Test Execution Guide (floci-gcp QA)

Companion to the GCP test plan and the GCP test dev plan. One section per QA phase. Each section lists what to create, what to read as a template without modifying, and which checks and emulator details to verify. Single QA Agent executes in order inside `.worktree/gcp-qa` with a User verification gate, journal update and commit only on explicit User commit confirmation after each phase.

Journal: append-only at docs/gcp-tests-journal.md. Each entry records date-time UTC, agent name, model ID, block and phase, work summary, final status, files changed, new files, token usage as input plus output plus total counts, and User sign-off status.

Global read-only rule: the AWS terragrunt tree, AWS terraform modules, impl terraform modules, impl terragrunt stacks, impl compose service, impl state, impl outputs files, and impl make targets are templates and subjects only. All QA work is additive under tests/gcp plus helper-pg probes.

Doc authority: the QA Agent refers to the floci-gcp documentation at https://floci.io/floci-gcp/services/ for emulator behavior during execution. If required information is not found in the first attempt, the QA Agent consults the User before proceeding.

New-tree paths used below: tests/gcp tree with shared client plus endpoint, status, round-trip, drift, reconcile, and stretch test files; helper-pg probe scripts; QA journal and plan docs.

## QA-0: spike coverage

Objective: every Block 0 matrix service has a probe before building further checks.

| Item | Detail |
|---|---|
| Create | Endpoint rows for each supported service in the endpoint table; degraded notes as comments |
| Read as template | Block 0 capability matrix for verdicts; vendor service docs for list paths |
| Touch | Endpoint test file only; no status tests yet |
| Resources to look for | List path per service; version suffix per path; count key per payload |
| Steps | Add one row per matrix service; run endpoint class; record degraded paths that 404 |
| Acceptance and gate | All supported services probed; degraded recorded; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## QA-1: runtime

Objective: emulator reachable with AWS untouched.

| Item | Detail |
|---|---|
| Create | Identity test; sidecar presence checks |
| Read as template | Block 1 compose service for port, label, and storage-mode conventions |
| Touch | New runtime assertions inside status tests only |
| Resources to look for | Info endpoint reachability from host; emulator plus sidecar containers; AWS endpoint still serving AWS only |
| Steps | Assert info 200 with version; assert emulator and sidecar names in docker output; record storage mode at the gate |
| Acceptance and gate | Info plus docker checks green; AWS diff empty; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## QA-2: config and provider

Objective: both endpoint modes render with no secret on disk.

| Item | Detail |
|---|---|
| Create | Dual-mode render checks; no-secret-on-disk assertion |
| Read as template | Block 2 env config for get_env pattern; root config for merged substitution; provider template for local versus real branching |
| Touch | New config assertions only; nothing shared |
| Resources to look for | Rendered local endpoints with version suffixes; plain provider on empty endpoint; no credential tracked by git |
| Steps | Render both modes; assert suffixes present locally and absent really; assert secret files untracked; run init and validate per stub stack |
| Acceptance and gate | Both modes render correctly; no secret on disk; init and validate pass; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## QA-3: bootstrap plus IAM

Objective: foundation state matches live emulator.

| Item | Detail |
|---|---|
| Create | State-type table per stack; bootstrap and IAM endpoint minimums |
| Read as template | Block 3 composites for contract outputs; config for expected counts |
| Touch | Status test file and endpoint table only |
| Resources to look for | Bucket 1; key ring plus key; network 1; subnets 2; firewalls 3; project services 8; service accounts 3; bindings 5 |
| Steps | Assert expected types per stack state; assert live counts meet minimums; fail on missing stack output |
| Acceptance and gate | Contract outputs present; live counts match state; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## QA-4: stateful

Objective: data plane live with round-trips per consumer.

| Item | Detail |
|---|---|
| Create | Secrets, topics, subscriptions, SQL endpoint tests; round-trip tests per service |
| Read as template | Block 0 dependency record for consumer wiring; Block 4 patterns for assembled outputs |
| Touch | New endpoint rows plus round-trip test file only |
| Resources to look for | Secrets 2; topics 2 plus subscriptions 2; SQL instance RUNNABLE plus database plus user; KMS key for encrypt and decrypt |
| Steps | Assert counts; publish and pull a message; read a secret; run a live SQL query; encrypt and decrypt via KMS; confirm every consumer wired |
| Acceptance and gate | API round-trips pass; no consumer left unwired; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## QA-5: standard

Objective: platform reachable with stable re-plan.

| Item | Detail |
|---|---|
| Create | Cluster and Run endpoint tests; k3s sidecar check; re-plan stability note |
| Read as template | Block 5 patterns for Docker-backed execution; standard outputs for names and URLs |
| Touch | New endpoint rows plus platform assertions only |
| Resources to look for | Cluster 1 plus node pool 1 RUNNING via container API; Run service 1 listed; ArgoCD healthy; gateway and frontend URL outputs |
| Steps | Assert cluster plus pool plus service listed; assert k3s sidecar present; confirm re-plan shows no changes; confirm ArgoCD health |
| Acceptance and gate | Platform checks green; re-plan stable; ArgoCD healthy; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## QA-6: workloads and scripts

Objective: four services on GKE with reachable gateway.

| Item | Detail |
|---|---|
| Create | Workload test class: overlay manifests, namespace, ready pods, gateway probe, ArgoCD sync, leak guard |
| Read as template | Base k8s manifests for service shapes; overlay for image addresses; deploy script for namespace and restart flow |
| Touch | Workload tests only; base manifests read-only |
| Resources to look for | Overlay manifests for gateway, user, order, payment; namespace smartcloud in cluster; ready pods per service; gateway 200 via port-forward URL; ArgoCD app Synced; rendered config untracked |
| Steps | Assert overlay files present; assert namespace exists; assert pods ready (completed jobs exempt); probe gateway via GATEWAY_URL; assert ArgoCD sync plus health; assert rendered config untracked |
| Acceptance and gate | Full pytest green except QA-8; namespace consistent; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## QA-7: verification and docs

Objective: round-trip proof of the core path plus reconciled inventory with AWS regression intact. Stretch scope is verified in QA-8.

| Item | Detail |
|---|---|
| Create | Round-trip suite per core service; drift plus freshness plus reconcile tests |
| Read as template | AWS verify script for inventory, freshness, round-trips, orphan drift, and slow-plan conventions; implementation resource table as planned baseline |
| Touch | New round-trip, drift, and reconcile test files; plan docs updated for confirmed values only |
| Resources to look for | State files under the main state subtree; live resources for drift comparison; round-trip targets for GCS, Secret Manager, PubSub, SQL, KMS, service accounts, network, GKE, and Run service; AWS verify outcome for regression |
| Steps | Precheck emulator plus network; inventory from state; run each core round-trip; assert zero live-but-unmanaged resources; run AWS verification; reconcile planned versus observed counts; record confirmed divergences |
| Acceptance and gate | All core round-trips pass; AWS verify still passes; table matches observed state; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## QA-8: optional stretch (separate scope flag)

Objective: deferred scope without blocking the app path and without touching signed-off core. Attempted only after QA-7 sign-off.

| Item | Detail |
|---|---|
| Create | Backend host-path tests; BigQuery subset tests; Run job test; all behind explicit scope flag |
| Read as template | Block 0 coverage verdict; Block 4 patterns for assembled outputs; Block 5 patterns for Docker-backed execution; vendor notes on the SQL subset |
| Touch | New stretch test files only; core tests read-only |
| Resources to look for | Backend service 1, URL map 1, target HTTP proxy 1, and global forwarding rule 1 only if Block 0 proved coverage; BigQuery dataset 1 plus tables 2 on the subset; Run job 1 Docker-backed |
| Steps | Register backend and verify gateway from host without port-forward; insert plus query tables; execute job; record coverage, dialect limits, and execution behavior |
| Acceptance and gate | Stretch round-trips pass or limits documented; core gates unaffected; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

Thought: goal executable QA companion, why same section shape, next implement QA-7 with Block 7.
