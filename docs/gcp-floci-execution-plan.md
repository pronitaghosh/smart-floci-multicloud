# GCP Block Implementation Guide (floci-gcp)

Companion to the GCP architecture doc and the GCP implementation plan. One section per block. Each section lists what to create, what to read as a template without modifying, and which resources and emulator details to verify. Single Agent executes in order with a User verification gate, journal update and commit only on explicit User commit confirmation after each block.

Journal: append-only at docs/gcp-journal.md. Each entry records date-time UTC, agent name, model ID, block and phase, work summary, final status, files changed, new files, token usage as input plus output plus total counts, and User sign-off status.

Global read-only rule: the AWS terragrunt tree, AWS terraform modules, the AWS compose service, AWS state, the AWS outputs file and AWS make targets are templates only. All GCP work is additive under new paths.

Doc authority: the Agent refers to the floci-gcp documentation for emulator behavior during implementation. If required information is not found in the first attempt, the Agent consults the User before proceeding.

New-tree paths used below: compose file gains a GCP service; terragrunt gcp tree with env, root, provider template and four stack dirs; terraform modules-gcp tree with leaf modules plus four composites; scripts gcp dir; k8s GCP overlay dir; GCP outputs JSON; GCP verification script; GCP makefile; GCP data volume dir.

## Block 0: provider spike

Objective: prove what the google provider can drive against the emulator before building modules, and record what the four services actually consume.

| Item | Detail |
|---|---|
| Create | Minimal probe configs with one resource per service for GCS, Secret Manager, IAM, KMS, PubSub, Firestore, Cloud SQL, GKE, Cloud Run, BigQuery and compute load balancer; capability matrix doc; per-service app data dependency record |
| Read as template | Vendor custom endpoint notes with version suffix rule; AWS gaps doc for divergence entry shape |
| Touch | Probe dir and matrix doc only; no stack modules yet |
| Resources to look for | Versioned endpoint per service; LRO completion behavior; fields that read back unset; GKE credential and kubeconfig shape; SQL host-side ports and addresses; load balancer API coverage verdict; k3s pull proof from the emulated registry including any mirror or TLS config; per-service data clients for Postgres, Redis, Firestore, PubSub and secrets |
| Steps | Apply one minimal resource per service and read it back; record supported, degraded or unsupported; prove the credential flow end to end; prove a k3s pull from the emulated registry; read the four services for data dependencies; freeze the resource table on evidence |
| Acceptance and gate | Matrix recorded; credential flow proven; dependency record complete; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## Block 1: emulator runtime

Objective: GCP API served on its own port with AWS untouched.

| Item | Detail |
|---|---|
| Create | Compose service for floci-gcp; GCP data volume dir; GCP-scoped start and clean commands in the GCP makefile |
| Read as template | Root compose file AWS service for port, volume, network and label conventions; AWS docker clean target for label-filter pattern |
| Touch | Root compose file by appending one service plus one volume only; nothing existing modified |
| Resources to look for | Emulator reachability from host on the GCP port; sidecar spawn for Cloud SQL, GKE and Cloud Run via the socket mount; hostname and base URL reflected in generated URLs; AWS port still serving AWS only; GCP does not bind host ports 80 and 443 |
| Steps | Add service; start only the GCP service; probe host reachability; list sidecar labels for GCP; stop and restart and confirm persistence behavior per mode; confirm AWS endpoint unaffected; publish Cloud SQL on a new nearby host port range that avoids the AWS proxy range, and record it; set the storage mode rule of memory for verification runs and hybrid for interactive dev only plus one reset command, and record the mode at every gate |
| Acceptance and gate | Host probe passes; sidecars spawnable; AWS diff empty; ports and SQL range recorded; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## Block 2: config and provider

Objective: single YAML input plus generated google provider with local versus real behavior.

| Item | Detail |
|---|---|
| Create | Terragrunt gcp env config; env defaults file; root config; google provider template; enumerated compat gate list by file and field; per-stack leaf config stubs for the four stacks |
| Read as template | AWS env config for global plus per-stack schema shape; AWS env defaults for get_env pattern and secret substitution; AWS root for merged config, local state path, generated provider and single string input; AWS provider template for local versus real branching; AWS leaf config for include, composite-by-dirname, module source switch, mock outputs and resolved merge |
| Touch | Nothing shared; all files are new under the gcp tree |
| Resources to look for | Global fields for project, location, endpoint URLs, compat flag and labels; per-service custom endpoints with API version suffixes; fake token for local auth; empty endpoint producing a plain provider; local state under a gcp state subtree; password and endpoint substitution with no credential on disk; every local workaround present in the gate list |
| Steps | Mirror schema with GCP names; wire versioned custom endpoints for REST services; keep real-GCP path clean; write the enumerated gate list with each workaround mapped to file and field; validate empty versus local endpoint rendering; init and validate each stub stack |
| Acceptance and gate | Both modes render correctly; no secret on disk; init and validate pass; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## Block 3: bootstrap plus IAM

