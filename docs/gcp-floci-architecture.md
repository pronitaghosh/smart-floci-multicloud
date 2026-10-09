# GCP Local Env Architecture (floci-gcp)

Basic design to add a GCP env beside the working AWS env. Same repo, parallel trees, shared patterns. No changes to the AWS terragrunt tree, AWS terraform modules, AWS compose service, AWS state, AWS outputs file, or AWS up target.

Decisions (confirmed): scope is full floci-gcp including Pub/Sub, BigQuery and Cloud Run; layout is parallel trees with a terragrunt gcp tree plus a modules-gcp tree; workloads are the same four Node images on GKE via Artifact Registry plus a k8s overlay.

## 1. Runtime: separate floci-gcp container is required

Verified against the floci-gcp Quick Start and Docker Compose docs.

Floci is one container per cloud, one port each. The AWS emulator serves AWS only on port 4566. The GCP emulator is a separate image on port 4588. Azure and OCI are likewise separate. The GCP tab in the floci UI is a catalog placeholder rendered from the service catalog. It serves no GCP API without the backend container. The current compose file runs the AWS service only, so no GCP API is currently served.

Required addition is additive, with the AWS service untouched and no port clash. The new service uses the floci-gcp latest image, publishes port 4588, mounts the Docker socket for Docker-backed services, uses a data volume for persistence, and sets hostname, base URL and hybrid storage mode via environment. Single port 4588 serves gRPC plus REST via ALPN. Docker-backed data planes expose generated endpoints where native protocols require it. Hybrid storage mode with the data volume keeps state across restarts, unlike the AWS emulator which is ephemeral. Credentials are not validated. SDK auth bypass uses emulator host variables and Terraform auth bypass uses a fake OAuth token. The default project is floci-local. Terraform custom endpoints must include the API version suffix, otherwise the provider hits an unversioned path. Only REST-exposed services are reachable via Terraform custom endpoints.

Fidelity model (same rule as AWS): Docker-backed is faithful; in-process is faithful for CRUD; control-plane-only is shape-only.

Service backing summary: GCS in-process; Pub/Sub in-process; Firestore and Datastore in-process; Secret Manager in-process; KMS in-process; IAM and service accounts in-process with bindings created but never enforced; Service Usage plus Resource Manager in-process for project service enables and project lookups; Cloud SQL Postgres Docker-backed by default with a mock flag for control-plane-only (MySQL out of v1 scope); GKE as real k3s via Docker or mock mode via the container API; Cloud Run services, revisions, jobs, workers and instances Docker-backed by default with a mock flag for control-plane-only, with the job deferred to stretch; BigQuery on a DuckDB engine with a GoogleSQL subset; Cloud Tasks, Scheduler, Functions, Eventarc, Monitoring, Logging, Kafka and Firebase Auth are control-plane-only or in-process with no Docker data plane for Functions and Tasks.

## 2. Entry point: Makefile.gcp (planned, mirrors AWS Makefile)

Status: design only, file not created yet. It will stay a separate file so the AWS Makefile is untouched. Merge options when wanted: include it at the end of the AWS Makefile since all GCP targets are gcp-prefixed with no clash, or keep it split and invoke with make minus f targeting Makefile.gcp. Until merged, GCP runs through the separate file.

Variables mirror AWS with GCP names: a GCP terragrunt directory defaulting to the gcp tree, same four stack names, same client and environment names, a GCP project defaulting to floci-local, a GCP endpoint defaulting to localhost on port 4588, auto-detected GCP container IP via docker inspect for the in-cluster endpoint, Terraform path set to terraform, OAuth token set to fake, and shared plugin cache.

