#!/usr/bin/env bash
#------------------------------------------------------------------
# Point kubectl at the emulated GKE cluster (floci-gcp sidecar k3s).
#------------------------------------------------------------------
# The emulator spawns a real k3s container per cluster with 6443 published
# on host port 6550. Its admin kubeconfig lives inside the sidecar at the
# k3s default path and uses client-cert auth, so no token or get-credentials
# flow is needed: extract it, rewrite the server to the host port, and merge
# it as a namespaced context.
#
# Idempotent; re-run after the sidecar is recreated.
#------------------------------------------------------------------
set -euo pipefail

CLUSTER_NAME="${1:-smartcloud-cluster}"
CONTEXT_NAME="floci-gcp-${CLUSTER_NAME}"
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

SIDECAR=$(docker ps --format "{{.Names}}" \
  | grep -E "^floci-gcp-gke-.*${CLUSTER_NAME}$" | head -n 1 || true)

if [ -z "$SIDECAR" ]; then
  echo "no running GKE sidecar for ${CLUSTER_NAME}" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

docker exec "$SIDECAR" cat /etc/rancher/k3s/k3s.yaml \
  | sed 's|https://127.0.0.1:6443|https://127.0.0.1:6550|' > "$TMPDIR/extracted"

# Rename cluster/user/context so the merge never collides with entries the
# user already has, then flatten-merge into the real kubeconfig.
kubectl --kubeconfig="$TMPDIR/extracted" config view --raw -o json > "$TMPDIR/renamed.json"
python3 - "$TMPDIR/renamed.json" "$CONTEXT_NAME" <<'PY'
import json, sys
path, name = sys.argv[1:3]
cfg = json.load(open(path))
for c in cfg.get("clusters", []):
    c["name"] = name
for u in cfg.get("users", []):
    u["name"] = name
for x in cfg.get("contexts", []):
    x["name"] = name
    x["context"]["cluster"] = name
    x["context"]["user"] = name
cfg["current-context"] = name
json.dump(cfg, open(path, "w"))
PY
kubectl --kubeconfig="$TMPDIR/renamed.json" config view --flatten > "$TMPDIR/single.yaml"

mkdir -p "$(dirname "$KUBECONFIG_PATH")"
[ -f "$KUBECONFIG_PATH" ] || touch "$KUBECONFIG_PATH"
KUBECONFIG="$TMPDIR/single.yaml:$KUBECONFIG_PATH" kubectl config view --flatten > "$TMPDIR/merged.yaml"
mv "$TMPDIR/merged.yaml" "$KUBECONFIG_PATH"

echo "  context ${CONTEXT_NAME} from ${SIDECAR}"
