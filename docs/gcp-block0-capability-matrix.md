# Block 0 Provider Spike Results

Date: 2026-10-07 UTC. Emulator: floci/floci-gcp:latest 0.10.0, storage memory, container floci-gcp-spike, port 4588, project floci-local.
Probes: repro/gcp-spike/, google provider ~> 7.36, fake token.

## Capability matrix

| Service | Terraform | Verdict | Notes |
|---|---|---|---|
| GCS bucket | google_storage_bucket | supported | create/read ok |
| Secret Manager secret + version | google_secret_manager_secret, version | supported | publish/get ok |
| IAM service account | google_service_account | supported degraded | display_name not round-tripped |
| KMS ring + key | google_kms_key_ring, crypto_key | supported | list ok |
| PubSub topic + sub | google_pubsub_topic, subscription | supported | publish returned messageIds 1 |
| Service Usage + Resource Manager | google_project_service | supported | run.googleapis.com enabled |
| Compute network, subnetwork, firewall | google_compute_network, subnetwork, firewall | supported | firewall requires source_ranges |
| Compute health check + backend service | google_compute_health_check, backend_service | supported conditional | requires EXTERNAL_MANAGED + exactly one health check; default shape 501 |
| Cloud SQL instance + db + user | google_sql_database_instance, database, user | supported | Docker sidecar postgres:16.14-alpine spawned; reports 172.17.0.3:5432, no host port published |
| Cloud Run service | google_cloud_run_v2_service | supported degraded | Docker sidecar nginx spawned; deletion_protection + labels drift; interrupted apply left emulator resource without state, fixed by import |
| BigQuery dataset + table | google_bigquery_dataset, table | supported | get ok |
| GKE cluster + node pool | google_container_cluster, node_pool | supported | requires container_custom_endpoint host mode http://container.localhost:4588/; path mode 404s; real k3s sidecar rancher/k3s:latest spawned; node pool needs ignore_node_count_changes |
| Artifact Registry repo | google_artifact_registry_repository | unsupported | 404; service absent from enabled list; no registry pull path proven |
| Firestore database | google_firestore_database | unsupported via Terraform | 404; gRPC-only, needs SDK path; usable via API, not provisionable via provider |
| Compute LB full path | url map, proxy, forwarding rule | not probed | backend only proven; defer to Block 8 |

## App data dependencies

- gateway: stateless proxy, USER_SERVICE_URL + ORDER_SERVICE_URL only.
- user-service: Postgres only, DB_HOST/PORT/USER/PASSWORD/NAME.
- order-service: Postgres required, Redis optional (REDIS_HOST unset disables cache, no failure).
- payment-service: stateless mock, no DB.
- Verdict: v1 Postgres-only works with cache disabled, no app code change.

## Frozen decisions for later blocks

- Endpoints: versioned suffixes per compat-terraform mapping; GKE host mode only.
- SQL: host-side published port range undecided, record in Block 1; sidecar has no host mapping today.
- Registry: no emulated Artifact Registry; Block 6 needs alternate image path decision.
- Firestore: provision via SDK, not Terraform.
- LB: EXTERNAL_MANAGED + health check shape; full Terraform deferred to Block 8.
- Storage mode: memory used; Block 1 records memory for verify, hybrid dev only, plus reset command.