Targets mirror AWS one to one: a reachability check against the GCP endpoint; format and validate scoped to the GCP module tree; plan, apply, destroy and output for selected stacks with the same space-separated stack guard; plan-all, apply-all and destroy-all in dependency order; outputs merged into a separate GCP outputs JSON; images built and pushed to Artifact Registry; deploy rendering Secret-derived config then applying the GCP k8s overlay then an explicit rollout restart; targets registering the gateway NodePort with the load balancer backend; frontend syncing to GCS; restart of workloads; verify running the GCP verification script; kubeconfig pointing kubectl at the emulated GKE cluster via get-credentials plus a fix-kubeconfig helper; ArgoCD sync and refresh status for the GCP application; full GCP build from nothing with cold-start handling (bootstrap, iam and stateful first, then GKE only, then kubeconfig, then full standard, then outputs, images, deploy, targets and frontend); docker start and clean scoped to the GCP emulator label only; GCP-only down and clean scoped to GCP state and GCP outputs.

Cold-start handling copies AWS: the cluster does not exist when the standard stack first runs, so create the cluster first without platform releases, write kubeconfig, then apply the rest. Host tooling uses localhost on port 4588 while pods use the compose DNS name on port 4588, same dual-address split as AWS host versus in-cluster endpoints.

## 3. Single config (mirrors AWS)

One GCP config file is the only input for GCP stacks. A GCP floci compat flag is the local surface and parallels the AWS flag. The file stays correct for real GCP and the flag gates emulator deviations in composites.

An env file holds environment variables with defaults: GCP endpoint URL defaulting to localhost on port 4588 with empty meaning real GCP, GCP project, local-only database password default, and auto-detected in-cluster address from the GCP container.

A GCP root config builds the merged config with password and endpoint substitutions so no credential lands on disk, stores local state under a gcp state subtree separate from AWS, generates the google provider from a new provider template with per-service custom endpoints plus version suffixes when an endpoint is set and a plain provider for real GCP, and passes a single YAML string input that composites decode.

Common libraries are reused as patterns: composite shape with a single string config variable, locals decoding YAML plus a resolved merge, static module blocks, an outputs merge helper writing a separate GCP outputs JSON, and a round-trip verification script structure.

## 4. Stacks (mirror bootstrap, iam, stateful, standard)

Leaf config pattern copies AWS: include root plus env, derive the composite name from the directory name, support a local module path or a registry source, and use dependencies plus a resolved merge with mock outputs for plan-before-apply.

Scope note: the implementation plan governs on scope. BigQuery datasets and tables, the Cloud Run job, and compute load balancer Terraform are stretch-only in Block 8, not core. Sections 4 and 7 below still describe them inline for context; treat them as deferred until Block 8 sign-off.

Stack contents for v1: bootstrap holds VPC network and subnetworks, firewall rules that are shape-only locally, KMS keyring and key, five Artifact Registry Docker repos for frontend, gateway, user, order and payment services, the frontend GCS bucket, and project service enables. IAM holds service accounts plus project IAM bindings for GKE nodes, the app identity and the Cloud Run invoker, created but never enforced locally. Stateful holds the Cloud SQL Postgres instance, database and user, the Firestore database, PubSub topics and subscriptions for orders and payments, Secret Manager secrets with app credentials assembled from the Cloud SQL endpoint plus an empty ArgoCD admin container, with BigQuery datasets and tables deferred to stretch. Standard holds the GKE cluster and node pool, the Cloud Run service, ArgoCD platform releases on GKE, and gateway and frontend URL outputs, with the external HTTP load balancer Terraform and the Cloud Run job deferred to stretch. Cloud SQL scope for v1 is Postgres only; MySQL is an explicit non-goal.

Module shape copies AWS: standard file set per module, global config plus a per-thing config input, iteration over a map, and GCP labels in place of the AWS tags merge.

Local compat gates sit behind the GCP compat flag: Cloud SQL auth and private-network fields are nulled if not round-tripped; there is no floci-gcp Memorystore equivalent so Firestore and PubSub are used instead of force-fitting Redis; Cloud Functions and Tasks stay control-plane-only; load balancer backend type switches for local reachability as described in section 6.

## 5. GKE specifics (parallels EKS)

