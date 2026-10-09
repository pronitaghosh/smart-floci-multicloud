#!/usr/bin/env bash
#------------------------------------------------------------------
# Deploy the application workloads to the emulated GKE cluster.
#------------------------------------------------------------------
# ArgoCD owns everything in k8s/gcp once the repo is pushed. This script
# covers the two things Argo cannot do, plus a direct apply so the demo
# works before the repo is pushed:
#
#   1. Render 01-config.yaml from Secret Manager plus the Cloud SQL sidecar
#      address. It holds the DB password, so it is gitignored and therefore
#      invisible to Argo. That seam is what External Secrets Operator would
#      close.
#   2. Apply the manifests. Identical content to what Argo reconciles, so the
#      two never fight -- run either, or both.
#
# There is deliberately no `kubectl set image`. Image references are the
# plain local names imported into k3s by scripts/build-and-import-gcp.sh,
# because GitOps and imperative patching are incompatible: Argo reverts the
# patch on its next sync.
#------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONTEXT="floci-gcp-smartcloud-cluster"

echo "=== Pointing kubectl at the emulated GKE cluster ==="
./scripts/fix-kubeconfig-gcp.sh smartcloud-cluster
kubectl config use-context "$CONTEXT"

echo "=== Rendering ConfigMap/Secret from Secret Manager ==="
# Not managed by Argo: contains the DB password and is gitignored.
./scripts/render-k8s-config-gcp.sh

echo "=== Applying manifests ==="
kubectl apply -f k8s/gcp/00-namespace.yaml
kubectl apply -f k8s/gcp/01-config.yaml

if kubectl get application -n argocd smartcloud >/dev/null 2>&1; then
  SYNC=$(kubectl get application -n argocd smartcloud \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  if [ "$SYNC" = "Synced" ]; then
    echo "  ArgoCD reports Synced -- leaving the workloads to it."
  else
    echo "  ArgoCD present but ${SYNC:-not yet reporting}; applying directly as well."
    kubectl apply -k k8s/gcp/
  fi
else
  echo "  ArgoCD not installed; applying directly."
  kubectl apply -k k8s/gcp/
fi

# A mutable :latest tag means a new image does NOT change the manifest, so
# neither `kubectl apply` nor an ArgoCD sync will restart anything -- the old
# pods keep running the old code, and a fix appears to do nothing. Restarting
# explicitly is the honest price of a mutable tag. It also re-reads the
# ConfigMap, which envFrom only injects at pod start.
echo "=== Restarting deployments to pick up :latest and current config ==="
kubectl rollout restart deployment -n smartcloud >/dev/null 2>&1 || true

echo "=== Waiting for rollout ==="
for svc in gateway user-service order-service payment-service; do
  kubectl rollout status "deployment/$svc" -n smartcloud --timeout=180s || true
done

kubectl get pods -n smartcloud

echo ""
echo "Next: port-forward the gateway (no load balancer on the emulator):"
echo "  kubectl port-forward -n smartcloud svc/gateway 8080:4000"
