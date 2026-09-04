#!/usr/bin/env bash
#------------------------------------------------------------------
# Deploy the application workloads to the emulated EKS cluster.
#------------------------------------------------------------------
# ArgoCD owns everything in k8s/ once it can reach the git repo. This script
# covers the two things Argo cannot do, plus a direct apply so the demo works
# before the repo is pushed:
#
#   1. Render 01-config.yaml from Secrets Manager. It holds the DB password,
#      so it is gitignored and therefore invisible to Argo. That seam is what
#      External Secrets Operator would close.
#   2. Apply the manifests. Identical content to what Argo reconciles, so the
#      two never fight -- run either, or both.
#
# There is deliberately no `kubectl set image` any more. Image references are
# committed in the manifests (floci's ECR address is deterministic), because
# GitOps and imperative patching are incompatible: Argo reverts the patch on
# its next sync. That also removes the class of bug where a stale cached image
# keeps running while a fix appears to do nothing.
#------------------------------------------------------------------
set -euo pipefail

# Stack outputs come from four Terragrunt states now, merged by this helper.
source "$(dirname "${BASH_SOURCE[0]}")/lib/outputs.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLOCI_ENDPOINT=${FLOCI_ENDPOINT:-http://localhost:4566}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

aws() { command aws --endpoint-url "$FLOCI_ENDPOINT" "$@"; }

CLUSTER_NAME=$(tf_out eks_cluster_name)

echo "=== Pointing kubectl at ${CLUSTER_NAME} (via floci) ==="
aws eks update-kubeconfig --name "$CLUSTER_NAME"
# Pin credentials into the exec block so GUI clients and the Terraform helm
# provider can authenticate too.
./scripts/fix-kubeconfig.sh "$CLUSTER_NAME" >/dev/null 2>&1 || true

echo "=== Rendering ConfigMap/Secret from Secrets Manager ==="
# Not managed by Argo: contains the DB password and is gitignored.
./scripts/render-k8s-config.sh

echo "=== Applying manifests ==="
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-config.yaml

if kubectl get application -n argocd msdemo >/dev/null 2>&1; then
  SYNC=$(kubectl get application -n argocd msdemo \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  if [ "$SYNC" = "Synced" ]; then
    echo "  ArgoCD reports Synced -- leaving the workloads to it."
  else
    echo "  ArgoCD present but ${SYNC:-not yet reporting}; applying directly as well."
    kubectl apply -k k8s/
  fi
else
  echo "  ArgoCD not installed; applying directly."
  kubectl apply -k k8s/
fi

echo "=== Waiting for rollout ==="
for svc in gateway user-service order-service payment-service; do
  kubectl rollout status "deployment/$svc" -n msdemo --timeout=180s || true
done

kubectl get pods -n msdemo

echo ""
echo "Next: ./scripts/register-alb-targets.sh   (points the ALB at the gateway NodePort)"