Kubernetes and Helm providers are generated from a static kubeconfig context, with a dummy context hook so plan works pre-cluster. Same cold-start targeted-apply sequence as EKS. Authentication uses get-credentials against the GCP endpoint and the emulator accepts any token. Node pools carry the same metadata-only risk as EKS scaling config, so autoscaling is not asserted locally. Workloads reuse the same service Dockerfiles. A GCP kustomize overlay rewrites images to Artifact Registry addresses and keeps probes and ports. Rendered Secret-derived config stays rendered and gitignored. ArgoCD owns the GCP overlay path and direct apply covers pre-push like the AWS deploy flow. Mutable latest tags still need an explicit rollout restart.

## 6. Reachability workaround (parallels ALB NodePort)

Expect the AWS gap to recur: the emulator load balancer container has no route to the k3s pod CIDR, so pod-IP endpoints health-check as timeout. Plan: gateway Service stays NodePort with the same port pattern, the registration script resolves the GKE node IP via docker inspect on the compose network rather than the unreachable bridge InternalIP, registers node and port with the backend, and deregisters stale pod-IP endpoints. Confirm against the emulator and keep the production-correct IP-based config behind the compat flag set to false.

Same dual-address rule: pods use the compose DNS name on port 4588, host provisioners and scripts use localhost on port 4588.

## 7. Verification (GCP script, mirrors AWS verify)

Round-trips, not describe-only, for the core path: GCS put, get, compare and delete; Secret Manager get plus JSON keys; PubSub publish and pull; Firestore write and read; Cloud SQL TCP plus a version query; KMS encrypt and decrypt; bucket and service account listing; network, subnet and firewall listing; GKE describe plus node listing; backend health plus health endpoint curl from host with in-network fallback; Cloud Run service invoke. BigQuery insert plus query and Cloud Run job execution are stretch-only in Block 8. Plus a state-freshness precheck for emulator reachability and network existence and an orphan drift check for resources live in floci-gcp but absent from GCP state. Optional full plan-all stays behind a slow-plan flag, off by default.

Implemented as scripts/verify-gcp.sh (Block 7): inventory from the four state files, freshness against the live network, round-trips per service, drift of live objects against merged outputs, and an AWS regression section that skips when the AWS emulator is down. First full run passes all GCP checks.

## 8. Non-breaking rules

Additive only: new compose service, new terragrunt gcp tree, new modules-gcp tree, new GCP scripts, new k8s GCP overlay, new GCP verification script, and this doc. No edits to AWS stacks, AWS provider template, AWS config, AWS scripts, or AWS Makefile targets.

State and outputs isolation: GCP state under a gcp state subtree versus AWS stacks; separate GCP outputs JSON versus AWS outputs JSON; GCP data volume separate from AWS ephemeral disk.

Docker cleanup uses the GCP emulator label filter only. AWS cleanup behavior is unchanged.

The demo database password plus a non-local endpoint fails the guardrail check in both clouds.

Unknowns to confirm during implementation: exact custom endpoint path per service including version suffix, GKE get-credentials plus kubeconfig shape against the emulator, Cloud SQL host-side proxy port range to publish, load balancer resource coverage in floci-gcp, and the BigQuery SQL subset for app queries.

## 9. Floci AWS versus Floci GCP implementation differences

Packaging: one container per cloud. AWS image on port 4566. GCP image on port 4588. Azure and OCI separate. The UI lists all clouds but each needs its own backend container.

Protocol: AWS multiplexes service APIs on one HTTP port. GCP serves gRPC plus REST on one port via ALPN negotiation.

Provider wiring: AWS uses per-service endpoint overrides plus credential skips and path-style S3. GCP uses per-service custom endpoints with mandatory API version suffixes plus a fake OAuth token and a project. Unversioned GCP endpoints fail.

Auth model: AWS uses static test credentials. GCP uses emulator host variables, a default local project, and any token. Neither enforces IAM locally.

State: AWS is ephemeral and loses everything on container recreate. GCP defaults to memory but supports persistent and hybrid modes with a data volume.

Project identity: AWS uses account ID, region and tags. GCP uses project, location and labels.

Networking inputs: AWS uses VPC, subnets, internet gateway, route tables and security groups. GCP uses VPC network, subnetworks and firewall rules. Both are shape-only locally with no real packet enforcement in the emulator.

