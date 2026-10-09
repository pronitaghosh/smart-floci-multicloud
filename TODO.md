# TODO

## Pending: KMS crypto key `rotation_period` perpetual drift

- Status: open, rotation schedule not converged locally.
- Symptom: every bootstrap re-plan shows 1 in-place change adding `rotation_period = "7776000s"` on `key`, even right after apply.
- Divergence: emulator accepts `CreateCryptoKey` with the field but never stores it; read-back omits it, so Terraform always diffs.
- Vendor model (`floci-gcp/docs/services/kms.md`): Terraform example sets only `purpose`; rotation is manual via `CreateCryptoKeyVersion` plus `UpdateCryptoKeyPrimaryVersion`. No rotation-schedule storage documented.
- Related: `destroy_scheduled_duration` behaves worse, forces key replacement, already removed.
- Proposed fix: drop `rotation_period` from `terraform/modules-gcp/kms` and `terragrunt/gcp/_env/config.yaml`; record manual-rotation model in `docs/gcp-compat-gates.md`; re-apply and confirm stable re-plan.
- Files: `terraform/modules-gcp/kms/main.tf`, `terraform/modules-gcp/kms/variables.tf`, `terragrunt/gcp/_env/config.yaml`

## Pending: shared scaffolding for AWS/GCP modules

- Status: open, design recorded, not implemented.
- Design: `docs/merge-gcp-aws-thought.md` (shared scaffolding only, keep provider trees).
- Scope: key maps, tags/labels merge, keyed outputs, composite wiring, versions constraint. No resource merge, no state move.
- Acceptance: AWS + GCP plan clean, diff only source refs.

## Research for user: Firestore database listing over REST

- Status: open, user research.
- Symptom: `GET /v1/projects/floci-local/databases` returns 404 on the emulator; removed from `helper-pg/verify_endpoints.py` defaults with an explanatory comment.
- Known: emulator serves Firestore over gRPC only (Block 0 verdict, re-confirmed). Real GCP REST lists at `GET /v1/{parent=projects/*}/databases`, so the 404 is emulator scope, not a wrong path.
- Question: confirm whether any REST or Terraform path can observe Firestore databases locally, or whether verification stays gRPC/SDK-only through Block 7.
- Files: `helper-pg/verify_endpoints.py`, `terraform/modules-gcp/firestore/main.tf`

## Pending: consider merging GCP and AWS k8s configurations

- Status: open, deferred by user direction; `k8s/gcp/` stays separate, AWS `k8s/` untouched.
- Context: sharing base manifests via one kustomization was explored; direct `../` file references are blocked by kustomize root restriction and `../` directory references cycle when the overlay sits inside the base tree. A shared-base layout needs `k8s/base/` plus sibling overlays, which renames AWS paths.
- Constraint: any merge must keep AWS entry points (`k8s/` apply path and ArgoCD path) byte-identical in built output, verified by diffing the build before and after.

## Pending: remove hard-coded IP and path from scripts/fix-gcp*.sh

- Status: open.
- Symptom: `scripts/fix-kubeconfig-gcp.sh` hard-codes the k3s server rewrite (`127.0.0.1:6443` to `127.0.0.1:6550`), the sidecar kubeconfig path (`/etc/rancher/k3s/k3s.yaml`), and the sidecar name pattern.
- Proposed fix: resolve the host port from `docker inspect` on the sidecar, and take the remote path plus server template from flags or environment with the current values as defaults.
- Files: `scripts/fix-kubeconfig-gcp.sh`

## Pending: reuse "lib/outputs.sh" and use tf_out to identify resource IDs

- Status: open.
- Context: GCP scripts (`render-k8s-config-gcp.sh`, planned deploy plus outputs helpers) shell out per stack instead of sharing one merge helper like the AWS `scripts/lib/outputs.sh` plus `tf_out` pattern.
- Proposed fix: add a GCP outputs helper that merges the four GCP stack states with a single-key accessor, and switch GCP scripts to it for resource IDs and endpoints.
- Files: `scripts/lib/outputs.sh`, `scripts/render-k8s-config-gcp.sh`

## Pending: AWS regression skips when the AWS emulator is unreachable

- Status: open.
- Context: `scripts/verify-gcp.sh` ends with an AWS regression gate, but reports FAIL when `localhost:4566` is down instead of skipping.
- Proposed fix: probe the AWS health endpoint first; skip the section with a reason when unreachable.
- Files: `scripts/verify-gcp.sh`

## Pending: merge verify.sh (AWS) and verify-gcp.sh

- Status: open, design not started.
- Context: two parallel verification scripts share inventory, freshness, round-trip, and verdict structure against different endpoints.
- Constraint: one runner with per-cloud cases; AWS and GCP gates stay independently addressable; Block 7 acceptance (both suites green) unchanged.
- Files: `verify.sh`, `scripts/verify-gcp.sh`
