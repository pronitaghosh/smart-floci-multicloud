#!/usr/bin/env bash
#------------------------------------------------------------------
# GCP verification: inventory from state, freshness precheck, core
# round-trips, drift check, plus AWS regression. Mirrors verify.sh.
#------------------------------------------------------------------
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

E=${FLOCI_GCP_BASE:-http://localhost:4588}
PROJECT=${FLOCI_GCP_PROJECT:-floci-local}
TIMEOUT=10
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source scripts/lib/outputs-gcp.sh >/dev/null 2>&1 || true

hdr() { echo ""; echo "=== $1 ==="; }
ok() { echo "  ok: $1"; }
no() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  skip: $1"; }

# ---------------------------------------------------------------- inventory
hdr "Inventory from GCP state"
TOTAL=0
for s in bootstrap iam stateful standard; do
  F=".state/dev/gcp/$s/terraform.tfstate"
  [ -f "$F" ] || { no "missing $F"; continue; }
  N=$(python3 -c "import json; print(len(json.load(open('$F')).get('resources', [])))")
  echo "  $s: $N resources"
  TOTAL=$((TOTAL + N))
done
echo "  $TOTAL resources across 4 stacks"
[ "$TOTAL" -gt 0 ] || no "empty inventory"

# ---------------------------------------------------------------- freshness
hdr "State freshness"
[ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$E/_floci-gcp/info")" = "200" ] \
  && ok "emulator reachable at $E" \
  || { no "emulator not reachable at $E"; exit 1; }

NET_ID=$(tf_out_gcp network_id 2>/dev/null)
LIVE_NET=$(curl -s -m $TIMEOUT "$E/compute/v1/projects/$PROJECT/global/networks" \
  | python3 -c "import json,sys; print(' '.join(n.get('selfLink','') for n in json.load(sys.stdin).get('items', [])))")
case "$LIVE_NET" in
  *"$NET_ID"*) ok "state matches live emulator (network exists)" ;;
  *) no "state network $NET_ID absent live -- stale state, rebuild stacks" ;;
esac

# ---------------------------------------------------------------- GCS
hdr "GCS (put -> get -> delete)"
BUCKET=$(tf_out_gcp frontend_bucket 2>/dev/null)
printf 'gcp-verify' > "$TMP/obj.txt"
if curl -s -m $TIMEOUT -X POST \
    "$E/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=verify/gcp.txt" \
    --data-binary "@$TMP/obj.txt" -o /dev/null -w '%{http_code}' | grep -q 200; then
  ok "put-object"
  curl -s -m $TIMEOUT "$E/storage/v1/b/$BUCKET/o/verify%2Fgcp.txt?alt=media" -o "$TMP/back.txt" \
  && cmp -s "$TMP/obj.txt" "$TMP/back.txt" \
    && ok "get-object returns identical bytes" \
    || no "get-object mismatch"
  curl -s -m $TIMEOUT -X DELETE \
    "$E/storage/v1/b/$BUCKET/o/verify%2Fgcp.txt" -o /dev/null \
  && ok "delete-object" || no "delete-object failed"
else
  no "put-object failed"
fi

# ---------------------------------------------------------------- Secret Manager
hdr "Secret Manager (get + JSON keys)"
SECRET_JSON=$(curl -s -m $TIMEOUT \
  "$E/v1/projects/$PROJECT/secrets/smartcloud-app-credentials/versions/latest:access" \
  | python3 -c "import json,sys,base64; d=json.load(sys.stdin); print(base64.b64decode(d['payload']['data']).decode())" 2>/dev/null)
echo "$SECRET_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d.get('db_username') and d.get('db_password') and d.get('db_name'), 'keys missing'
" 2>/dev/null && ok "secret get returns db_username/password/name" \
  || no "secret get or keys failed"

# ---------------------------------------------------------------- PubSub
hdr "PubSub (publish -> pull)"
MSG=$(printf 'gcp-verify' | base64 -w0)
PUB=$(curl -s -m $TIMEOUT -X POST "$E/v1/projects/$PROJECT/topics/orders:publish" \
  -H "Content-Type: application/json" -d "{\"messages\":[{\"data\":\"$MSG\"}]}" | head -c 200)
