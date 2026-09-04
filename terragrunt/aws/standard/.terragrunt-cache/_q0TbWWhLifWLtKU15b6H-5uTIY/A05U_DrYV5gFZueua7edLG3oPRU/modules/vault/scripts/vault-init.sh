#!/usr/bin/env bash
#------------------------------------------------------------------
# Initialise Vault and store its root token in AWS Secrets Manager.
#------------------------------------------------------------------
# Invoked by null_resource.floci_vault_init. Idempotent: an already-initialised
# cluster is left alone.
#------------------------------------------------------------------
set -uo pipefail

AWS="aws --endpoint-url ${AWS_ENDPOINT}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Do NOT guess the pod name. The chart's fullname is <release>-<chart>, so a
# release called "msdemo" produces "msdemo-vault-0" -- not "msdemo-0". Getting
# this wrong makes every kubectl exec fail silently.
STS=$(kubectl get statefulset -n "$NAMESPACE" \
  -l "app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/name=vault" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$STS" ]; then
  echo "no vault statefulset found in namespace $NAMESPACE for release $RELEASE" >&2
  kubectl get statefulset -n "$NAMESPACE" >&2 2>/dev/null || true
  exit 1
fi

POD="${STS}-0"
echo "vault statefulset: $STS (initialising via $POD)"

echo "waiting for ${POD} to answer the Vault API..."
# `vault status` exits 0 when unsealed, 2 when sealed and 1 when the API is
# unreachable -- so the exit code alone cannot distinguish "not ready" from
# "sealed but fine". Wait for a parseable JSON body instead, which only
# appears once the API is actually answering.
for i in $(seq 1 60); do
  BODY=$(kubectl exec -n "$NAMESPACE" "$POD" -- vault status -format=json 2>/dev/null || true)
  if printf '%s' "$BODY" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    echo "  API is up after $((i * 5))s"
    break
  fi
  sleep 5
done

STATUS=$(kubectl exec -n "$NAMESPACE" "$POD" -- vault status -format=json 2>/dev/null || echo '{}')
INITIALIZED=$(printf '%s' "$STATUS" | python3 -c "import json,sys;print(json.load(sys.stdin).get('initialized',False))" 2>/dev/null || echo False)

if [ "$INITIALIZED" = "True" ]; then
  echo "vault is already initialised; nothing to do"
  exit 0
fi

echo "running operator init..."
# stderr is captured, NOT discarded. Swallowing it here previously turned every
# failure into the useless "produced no output", which hid the real cause.
ERR=$(mktemp)
if [ "$AUTO_UNSEAL" = "true" ]; then
  # With awskms the seal is handled by KMS, so there are recovery keys rather
  # than unseal keys and the cluster unseals itself on start.
  INIT=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault operator init -format=json -recovery-shares=1 -recovery-threshold=1 2>"$ERR")
else
  INIT=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault operator init -format=json -key-shares=1 -key-threshold=1 2>"$ERR")
fi

if [ -z "$INIT" ]; then
  echo "operator init failed. vault said:" >&2
  sed 's/^/    /' "$ERR" >&2
  echo "  pod state:" >&2
  kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE" >&2 2>/dev/null || true
  echo "  last 20 log lines from $POD:" >&2
  kubectl logs -n "$NAMESPACE" "$POD" --tail=20 2>/dev/null | sed 's/^/    /' >&2 || true
  rm -f "$ERR"
  exit 1
fi
rm -f "$ERR"

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
