# GCP Architecture and Plan Review

Role: senior/staff architect. Scope: GCP architecture doc, implementation plan, block guide. Verdict: direction sound, execution order wrong on five points. Fix the five before Block 3.

## Critical 1: Terraform provider coverage is assumed, not proven

Plan builds seven blocks on the premise that the google provider can create GKE, Cloud SQL, Cloud Run and load balancer resources against floci-gcp. Vendor docs state only REST-exposed services are reachable via custom endpoints and call out GCS, IAM and Secret Manager. GKE, SQL, Run and compute forwarding rules are unproven through Terraform.

Recommendation: add a Block 0 provider spike. One minimal resource per service, applied and read back, recorded as supported, degraded or unsupported. Freeze the resource table only after the spike. Do not let Block 3 acceptance depend on exact counts before this.

## Critical 2: resource table has false precision

60 resources across 31 types is presented as a target and wired into acceptance (apply matches mapped counts). The AWS table was observed. This one is invented. Emulators create implicit resources, refuse others, and rename fields. Strict count acceptance will fail for the wrong reasons.

Recommendation: mark the table provisional in the doc. Acceptance per block is contract outputs plus round-trips, not totals. Reconcile counts in Block 7 only.

## Critical 3: load balancer design copies AWS without evidence

AWS needed NodePort plus registration because the ALB container lacks a pod-CIDR route. The plan assumes the same for the GCP external HTTP load balancer, but there is no evidence floci-gcp emulates backend service, URL map, proxy or forwarding rule resources at all.

Recommendation: demote the load balancer to stretch. Primary local access is NodePort plus host probe with in-network fallback, and direct Cloud Run invocation where applicable. Build the compute load balancer modules only if the Block 0 spike proves coverage.

## Critical 4: GKE access flow is hand-waved

AWS uses update-kubeconfig with an explicit endpoint-url flag. gcloud has no equivalent flag. The plan says get-credentials against the emulator endpoint without stating the override mechanism, and the kubeconfig context shape is listed as unknown while Block 5 depends on it.

Recommendation: spike credential acquisition first: endpoint override method, context name, cluster CA handling, and the dummy-context hook equivalent. Block 5 cannot start without this recorded.

## Critical 5: app portability contradiction

Block 6 reuses the same four images unchanged. Block 4 replaces Redis with Firestore plus PubSub. If the services read Redis, identical images cannot run on the new stateful layer without code changes. The docs never state the current data dependencies of gateway, user, order and payment services.

Recommendation: record per-service data dependencies before Block 4. Either scope stateful to Postgres-only for v1 with PubSub and Firestore as parallel new paths, or add an explicit app-port block. Do not apply stateful with an unresolved consumer.

## Major 6: state persistence changes test semantics

AWS is ephemeral, so every run starts clean. GCP hybrid mode persists across restarts. Gates that pass on stale state give false confidence, and drift checks behave differently.

Recommendation: default to memory mode for verification runs, hybrid for interactive dev only, and document one reset command. Each block gate states the storage mode used.

## Major 7: Cloud SQL ports and addresses undecided

AWS publishes a proxy port range for host-side database access. The GCP docs list the equivalent as unknown while Block 4 acceptance requires a live SQL query. Host versus in-cluster addresses for SQL are also unspecified.

Recommendation: decide the published range and the two addresses in Block 1, not Block 4.

## Major 8: IAM mapping misses workload identity

Three AWS roles map to three GCP service accounts, but pod access to Secret Manager and GCS needs the Kubernetes service account binding story. It is absent from Blocks 3 and 6.

Recommendation: specify the binding mechanism or explicitly document that local pods use the emulator bypass with no binding. Do not leave it implicit.

## Major 9: compat flag scope is unbounded

AWS honors its flag in exactly three places. The GCP flag is described as gating deviations everywhere, which invites sprawl and production drift.

Recommendation: enumerate the gated deviations by file and field, mirroring the AWS three-place discipline. Any new gate requires updating the list.

## Major 10: BigQuery and Cloud Run job inflate the critical path

The app path needs Postgres, secrets, registry, cluster and backend. BigQuery tables and the Cloud Run job are full-scope additions with DuckDB dialect risk, yet sit in stateful and standard acceptance.

Recommendation: move BigQuery and the Cloud Run job to an optional Block 8. Keep standard acceptance to cluster, backend access, ArgoCD and URL outputs.

## Process 11: commit, journal and port conflicts

Per-block auto-commit conflicts with the repo no-commit-without-confirm rule; gate on explicit user commit confirmation each time. Journal location, entry format and token units are unspecified; fix the path and fields before Block 1. Ports 80 and 443 are already bound by the AWS ALB emulation; the GCP load balancer cannot reuse them, so state the GCP access port explicitly. The AWS tree already shows a namespace inconsistency between manifests and restart targets; the GCP overlay must declare one namespace and use it everywhere. Artifact Registry docker login flow is unspecified; ECR get-login-password does not transfer.

## Suggested block order fix

Block 0 spike: provider capability matrix, GKE credential flow, SQL ports and addresses, load balancer coverage, per-service data dependencies. Then Blocks 1 through 7 as written, with BigQuery and Run job moved to optional, counts treated as provisional, and each gate requiring user verification plus explicit commit confirmation plus journal update.
