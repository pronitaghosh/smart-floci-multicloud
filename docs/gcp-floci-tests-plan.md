# GCP Tests Plan (floci-gcp)

Status: plan for this implementation. No app-code testing; emulator,
infrastructure state, and workloads only.

## Layers

1. Stack lifecycle (`helper-pg/verify-tf-stack.sh <stack-dir> full`):
init, validate, plan to reviewed `.<stack>.tfplan`. Apply uses the
reviewed file only, then deletes it. Plan files hold secrets: never commit.
2. Emulator endpoints (`tests/gcp/test_emulator_endpoints.py`): info plus
16 list endpoints across bootstrap, IAM, stateful, standard, stretch.
Each asserts HTTP 200, JSON shape, minimum item count.
3. Project status (`tests/gcp/test_project_status.py`): state files per
stack with expected resource types; docker sidecars; Block 6 workloads
(overlay manifests, namespace, ready pods, gateway, ArgoCD sync,
rendered-config leak guard).
4. Ad-hoc probes (`helper-pg/verify_endpoints.py`,
`helper-pg/verify_status.py`): human-readable GET checks, same coverage
as layers 2-3. Keep in sync when adding endpoints.

## Tooling

- Runner: `floci-pyenv/bin/python -m pytest tests/gcp -q`.
- Deps: `tests/requirements.txt` (`pytest==9.1.1`, in `floci-pyenv`).
- Stdlib only in test code (`urllib`, `unittest`, `subprocess`).
- Shared client: `tests/gcp/common.py`; `conftest.py` fixes imports.
- Env overrides: `FLOCI_GCP_BASE`, `FLOCI_GCP_PROJECT`, `STATE_ROOT`,
`OVERLAY_DIR`, `NAMESPACE`, `GATEWAY_URL`.
- Emulator down: endpoint/workload tests skip; state/file tests still run.

## Test architecture

Layout (all under `tests/gcp/`, stdlib only):

- `common.py`: `get`/`get_json` (base URL + `{project}` substitution),
`count_list` (first present list key, 0 when none), `emulator_up`
probe. Reused by every test file; extend here, not per file.
- `conftest.py`: inserts test dir into `sys.path` for any cwd.
- `test_emulator_endpoints.py`: `ENDPOINTS` table (name to path +
minimum) looped in one `test_all_endpoints` via `subTest`;
`TestInfo` asserts emulator identity. Add coverage by adding a table
row, never a new function.
- `test_project_status.py`: `EXPECTED_TYPES` table looped per stack
(`TestStateFiles`); `TestDocker` greps `docker ps` for sidecar name
fragments; `TestWorkloads` (Block 6) one method per acceptance item
using `kubectl()` JSON helper and `GATEWAY_URL` probe.

Organization rules: data tables over code (new endpoint = new row);
one class per area (endpoints, state, docker, workloads, later
round-trips, drift, stretch); `subTest` names the failing item;
module-level `skipUnless(emulator_up())` keeps file tests runnable
offline; env overrides keep worktree/main interchangeable.

Reuse and refactor targets:

- Reuse now: `common.get_json`, `count_list`, `kubectl()`,
`load_state()`, env-override pattern.
- Refactor next: move `kubectl()` + `load_state()` into `common.py`;
split `TestWorkloads` per service when Block 6 grows; extract
round-trip helpers (GCS put/get, publish/pull, SQL query) for QA-7
instead of copying probe code; share `ENDPOINTS` table between tests
and `helper-pg` via generated import or single source.

Coverage map (test to implementation):

- `TestInfo` + info endpoint: Block 1 runtime reachability.
- buckets/keyrings/networks/subnets/firewalls/services: Block 3
bootstrap modules and provider wiring.
- serviceaccounts: Block 3 IAM bindings.
- secrets/topics/subscriptions/sql: Block 4 stateful data plane.
- clusters/run (+node pool in payload): Block 5 standard platform.
- `TestStateFiles`: per-stack `EXPECTED_TYPES` mirror Block 2-5
composites; fails on missing stack output.
- `TestDocker`: Block 1 sidecar spawn + Block 5 k3s/Run/SQL containers.
- `TestWorkloads`: Block 6 overlay, pods, gateway, ArgoCD, leak guard.
- datasets/bucket_objects: empty today; QA-8 tables + Block 6 sync fill
them (minimums 0 are placeholders, raise on evidence).

## Block mapping

- Block 3: bootstrap/IAM endpoints + state types + serviceaccounts.
- Block 4: secrets, topics, subscriptions, sql instance + user/db.
- Block 5: clusters, run services, node pool in cluster payload.
- Block 6: workloads class (fails until deploy); bucket objects after
frontend sync.
- Block 8: datasets/table checks extend here; LB endpoints if proven.

## Adding an endpoint

1. Add path + minimum to `test_emulator_endpoints.py` and
`helper-pg/verify_endpoints.py`.
2. Add to `verify_status.py` `LIVE_ENDPOINTS` with count key.
3. Run pytest; update minimums only from observed plan-apply evidence.

## Parallel QA plan (per implementation block)

