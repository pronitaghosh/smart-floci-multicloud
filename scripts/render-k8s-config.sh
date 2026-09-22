#!/usr/bin/env bash
# Generates k8s/01-config.yaml from live terraform outputs.
# Runnable from anywhere -- it locates the project root itself.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLOCI_ENDPOINT=${FLOCI_ENDPOINT:-http://localhost:4566}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

# Stack outputs come from four Terragrunt states now, merged by this helper.
# tf_out() is already null-safe: a disabled module yields an empty string.
source "$(dirname "${BASH_SOURCE[0]}")/lib/outputs.sh"

RDS_ENDPOINT=$(tf_out rds_endpoint)        # host:port
REDIS_ENDPOINT=$(tf_out redis_endpoint)    # host only; empty when disabled

# floci reports the ElastiCache endpoint as the literal string "localhost".
# That is a control-plane value with no data plane behind it -- unlike EKS, RDS
# and ECR, floci starts no container for ElastiCache. From inside a pod
# "localhost" is the pod's own loopback, so the client dials itself and
# node-redis retries forever. Treat it as "no cache" rather than passing it on.
case "$REDIS_ENDPOINT" in
  localhost|127.0.0.1|"")
    if [ -n "$REDIS_ENDPOINT" ]; then
      echo "  note: elasticache endpoint is '${REDIS_ENDPOINT}' -- not reachable from a pod; caching disabled" >&2
    fi
    REDIS_ENDPOINT=""
    ;;
esac
ALB_DNS=$(tf_out alb_dns_name)

if [ -z "$RDS_ENDPOINT" ]; then
  echo "rds_endpoint is empty -- has terraform apply run?" >&2
  exit 1
fi

DB_HOST="${RDS_ENDPOINT%%:*}"
DB_PORT="${RDS_ENDPOINT##*:}"
if [ "$DB_PORT" = "$RDS_ENDPOINT" ]; then
  DB_PORT=5432   # endpoint carried no :port suffix
fi

# Credentials come from Secrets Manager, so this file is not a second place
# the password has to be kept in sync.
SECRET_ARN=$(tf_out app_secret_arn)
SECRET_JSON=$(command aws --endpoint-url "$FLOCI_ENDPOINT" secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" --query SecretString --output text 2>/dev/null || printf '{}')

# Delimited with \x1f (unit separator). Tab looks tempting but tab IS an IFS
# whitespace character, so bash collapses runs of them and an empty field
# silently shifts every later field left by one.
IFS=$'\x1f' read -r DB_USER DB_PASSWORD DB_NAME <<<"$(printf '%s' "$SECRET_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
# Key names must match modules/secrets/main.tf exactly.
print('\x1f'.join([d.get('db_username', ''),
                   d.get('db_password', ''),
                   d.get('db_name', '')]))
")"

for pair in "DB_USER:$DB_USER" "DB_PASSWORD:$DB_PASSWORD" "DB_NAME:$DB_NAME"; do
  if [ -z "${pair#*:}" ]; then
    echo "${pair%%:*} is empty -- check the keys in $SECRET_ARN" >&2
    echo "  expected db_username / db_password / db_name" >&2
    exit 1
  fi
done

mkdir -p k8s

{
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: smartcloud-config
  namespace: smartcloud
data:
  DB_HOST: "${DB_HOST}"
  DB_PORT: "${DB_PORT}"
  DB_NAME: "${DB_NAME}"
  ALB_DNS_NAME: "${ALB_DNS}"
  USER_SERVICE_URL: "http://user-service.smartcloud.svc.cluster.local:4001"
  ORDER_SERVICE_URL: "http://order-service.smartcloud.svc.cluster.local:4002"
  PAYMENT_SERVICE_URL: "http://payment-service.smartcloud.svc.cluster.local:4003"
EOF

  # Omit the Redis keys entirely when there is no cache. order-service treats
  # an unset REDIS_HOST as "caching disabled" rather than failing.
  if [ -n "$REDIS_ENDPOINT" ]; then
    cat <<EOF
  REDIS_HOST: "${REDIS_ENDPOINT}"
  REDIS_PORT: "6379"
EOF
  fi

  cat <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: smartcloud-db-secret
  namespace: smartcloud
type: Opaque
stringData:
  DB_USER: "${DB_USER}"
  DB_PASSWORD: "${DB_PASSWORD}"
EOF
} > k8s/01-config.yaml

echo "Wrote k8s/01-config.yaml"
echo "  DB:    ${DB_HOST}:${DB_PORT}/${DB_NAME} as ${DB_USER}"
echo "  Redis: ${REDIS_ENDPOINT:-(disabled -- caching off)}"
echo "  ALB:   ${ALB_DNS}"