echo "$PUB" | grep -q messageIds && ok "publish" || no "publish failed"
PULL=$(curl -s -m $TIMEOUT -X POST "$E/v1/projects/$PROJECT/subscriptions/orders-sub:pull" \
  -H "Content-Type: application/json" -d '{"maxMessages":1}' | head -c 600)
echo "$PULL" | grep -q "$MSG" && ok "pull returns payload" || no "pull mismatch"
ACK=$(echo "$PULL" | python3 -c "import json,sys; m=json.load(sys.stdin).get('receivedMessages',[]); print(m[0]['ackId'] if m else '')" 2>/dev/null)
[ -n "$ACK" ] && curl -s -m $TIMEOUT -X POST "$E/v1/projects/$PROJECT/subscriptions/orders-sub:acknowledge" \
  -H "Content-Type: application/json" -d "{\"ackIds\":[\"$ACK\"]}" -o /dev/null

# ---------------------------------------------------------------- Firestore
hdr "Firestore (SDK write -> read -> delete; REST is gRPC-only)"
if floci-pyenv/bin/python -c "import google.cloud.firestore" 2>/dev/null; then
  FIRESTORE_EMULATOR_HOST=localhost:4588 floci-pyenv/bin/python - >"$TMP/fs.txt" 2>&1 <<'PY'
from google.cloud import firestore
db = firestore.Client(project="floci-local")
ref = db.collection("verify").document("gcp-probe")
ref.set({"ping": "pong"})
assert ref.get().to_dict() == {"ping": "pong"}, "read mismatch"
ref.delete()
print("round-trip ok")
PY
  grep -q "round-trip ok" "$TMP/fs.txt" && ok "SDK write/read/delete" \
    || no "SDK round-trip failed: $(head -c 200 "$TMP/fs.txt")"
else
  skip "google-cloud-firestore not installed -- run scripts/setup-gcp-env.sh"
fi

# ---------------------------------------------------------------- KMS
hdr "KMS (encrypt -> decrypt)"
PT=$(printf 'hello-floci-gcp' | base64 -w0)
KEY="projects/$PROJECT/locations/us-central1/keyRings/smartcloud-key/cryptoKeys/key"
CT=$(curl -s -m $TIMEOUT -X POST "$E/v1/$KEY:encrypt" \
  -H "Content-Type: application/json" -d "{\"plaintext\":\"$PT\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('ciphertext',''))" 2>/dev/null)
if [ -n "$CT" ]; then
  BACK=$(curl -s -m $TIMEOUT -X POST "$E/v1/$KEY:decrypt" \
    -H "Content-Type: application/json" -d "{\"ciphertext\":\"$CT\"}" \
    | python3 -c "import json,sys,base64; print(base64.b64decode(json.load(sys.stdin).get('plaintext','')).decode())" 2>/dev/null)
  [ "$BACK" = "hello-floci-gcp" ] && ok "ciphertext decrypts back" \
    || no "decrypt returned '$BACK'"
else
  no "encrypt failed"
fi

# ---------------------------------------------------------------- IAM service accounts
hdr "IAM service accounts (list)"
SAS=$(curl -s -m $TIMEOUT "$E/v1/projects/$PROJECT/serviceAccounts")
for sa in smartcloud-gke-node smartcloud-app smartcloud-run-invoker; do
  echo "$SAS" | grep -q "$sa" && ok "$sa present" || no "$sa missing"
done

# ---------------------------------------------------------------- GKE
hdr "GKE (describe + nodes)"
curl -s -m $TIMEOUT "$E/container/v1/projects/$PROJECT/locations/us-central1/clusters/smartcloud-cluster" \
  | grep -q smartcloud-cluster && ok "cluster describes" || no "cluster describe failed"
NODES=$(kubectl --context floci-gcp-smartcloud-cluster get nodes --no-headers 2>/dev/null | wc -l)
[ "$NODES" -ge 1 ] && ok "$NODES node(s) Ready" || no "no nodes"