Each QA phase runs alongside its implementation block and gates the
same user checkpoint. QA never applies; it reads state, emulator, and
cluster only.

- QA-0 (provider spike): record per-service verdicts in matrix;
re-run `pytest tests/gcp -q` endpoint class after each probe batch.
Gate: matrix matches observed emulator behavior.
- QA-1 (runtime): emulator info reachable; AWS endpoint unaffected;
sidecar spawn/delete clean; storage mode recorded. Gate: script
`verify_status.py` emulator ok, AWS diff empty.
- QA-2 (config/provider): both modes render (local vs empty endpoint);
no secret on disk; `init` + `validate` pass per stub stack.
Gate: `verify-tf-stack.sh <stack> full` clean, no plan file committed.
- QA-3 (bootstrap/IAM): state types present; live buckets, keyrings,
networks, subnets, firewalls, services, serviceaccounts counts > 0.
Gate: endpoint tests for Block 3 names green.
- QA-4 (stateful): secrets, topics, subscriptions counts match config;
SQL instance RUNNABLE + query round-trip; KMS encrypt/decrypt.
Gate: Block 4 endpoint tests green; round-trips logged.
- QA-5 (standard): cluster + node pool RUNNING; Run service listed;
ArgoCD healthy; re-plan stable. Gate: clusters/run endpoint tests
green; `TestDocker` k3s sidecar present.
- QA-6 (workloads): `TestWorkloads` green (overlay, pods ready,
gateway 200 via port-forward/in-network fallback, ArgoCD Synced, leak
guard); bucket objects after sync; namespace consistent. Backend
node+port registration is Block 8 scope, not QA-6. Gateway check runs
against a port-forward URL via `GATEWAY_URL` (default stays direct
NodePort as negative control). Gate: full pytest green except QA-8.
- QA-7 (verification and docs): mirrors Block 7 round-trip proof plus
reconciled inventory with AWS regression intact.
  - Precheck: emulator info plus network existence; AWS endpoint
  unaffected (existing AWS verify outcome recorded for regression).
  - Inventory from state: every resource in `.state/dev/gcp/*` has a
  live counterpart; new drift test asserts zero live-but-unmanaged
  resources (orphan check).
  - Core round-trips, one test each: GCS object put/get, Secret Manager
  access, PubSub publish/pull, SQL live query, KMS encrypt/decrypt,
  service-account token use, GKE node reachability, Run service invoke,
  gateway host path. Firestore via SDK path only (Terraform 404 known).
  - Reconcile: planned-vs-observed counts per implementation-plan
  resource table; new test asserts table file matches observed counts,
  deltas carry reasons.
  - Freshness: state mtime newer than last apply; slow-plan flag when
  plan exceeds threshold.
  - Gate: full pytest green, AWS verify still passes, table reconciled,
  divergences recorded in architecture doc.

- QA-8 (stretch, separate fifth stack): mirrors Block 8 deferred scope,
attempted only after QA-7 sign-off; core stacks read-only.
  - Backend node+port registration with host-path gateway verification
  (moved from QA-6): backend service, URL map, target HTTP proxy,
  global forwarding rule, each counted live; gateway 200 from host
  without port-forward.
  - BigQuery: dataset 1 plus tables 2; insert plus query on DuckDB
  subset; dialect limits recorded as known-failure cases, not errors.
  - Cloud Run job: Docker-backed execution completes; execution
  behavior recorded.
  - Isolation: stretch tests in own class/files behind explicit scope
  flag; core suite green with flag off and on.
  - Gate: stretch round-trips pass or limits documented; core gates
  unaffected.

## Acceptance

- `pytest tests/gcp -q`: green except documented pending scope.
- New Block 6 failures must name the missing resource, not just status.
- Journal + commit only on explicit user confirmation.

## Coverage audit 2026-10-09 (Blocks 0-6)

Worktree run: 7 passed + 32 subtests, 3 failed
(`argocd_synced`, `gateway_reachable`, `overlay_manifests`).

- Block 0: matrix recorded, no automated cross-check. Manual.
- Block 1: compose/ports/storage mode, no test asserts. Manual
(`verify_status.py` emulator reachability only).
- Block 2: dual-mode render, no secret on disk, init/validate. Manual
(`verify-tf-stack.sh full` per stack).
- Block 3: covered, green (endpoints + state types).
- Block 4: endpoints green; publish/pull, SQL query, KMS round-trips
manual, unlogged. Gap: automate or log.
- Block 5: endpoints green; re-plan stability + ArgoCD health manual. Gap.
- Block 6: incomplete. Overlay manifests uncommitted in main; worktree
overlay stale ns-only. Run worktree suite with
`OVERLAY_DIR=<main>/k8s/gcp` plus `STATE_ROOT=<main>/.state/dev/gcp`
until manifests merge. Gateway via `GATEWAY_URL` port-forward URL;
direct NodePort is negative control. ArgoCD sync blocked on unpushed
`gcp` revision.

Thought: goal durable test contract, why layers mirror blocks, next extend for Block 8.
