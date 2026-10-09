#!/usr/bin/env bash
# Generates k8s/gcp/01-config.yaml from the emulator state.
# Runnable from anywhere -- it locates the project root itself.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

GCP_ENDPOINT=${GCP_ENDPOINT:-http://localhost:4588}
PROJECT=${GCP_PROJECT:-floci-local}

# Pods reach Postgres at the Cloud SQL sidecar IP on the compose network.
# Pod DNS cannot resolve docker container names, but the IP is directly
# routable from k3s (probed during Block 6). Resolved fresh on every render
# because the IP changes when the sidecar is recreated.
DB_HOST=$(docker inspect floci-gcp-cloudsql-floci-local-postgres \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -n 1)
DB_PORT=5432

if [ -z "$DB_HOST" ]; then
  echo "Cloud SQL sidecar not running -- is floci-gcp up?" >&2
  exit 1
fi

SECRET_JSON=$(curl -s -m 10 \
  "$GCP_ENDPOINT/v1/projects/$PROJECT/secrets/smartcloud-app-credentials/versions/latest:access" \
  | python3 -c "import json,sys,base64; d=json.load(sys.stdin); print(base64.b64decode(d['payload']['data']).decode())")

# Delimited with \x1f (unit separator). Tab IS an IFS whitespace character,
# so bash collapses runs of them and an empty field silently shifts every
# later field left by one.
IFS=$'\x1f' read -r DB_USER DB_PASSWORD DB_NAME <<<"$(printf '%s' "$SECRET_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print('\x1f'.join([d.get('db_username', ''),
                   d.get('db_password', ''),
                   d.get('db_name', '')]))
")"

for pair in "DB_USER:$DB_USER" "DB_PASSWORD:$DB_PASSWORD" "DB_NAME:$DB_NAME"; do
  if [ -z "${pair#*:}" ]; then
    echo "${pair%%:*} is empty -- check smartcloud-app-credentials keys" >&2
    echo "  expected db_username / db_password / db_name" >&2
    exit 1
  fi
done

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
  USER_SERVICE_URL: "http://user-service.smartcloud.svc.cluster.local:4001"
  ORDER_SERVICE_URL: "http://order-service.smartcloud.svc.cluster.local:4002"
  PAYMENT_SERVICE_URL: "http://payment-service.smartcloud.svc.cluster.local:4003"
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
} > k8s/gcp/01-config.yaml

echo "Wrote k8s/gcp/01-config.yaml"
echo "  DB:    ${DB_HOST}:${DB_PORT}/${DB_NAME} as ${DB_USER}"
echo "  Redis: (disabled -- caching off, no Memorystore on emulator)"
