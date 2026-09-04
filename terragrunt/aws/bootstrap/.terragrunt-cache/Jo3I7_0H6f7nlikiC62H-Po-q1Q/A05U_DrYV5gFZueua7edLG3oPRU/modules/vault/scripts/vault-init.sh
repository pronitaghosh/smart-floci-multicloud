#!/usr/bin/env bash
#------------------------------------------------------------------
# Initialise Vault and store its root token in AWS Secrets Manager.
#------------------------------------------------------------------
# Invoked by null_resource.floci_vault_init. Idempotent: an already-initialised
# cluster is left alone.
#------------------------------------------------------------------
set -uo pipefail

POD="${RELEASE}-0"
AWS="aws --endpoint-url ${AWS_ENDPOINT}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "waiting for ${POD} to answer the Vault API..."
for i in $(seq 1 60); do
  if kubectl exec -n "$NAMESPACE" "$POD" -- vault status -format=json >/dev/null 2>&1; then break; fi
  # exit 2 means "sealed" -- the API is up, which is all we need here
  if [ "$(kubectl exec -n "$NAMESPACE" "$POD" -- vault status -format=json 2>/dev/null; echo $?)" = "2" ]; then break; fi
  sleep 5
done

STATUS=$(kubectl exec -n "$NAMESPACE" "$POD" -- vault status -format=json 2>/dev/null || echo '{}')
INITIALIZED=$(printf '%s' "$STATUS" | python3 -c "import json,sys;print(json.load(sys.stdin).get('initialized',False))" 2>/dev/null || echo False)

if [ "$INITIALIZED" = "True" ]; then
  echo "vault is already initialised; nothing to do"
  exit 0
fi

echo "running operator init..."
if [ "$AUTO_UNSEAL" = "true" ]; then
  # With awskms the seal is handled by KMS, so there are recovery keys rather
  # than unseal keys and the cluster unseals itself on start.
  INIT=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault operator init -format=json -recovery-shares=1 -recovery-threshold=1 2>/dev/null)
else
  INIT=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault operator init -format=json -key-shares=1 -key-threshold=1 2>/dev/null)
fi

if [ -z "$INIT" ]; then
  echo "operator init produced no output -- is the pod running?" >&2
  exit 1
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
printf '%s' "$INIT" > "$TMP/init.json"

python3 - "$TMP/init.json" "$TMP/token" "$TMP/keys" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
open(sys.argv[2], 'w').write(d.get('root_token', ''))
keys = d.get('recovery_keys_b64') or d.get('unseal_keys_b64') or []
open(sys.argv[3], 'w').write(json.dumps({'keys': keys}))
PY

# Passed via file:// so the token never appears in `ps` output.
if [ -n "${ROOT_SECRET:-}" ]; then
  $AWS secretsmanager put-secret-value \
    --secret-id "$ROOT_SECRET" \
    --secret-string "file://$TMP/token" >/dev/null \
    && echo "root token -> secretsmanager://$ROOT_SECRET"
fi

if [ -n "${RECOVERY_SECRET:-}" ]; then
  $AWS secretsmanager put-secret-value \
    --secret-id "$RECOVERY_SECRET" \
    --secret-string "file://$TMP/keys" >/dev/null \
    && echo "recovery keys -> secretsmanager://$RECOVERY_SECRET"
fi

# Shamir needs an explicit unseal; awskms does it automatically.
if [ "$AUTO_UNSEAL" != "true" ]; then
  KEY=$(python3 -c "import json;print(json.load(open('$TMP/keys'))['keys'][0])")
  kubectl exec -n "$NAMESPACE" "$POD" -- vault operator unseal "$KEY" >/dev/null 2>&1 \
    && echo "unsealed with the Shamir key"
fi

echo "vault initialised"
