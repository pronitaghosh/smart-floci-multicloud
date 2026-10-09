#!/usr/bin/env bash
# Builds gateway, user-service, order-service, payment-service and imports
# them into the emulated GKE cluster's containerd. Runnable from anywhere --
# it locates the project root itself.
#
# There is no Artifact Registry on the emulator (create returns 404), so
# there is no login or push step: images are imported by name and the overlay
# references the plain local names with IfNotPresent.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CLUSTER_NAME="${1:-smartcloud-cluster}"
SIDECAR="floci-gcp-gke-floci-local-${CLUSTER_NAME}"
CTR="ctr --address /run/k3s/containerd/containerd.sock -n k8s.io"

if ! docker ps --format "{{.Names}}" | grep -qx "$SIDECAR"; then
  echo "GKE sidecar $SIDECAR not running" >&2
  exit 1
fi

SERVICES=(gateway user-service order-service payment-service)

for svc in "${SERVICES[@]}"; do
  # NOTE: always brace the variable before a colon. Bare "$svc:latest"
  # mis-expands in this shell; "${svc}:latest" is required.
  echo "=== Building ${svc} -> ${svc}:latest ==="
  # --provenance/--sbom off: buildx otherwise attaches attestation manifests
  # that serve nothing here.
  docker build --no-cache --provenance=false --sbom=false \
    -t "${svc}:latest" "services/${svc}"

  echo "=== Importing ${svc}:latest into k3s ==="
  docker save "${svc}:latest" \
    | docker exec -i "$SIDECAR" $CTR images import - >/dev/null
done

echo ""
echo "All images imported into ${SIDECAR}."
kubectl config use-context "floci-gcp-${CLUSTER_NAME}" >/dev/null 2>&1 || true
