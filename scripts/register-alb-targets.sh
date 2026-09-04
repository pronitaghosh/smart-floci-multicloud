#!/usr/bin/env bash
# Registers the gateway pods' IPs directly with the ALB target group.
# This stands in for what the AWS Load Balancer Controller would normally
# automate in a real EKS cluster -- floci doesn't ship that controller,
# so we do the registration by hand for this demo.
set -euo pipefail

# Stack outputs come from four Terragrunt states now, merged by this helper.
source "$(dirname "${BASH_SOURCE[0]}")/lib/outputs.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLOCI_ENDPOINT=${FLOCI_ENDPOINT:-http://localhost:4566}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

# Without this the script would register targets in the real AWS account.
aws() { command aws --endpoint-url "$FLOCI_ENDPOINT" "$@"; }

TG_ARN=$(aws elbv2 describe-target-groups --names msdemo-gateway-tg \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
echo "Target group: $TG_ARN"

# Refuse to proceed if no gateway pod is actually serving -- otherwise we
# register a node port that nothing is behind.
READY=$(kubectl get pods -n msdemo -l app=gateway \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[*].status.podIP}' | wc -w | tr -d ' ')
if [ "$READY" -eq 0 ]; then
  echo "No running gateway pods -- is the deployment rolled out?" >&2
  echo "  kubectl get pods -n msdemo -l app=gateway" >&2
  exit 1
fi
echo "Gateway pods running: $READY"

NODE_PORT=$(kubectl get svc gateway -n msdemo -o jsonpath='{.spec.ports[0].nodePort}')
if [ -z "$NODE_PORT" ]; then
  echo "svc/gateway has no nodePort -- it must be type: NodePort for the ALB to reach it" >&2
  exit 1
fi

# The node's Kubernetes InternalIP is its *default bridge* address (172.17.x),
# which the floci container cannot reach. We need its address on the
# floci_default network instead, so read it from docker rather than kubectl.
# Override with NODE_IP=... if the container is named differently.
CLUSTER_NAME=$(tf_out eks_cluster_name)
if [ -z "${NODE_IP:-}" ]; then
  NODE_IP=$(docker inspect "floci-eks-${CLUSTER_NAME}" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{if ne $k "bridge"}}{{$v.IPAddress}}{{end}}{{end}}' \
    2>/dev/null)
fi
if [ -z "$NODE_IP" ]; then
  echo "could not determine the k3s node IP on the floci network" >&2
  echo "  set it explicitly:  NODE_IP=172.18.0.5 $0" >&2
  exit 1
fi

# Drop anything already registered that isn't this node:port -- notably pod IPs
# from earlier runs, which stay permanently unhealthy.
EXISTING=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].[Target.Id,Target.Port]' --output text 2>/dev/null)
while read -r eid eport; do
  if [ -n "$eid" ] && [ "$eid:$eport" != "$NODE_IP:$NODE_PORT" ]; then
    echo "  deregistering stale target ${eid}:${eport}"
    aws elbv2 deregister-targets --target-group-arn "$TG_ARN" \
      --targets "Id=${eid},Port=${eport}" >/dev/null 2>&1 || true
  fi
done <<<"$EXISTING"

echo "Registering node target: ${NODE_IP}:${NODE_PORT}"
aws elbv2 register-targets --target-group-arn "$TG_ARN" \
  --targets "Id=${NODE_IP},Port=${NODE_PORT}"

echo "=== Target health ==="
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --output table
