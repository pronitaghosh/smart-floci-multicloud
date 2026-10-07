# GCP compat gates

Enumerated local workarounds. Each maps to file and field. Honoured only when `global.floci_compat` is true. Set false for real GCP.

| # | Workaround | File | Field |
|---|---|---|---|
| 1 | Fake OAuth token, IAM never enforced | terragrunt/gcp/provider-gcp.tftpl | `access_token = "fake"` |
| 2 | Per-service custom endpoints with API version suffixes | terragrunt/gcp/provider-gcp.tftpl | `*_custom_endpoint` |
| 3 | GKE container endpoint host mode only | terragrunt/gcp/provider-gcp.tftpl | `container_custom_endpoint = "http://container.localhost:4588/"` |
| 4 | Password substitution, no credential on disk | terragrunt/gcp/root.hcl | `__DB_PASSWORD__` replace |
| 5 | In-cluster endpoint substitution | terragrunt/gcp/root.hcl | `__FLOCI_IP__` replace |
| 6 | Local state under gcp subtree | terragrunt/gcp/root.hcl | `.state/<env>/gcp/<stack>` |
| 7 | Null SQL fields the emulator does not round-trip | terraform/modules-gcp/composite-stateful | Block 4 |
| 8 | GCS bucket shape-only versioning/policy | terraform/modules-gcp/composite-bootstrap | Block 3 |
| 9 | Firewall rules shape-only, source ranges required | terragrunt/gcp/_env/config.yaml | `network.firewall_rules[].source_ranges` |
| 10 | Firestore via SDK, not Terraform | n/a | Block 0 verdict |
| 11 | Artifact Registry create 404s via Terraform and REST; module publishes address pattern only, repos land in Block 6 | terraform/modules-gcp/registry/main.tf | placeholder outputs |
| 12 | NodePort plus registration instead of LB IPs | terraform/modules-gcp/composite-standard | Block 5 |
| 13 | No Memorystore; Firestore plus PubSub cover stateful | terragrunt/gcp/_env/config.yaml | no redis section |
| 14 | BigQuery, LB Terraform, Run job stretch-only | n/a | Block 8 |
