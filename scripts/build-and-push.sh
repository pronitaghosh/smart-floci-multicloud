#!/usr/bin/env bash
# Builds and pushes gateway, user-service, order-service, payment-service to ECR.
# Runnable from anywhere -- it locates the project root itself.
set -euo pipefail

# Stack outputs come from four Terragrunt states now, merged by this helper.
source "$(dirname "${BASH_SOURCE[0]}")/lib/outputs.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLOCI_ENDPOINT=${FLOCI_ENDPOINT:-http://localhost:4566}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

# Every aws call must target floci, never the real account.
aws() { command aws --endpoint-url "$FLOCI_ENDPOINT" "$@"; }

ECR_URLS_JSON=$(tf_out ecr_repository_urls)

SERVICES=(gateway user-service order-service payment-service)

REGISTRY=$(printf '%s' "$ECR_URLS_JSON" \
  | python3 -c "import json,sys; print(list(json.load(sys.stdin).values())[0].split('/')[0])")

echo "=== Logging in to $REGISTRY ==="
# floci's registry is plain HTTP. Docker refuses that unless the host is listed
# under 'insecure-registries' in the daemon config, so say so up front.
if ! aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"; then
  cat >&2 <<EOF

docker login failed. If the error mentions HTTP/TLS, add this to Docker
Desktop -> Settings -> Docker Engine, then restart Docker:

  { "insecure-registries": ["${REGISTRY}"] }

EOF
  exit 1
fi

MANIFEST=build-images.txt
: > "$MANIFEST"   # truncate; this file describes the current build only

for svc in "${SERVICES[@]}"; do
  IMAGE_URI=$(printf '%s' "$ECR_URLS_JSON" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['$svc'])")

  if [ ! -f "services/$svc/Dockerfile" ]; then
    echo "services/$svc/Dockerfile missing -- cannot build $svc" >&2
    exit 1
  fi

  echo "=== Building $svc -> ${IMAGE_URI}:latest ==="
  # --provenance/--sbom off: buildx otherwise attaches attestation manifests
  # whose empty sha256("{}") config blob is pushed over https through Docker
  # Desktop's internal proxy, which intermittently times out against floci's
  # plain-HTTP registry. Nothing here needs attestations.
  docker build --provenance=false --sbom=false \
    -t "${IMAGE_URI}:latest" "services/$svc"

  # The registry is a local sidecar; a timeout is transient, so retry briefly.
  for attempt in 1 2 3; do
    if docker push "${IMAGE_URI}:latest"; then
      break
    fi
    if [ "$attempt" -eq 3 ]; then
      echo "push of $svc failed after 3 attempts" >&2
      exit 1
    fi
    echo "  push attempt $attempt failed, retrying in $((attempt * 5))s..." >&2
    sleep $((attempt * 5))
  done

  echo "$svc -> ${IMAGE_URI}:latest" >> "$MANIFEST"
done

echo ""
echo "All images pushed. Image URIs written to $(pwd)/$MANIFEST"