Objective: foundation network, keys, registries, bucket, service enables, identities.

| Item | Detail |
|---|---|
| Create | Leaf modules for GCP network, KMS, Artifact Registry, GCS bucket and project services; composites for bootstrap and IAM; leaf stack configs for bootstrap and IAM |
| Read as template | AWS networking module for for_each map pattern and tagging merged with global tags; AWS KMS module for key plus alias shape; AWS ECR module for five repos and URL outputs; AWS S3 module for bucket plus policy and versioning; AWS IAM role module for roles, policies and attachments; AWS composite bootstrap locals for name-to-ARN resolution from resolved; AWS composite IAM structure; AWS bootstrap and IAM leaf configs for mock outputs |
| Touch | New modules-gcp tree and gcp leaf stacks only |
| Resources to look for | Compute network 1; subnetworks 2; firewall rules 3 as shape-only; KMS key ring 1 plus crypto key 1; Artifact Registry Docker repos 5 with URL outputs; storage bucket 1 for frontend; project services 8 for compute, container, SQL, Run, Secret Manager, KMS, PubSub and BigQuery; service accounts 3; project IAM members 5; explicit pod access mechanism for Secret Manager and GCS as account binding or documented emulator bypass; labels in place of tags; Service Usage backing for project service resources |
| Steps | Build leaf modules first with map inputs; wire composites with resolved lookups; specify the pod access mechanism or document the bypass; add mock outputs for downstream plan; plan clean pre-apply; apply bootstrap then IAM; record actual IDs for the handoff contract |
| Acceptance and gate | Apply matches the planned counts of 22 plus 8; pod access explicit; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## Block 4: stateful

Objective: database, messaging and secrets on handed-off foundation outputs, scoped by the Block 0 dependency record. If Block 0 finds a Redis client, Block 0 proposes the v1 fallback for User decision before Block 4 starts. BigQuery is deferred to Block 8.

| Item | Detail |
|---|---|
| Create | Leaf modules for Cloud SQL, Firestore, PubSub and Secret Manager; stateful composite; stateful leaf stack config |
| Read as template | AWS RDS module for instance, subnet group, endpoint outputs and compat nulling of non-round-tripped fields; AWS ElastiCache module for ignore-changes pattern on emulator-owned fields; AWS Secrets Manager module for assembled values from own outputs; AWS stateful composite locals for secret assembly; AWS stateful leaf config for dependency plus resolved merge |
| Touch | New stateful module set, composite and leaf stack only |
| Resources to look for | SQL instance 1 plus database 1 plus user 1 with Docker-backed data plane; Firestore database 1; PubSub topics 2 plus subscriptions 2; Secret Manager secrets 3 plus versions 2 with app credentials assembled from SQL endpoint; KMS crypto key 1 for secret encryption; compat flag nulling for SQL fields the emulator does not round-trip, each listed in the Block 2 gate list; no Memorystore and no Redis port |
| Steps | Confirm scope against the Block 0 dependency record so no consumer is left unwired; consume network and KMS outputs via resolved only, never direct remote state; assemble secret values in composite locals; apply; run API-level round-trips for SQL query, publish and pull, secret access, KMS encrypt and decrypt |
| Acceptance and gate | Secrets complete; live SQL query passes; messaging round-trips pass; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## Block 5: standard

Objective: cluster, Cloud Run service and platform releases with cold-start handling. The Cloud Run job and compute load balancer Terraform are deferred to Block 8; primary local access is NodePort plus probe.

| Item | Detail |
|---|---|
| Create | Leaf modules for GKE, Cloud Run service and ArgoCD; standard composite; standard leaf stack config with Kubernetes provider generation and dummy context hook |
| Read as template | AWS EKS module for cluster plus node group and metadata-only scaling caveat; AWS CloudFront handling for compat-gated disable pattern; AWS Vault and ArgoCD modules for Helm release plus namespace plus null init pattern; AWS standard composite locals for resolved wiring plus compat gating; AWS standard leaf config for dependencies, dynamic modules, Kubernetes provider generation, dummy context hook, cold-start comment and resolved inputs |
| Touch | New standard module set, composite and leaf stack only |
| Resources to look for | Container cluster 1 plus node pool 1 via the container API with real k3s or mock mode; Cloud Run service 1 Docker-backed; Helm releases 2 and namespaces 2 for ArgoCD without Vault; gateway and frontend URL outputs; NodePort plus probe as primary local access; static kubeconfig context for plan safety |
| Steps | Targeted cluster apply first; write kubeconfig; full standard apply; confirm re-plan stability; confirm ArgoCD health; record cluster, backend and URL outputs for the app block |
| Acceptance and gate | Cold-start sequence repeatable; re-plan stable; ArgoCD healthy; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## Block 6: workloads and scripts