Kubernetes: AWS EKS and GCP GKE both run real k3s via Docker with a mock mode on the GCP side. Both have metadata-only node pools with no real autoscaling. Both need the same cold-start sequence of targeted cluster apply, then kubeconfig, then full apply. Cluster access differs: AWS uses update-kubeconfig plus a token webhook, GCP uses get-credentials against the emulator endpoint.

Data plane: AWS RDS is Docker Postgres and ECR is a Docker registry. GCP Cloud SQL Postgres and MySQL are Docker-backed, Cloud Run execution is Docker-backed, and managed Kafka can be Docker-backed. AWS ElastiCache has no usable data plane while GCP Firestore, PubSub and BigQuery are usable in-process. GCP has no Memorystore equivalent, so Redis is not ported and Firestore plus PubSub cover stateful needs.

Registry: AWS pushes to ECR over plain HTTP with insecure registry setup. GCP pushes to Artifact Registry Docker repos with the same plain HTTP caveat to confirm.

Secrets and config: AWS uses Secrets Manager plus SSM Parameter Store. GCP uses Secret Manager only, with outputs JSON covering the SSM role.

Certificates and CDN: AWS ACM reports issued without real TLS material and CloudFront is disabled locally because the provider crashes on the emulator response. GCP load balancer and certificate coverage must be verified during implementation, with no equivalent provider crash currently known.

Load balancing: AWS ALB cannot reach the pod CIDR so the project uses NodePort plus explicit target registration. The same limitation is expected for the GCP load balancer, so the same NodePort plus registration workaround is planned and production IP-based config stays behind the compat flag.

Platform services: AWS runs Vault with KMS auto-unseal plus ArgoCD. GCP plans ArgoCD only, with no Vault equivalent. Secret-derived app config stays rendered and gitignored on both.

Verification: AWS checks a local health path plus KMS, S3, Secrets Manager, SSM, ECR, IAM, VPC, ACM, RDS, EKS and ALB round-trips. GCP checks base URL reachability plus GCS, Secret Manager, PubSub, Firestore, Cloud SQL, BigQuery, KMS, IAM service accounts, VPC network, GKE and load balancer plus Cloud Run round-trips.

Container identity: AWS sidecars filter by the floci label. GCP sidecars carry shared floci identity labels plus service, resource, project and location labels for direct lookup.

URLs and ports: GCP embeds a configured hostname and base URL in generated URLs, so the hostname must match the compose service for cross-container traffic. AWS relies on path-style addressing plus published ALB ports and a per-resource proxy port range.

Storage options: AWS has no storage mode switch. GCP supports memory, persistent, hybrid and write-ahead-log modes with a persistent path setting.

## 10. Block 7 reconciled inventory and confirmed divergences

State holds 23 resource blocks across four stacks (for_each consolidates instances per block). Planned core was 53 resources; gates rest on outputs plus round-trips, not totals. Differences with reasons:

- Subnets 1 versus 2, firewall rules 1 versus 3, project services 1 block versus 8: config carries the smaller sets; no packet enforcement locally either way.
- Artifact Registry 0 versus 5: create returns 404 on the emulator, so the module publishes address patterns only and images import into k3s by name.
- IAM members 1 block versus 5: bindings cover the three service accounts; nothing is enforced locally.
- Firestore 0 resources versus 1: database create 404s over REST, so the module is an SDK placeholder.
- Secrets 1 block plus 1 version block versus 3 plus 2: two secrets (app credentials, ArgoCD admin) with versions written at apply time.
- No second KMS key and no second namespace or null hook: single key suffices; no Vault equivalent, so one ArgoCD namespace and one password hook.
- SQL round-trip runs through the gateway user path, not direct TCP: the SQL sidecar publishes no host port, and pods use the sidecar IP because pod DNS cannot resolve docker container names.
- NodePort is dead on this emulator: nothing listens on the node for 30080 on any node IP, so host access is port-forward only. The planned NodePort plus probe path degrades to port-forward plus in-network fallback.
- Kubeconfig comes from the k3s sidecar extract: the get-credentials override stays unproven and is not needed.
- AWS regression skips when its emulator is down; both suites have not yet run green together.
