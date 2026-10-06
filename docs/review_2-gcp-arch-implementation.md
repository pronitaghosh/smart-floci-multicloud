# Senior Engineer Review 2 — GCP Architecture and Implementation Docs

Scope: gcp-floci-architecture.md, gcp-floci-implementation-plan.md, gcp-floci-execution-plan.md (renamed from gcp-floci-block-implementation.md), review-gcp-arch-implementation.md, aws-resources.md section 1, plus layout skim of terragrunt/aws, terraform/modules, scripts, k8s, Makefile and docker-compose.yml.

## 1. Prior review findings verdict

C1 Provider coverage assumed: addressed in design. Block 0 requires a per-service probe with supported, degraded or unsupported matrix, LRO and read-back checks, and the table frozen on evidence.

C2 False precision: partial. Table marked provisional with gates on contract outputs plus round-trips. Residual: block-guide Block 3 acceptance still demands exact counts of 22 plus 8, and the plan header still leads with 60 resources across 31 types as a target.

C3 Load balancer copies AWS: addressed in design. Load balancer Terraform demoted to Block 8, primary access is NodePort plus host probe with in-network fallback. Residual: architecture section 6 still presents registration as standard-scope work, not stretch-conditional.

C4 GKE access hand-waved: partial. Block 0 gates the credential flow and kubeconfig shape before Block 5. The override mechanism is still unstated, since gcloud has no endpoint flag for get-credentials, and CA and token handling are unproven.

C5 App portability and Redis: partial. Block 0 requires a per-service data dependency record and Block 4 follows it. No v1 fallback is committed if a Redis client is found, and no app-port block is defined.

M6 State persistence: addressed. Memory for verification, hybrid for interactive dev only, one reset command, mode recorded per gate.

M7 SQL ports and addresses: addressed in design. Decided and recorded in Block 1 rather than Block 4.

M8 Workload identity: addressed in design, open in proof. Explicit pod access mechanism required, but no default chosen.

M9 Compat flag sprawl: addressed in design. Block 2 outputs an enumerated gate list by file and field.

M10 BigQuery and Run job on critical path: addressed in design. Both moved to Block 8. Residual staleness covered below.

P11 Commit, journal, ports, namespace, registry: partial. Explicit per-block commit confirmation, journal path with field list, no GCP bind on 80 and 443, single GCP namespace rule are fixed. Open: Artifact Registry login flow still unconfirmed, with no k3s-side registry config step.

## 2. New critical issues

N1. Architecture contradicts plan on core scope. Architecture stateful lists BigQuery datasets and tables, standard lists Cloud Run service and job plus load balancer pieces, verification requires BigQuery and Cloud Run round-trips as core. Plan and block guide defer all three to Block 8. Recommendation: strip those items from architecture sections 4, 7 and 9 or mark stretch-only until fixed.

N2. Resource table arithmetic error. Standard column lists cluster, node pool, Run service, 2 Helm releases, 2 namespaces and 2 null resources, which sums to 9, but the core total shows 8. Core total 52 and grand total 60 inherit the error. Recommendation: correct the row or the total before freezing, and add a generator check like the AWS resource script that refuses on mismatch.

N3. Stretch placement undefined. Plan says four stacks plus one optional stretch block, while the block guide allows editing signed-off core composites. Recommendation: freeze stretch as a separate fifth stack with its own state path and forbid core composite edits in Block 8.

N4. Secret count unexplained: 3 secrets versus 2 versions. Recommendation: the Block 0 dependency record must map each secret and version to a consumer, or correct the table.

N5. KMS key double count unjustified: one key in bootstrap plus one in stateful with no stated reason. Recommendation: default to one key unless Block 0 proves a per-stack requirement.

N6. Registry pull path incomplete. Five Artifact Registry repos assume host docker login suffices, but pulls happen from k3s inside floci-gcp, which needs its own registry mirror or TLS config. Recommendation: Block 0 or 6 must prove a k3s pull from the emulated registry and document the k3s registry config.

N7. MySQL scope leak. Architecture states Cloud SQL Postgres and MySQL support, but the table and blocks provision Postgres only. Recommendation: delete the MySQL mention or record an explicit non-goal.

## 3. Internal consistency

Block, phase and mermaid numbering are consistent across Blocks 0 to 8. Type count of 31 recounts correctly. Standard column arithmetic fails as noted, and Block 3 exact-count acceptance contradicts the provisional-counts rule. Block 8 scope matches between plan table and block text, but placement is inconsistent. The AWS table is observed inventory with a fidelity legend and generator enforcement; the GCP table is provisional with neither, acceptable pre-Block 0 only.

## 4. Feasibility risks, ordered

1. Google provider REST-only gap on GKE, SQL, Run and compute load balancer, with no defined fallback.
2. GKE credential and kubeconfig override unproven, blocking the cold-start sequence and all Kubernetes and Helm providers.
3. App data dependency mismatch on Redis, with no app-port effort scoped.
4. Artifact Registry to k3s pulls plus Cloud SQL host proxy ports, two Docker-networking unknowns bundled into Blocks 1 and 6.
5. Stale-state false greens under hybrid persistence without enforced memory-mode plus reset discipline.

The parallel-tree pattern in the repo makes additive GCP trees plausible with no shared-file edits. The compose change is append-only, but the unpinned image tag and socket, volume and hostname wiring are unproven.

## 5. Go and no-go

No-go for Block 1 onward, conditional go for Block 0 only. Conditions: agree the plan table plus Block 8 deferral govern over the stale architecture sections; fix the standard column total, secret counts and KMS double key before freezing; decide stretch as a separate fifth stack; require Block 0 exit criteria of versioned endpoint verdicts per service, credential and kubeconfig proof with the exact override, SQL addresses plus published range, Artifact Registry pull proof from k3s, per-service dependency record with Redis verdict, and recorded storage mode plus reset command.