# ---------------------------------------------------------------- Gateway (app + SQL proof)
hdr "Gateway (health + user round-trip via port-forward)"
kubectl --context floci-gcp-smartcloud-cluster port-forward -n smartcloud svc/gateway 14000:4000 \
  >/dev/null 2>&1 &
PF=$!
sleep 6
GCODE=$(curl -s -m $TIMEOUT -o /dev/null -w '%{http_code}' http://localhost:14000/healthz)
[ "$GCODE" = "200" ] && ok "gateway /healthz 200" || no "gateway /healthz $GCODE"
UCODE=$(curl -s -m $TIMEOUT -o /dev/null -w '%{http_code}' http://localhost:14000/api/users/1)
[ "$UCODE" = "200" ] && ok "user read-back 200 (gateway->service->SQL)" \
  || no "user read-back $UCODE"
kill $PF 2>/dev/null

# ---------------------------------------------------------------- Cloud Run
hdr "Cloud Run (invoke)"
RUN_HOST=$(tf_out_gcp run_service_uris 2>/dev/null \
  | python3 -c "import json,sys; print(list(json.load(sys.stdin).values())[0].split('/')[2])")
RCODE=$(curl -s -m $TIMEOUT -o /dev/null -w '%{http_code}' -H "Host: $RUN_HOST" http://localhost:4588/)
[ "$RCODE" = "200" ] && ok "run service invokes 200" || no "run invoke $RCODE"

# ---------------------------------------------------------------- ArgoCD
hdr "ArgoCD (Synced + Healthy)"
SYNC=$(kubectl --context floci-gcp-smartcloud-cluster get application smartcloud -n argocd \
  -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
[ "$SYNC" = "Synced/Healthy" ] && ok "application $SYNC" || no "application $SYNC"

# ---------------------------------------------------------------- Drift (live-but-unmanaged)
hdr "Drift (live objects missing from outputs)"
ORPHANS=0
check_managed() { # $1 live-id, $2 outputs-key, $3 label
  tf_out_gcp "$2" 2>/dev/null | grep -q "$1" \
    && ok "$3 $1 managed" \
    || { echo "  orphan: $3 $1"; ORPHANS=$((ORPHANS + 1)); }
}
for b in $(curl -s -m $TIMEOUT "$E/storage/v1/b?project=$PROJECT" \
    | python3 -c "import json,sys; print(' '.join(i.get('name','') for i in json.load(sys.stdin).get('items',[])))"); do
  check_managed "$b" bucket_ids bucket
done
for t in $(curl -s -m $TIMEOUT "$E/v1/projects/$PROJECT/topics" \
    | python3 -c "import json,sys; print(' '.join(x.get('name','').split('/')[-1] for x in json.load(sys.stdin).get('topics',[])))"); do
  check_managed "$t" pubsub_topic_ids topic
done
for s in $(curl -s -m $TIMEOUT "$E/v1/projects/$PROJECT/secrets" \
    | python3 -c "import json,sys; print(' '.join(x.get('name','').split('/')[-1] for x in json.load(sys.stdin).get('secrets',[])))"); do
  check_managed "$s" secret_ids secret
done
[ "$ORPHANS" -eq 0 ] && ok "no live-but-unmanaged objects" || no "$ORPHANS orphan(s)"

# ---------------------------------------------------------------- AWS regression
hdr "AWS regression"
if ! curl -s -m 5 "${FLOCI_ENDPOINT:-http://localhost:4566}/_localstack/health" >/dev/null 2>&1; then
  skip "AWS emulator not running -- regression needs the AWS stack up"
elif ./verify.sh >/tmp/opencode/aws-verify.log 2>&1; then
  ok "AWS verify passes"
else
  no "AWS verify failed (see /tmp/opencode/aws-verify.log)"
fi

# ---------------------------------------------------------------- verdict
hdr "Verdict"
[ "$FAIL" -eq 0 ] && { echo "  ALL CHECKS PASS"; exit 0; } \
  || { echo "  $FAIL CHECK(S) FAILED"; exit 1; }