Objective: same four services on GKE with registry, config, deploy and backend registration flows.

| Item | Detail |
|---|---|
| Create | K8s GCP overlay; GCP scripts for outputs merge, build and push, deploy, backend registration, frontend sync and kubeconfig fix; GCP makefile targets; GCP outputs JSON |
| Read as template | K8s base manifests for gateway, user, order and payment services plus namespace and kustomization; AWS build and push script for login, build, retry and manifest pattern; AWS deploy script for kubeconfig, rendered config, apply versus ArgoCD-synced decision and explicit restart for mutable tags; AWS ALB registration script for NodePort lookup, Docker-network node IP resolution and stale target cleanup; AWS frontend script for address injection plus bucket sync; AWS outputs helper for multi-stack merge plus single-key accessor; AWS kubeconfig fix script; AWS make targets for images, deploy, targets, frontend, restart and kubeconfig |
| Touch | New overlay dir, new scripts gcp dir, new GCP makefile, new GCP outputs JSON; base k8s manifests read-only |
| Resources to look for | Overlay image addresses pointing at Artifact Registry repos; Artifact Registry docker login flow documented before build and push with plain-HTTP insecure-registry confirmation; rendered Secret-derived config gitignored; namespace smartcloud used in manifests, deploy, restart and ArgoCD destination; NodePort for gateway with the same port pattern; node IP from Docker network rather than bridge InternalIP; backend registration with stale pod-IP cleanup; GCS frontend bucket as deploy target; separate GCP outputs keys for project, network, registries, bucket, SQL, secrets, PubSub, cluster, backend and frontend |
| Steps | Use namespace smartcloud throughout; document the registry login flow; render overlay; build and push four images; render config from Secret Manager; apply overlay; explicit restart; register node and port with backend; sync frontend; verify gateway through backend from host with in-network fallback |
| Acceptance and gate | Four services at replicas in smartcloud; gateway reachable after registration; ArgoCD owns overlay path; namespace consistent everywhere; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## Block 7: verification and docs

Objective: round-trip proof of the core path plus reconciled inventory with AWS regression intact. Stretch scope is verified in Block 8.

| Item | Detail |
|---|---|
| Create | GCP verification script covering core round-trips plus freshness and drift checks; confirmed divergence notes in the architecture doc; reconciled resource table |
| Read as template | AWS verify script for inventory from state, freshness precheck, per-service round-trips, orphan drift check and slow-plan flag; AWS resources doc for observed inventory table conventions; AWS gaps doc for divergence entry shape; GCP implementation plan resource table as the planned baseline |
| Touch | New verification script; architecture and plan docs updated for confirmed values only |
| Resources to look for | State files under the GCP state subtree; live GCP resources for drift comparison; core round-trip targets for GCS, Secret Manager, PubSub, Firestore, SQL, KMS, service accounts, network, GKE, backend and Cloud Run service; AWS state and AWS verify outcome for regression |
| Steps | Precheck emulator plus network existence; run inventory from GCP state; run each core round-trip; run drift check for live-but-unmanaged resources; run AWS verification for regression; reconcile planned versus observed counts with reasons; record confirmed divergences |
| Acceptance and gate | All core round-trips pass; AWS verify still passes; table matches observed state; inform User; User verifies; journal update; commit only on explicit User commit confirmation |

## Block 8: optional stretch (separate fifth stack)

Objective: deferred scope without blocking the app path and without touching signed-off core. Attempted only after Block 7 sign-off.

| Item | Detail |
|---|---|
| Create | Leaf modules for compute load balancer pieces, BigQuery dataset and tables, and Cloud Run job; a separate fifth stretch stack with its own state path |
| Read as template | Block 0 coverage verdict; Block 4 patterns for assembled outputs; Block 5 patterns for Docker-backed execution; vendor notes on the DuckDB SQL subset |
| Touch | New stretch modules and stretch stack only; core stacks and composites read-only |
| Resources to look for | Backend service 1, URL map 1, target HTTP proxy 1 and global forwarding rule 1 only if Block 0 proved coverage; BigQuery dataset 1 plus tables 2 on the DuckDB subset; Cloud Run job 1 Docker-backed; compute, dialect and execution risks isolated here |
| Steps | Apply stretch resources; run backend plus table insert and query plus job execution; record coverage, dialect limits and execution behavior |
| Acceptance and gate | Stretch round-trips pass or limits documented; core gates unaffected; inform User; User verifies; journal update; commit only on explicit User commit confirmation |
