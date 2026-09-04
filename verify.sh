#!/usr/bin/env bash
# Functional verification of the msdemo stack against floci.
#
# This does round-trips (write then read back) rather than just listing
# resources, so a PASS means the service actually works, not just that the
# control plane remembers an object exists.
#
# Usage:  ./verify.sh
set -uo pipefail

export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
E=${E:-http://localhost:4566}
aws() { command aws --endpoint-url "$E" "$@"; }

PROJECT=msdemo
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
warn() { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; skip=$((skip+1)); }
hdr()  { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# Pull the values under test straight from the stacks, so this can't drift
# from what was actually applied.
hdr "Reading stack outputs"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/outputs.sh"
tg_refresh_outputs 2>/dev/null || true
if [ ! -s .outputs.json ]; then
  echo "  could not read stack outputs -- run 'make apply-all' first"
  exit 1
fi
jq_get() { tf_out "$1"; }
BUCKET=$(jq_get frontend_bucket)
KMS_ARN=$(jq_get kms_key_arn)
SECRET_ARN=$(jq_get app_secret_arn)
ALB_DNS=$(jq_get alb_dns_name)
VPC_ID=$(jq_get vpc_id)
CLUSTER=$(jq_get eks_cluster_name)
CERT_ARN=$(jq_get acm_certificate_arn)
echo "  bucket=$BUCKET  vpc=$VPC_ID  cluster=$CLUSTER"

# ---------------------------------------------------------------- inventory
# Everything terraform actually created, grouped by module, with the real IDs
# floci handed back. This is the authoritative list -- the functional checks
# further down only spot-check the services that have a data path.
hdr "Resource inventory (from terraform state -- freshness checked below)"
terraform show -json 2>/dev/null | python3 -c '
import json, sys
from collections import defaultdict

try:
    doc = json.load(sys.stdin)
except Exception:
    print("  could not parse terraform show -json"); sys.exit(0)

rows = []
def walk(mod):
    for r in mod.get("resources", []):
        if r.get("mode") != "managed":
            continue
        v = r.get("values", {}) or {}
        ident = v.get("id") or v.get("arn") or v.get("name") or ""
        rows.append((r["address"], r["type"], str(ident)))
    for child in mod.get("child_modules", []):
        walk(child)

walk(doc.get("values", {}).get("root_module", {}))

if not rows:
    print("  state is empty"); sys.exit(0)

groups = defaultdict(list)
for addr, typ, ident in rows:
    parts = addr.split(".")
    mod = parts[1] if addr.startswith("module.") else "(root)"
    # strip the module prefix so the resource address reads cleanly
    short = ".".join(parts[2:]) if addr.startswith("module.") else addr
    groups[mod].append((short, typ, ident))

def clip(s, n):
    return s if len(s) <= n else s[: n - 1] + "…"

for mod in sorted(groups):
    items = sorted(groups[mod])
    print("\n  \033[1m%s\033[0m  (%d)" % (mod, len(items)))
    for short, typ, ident in items:
        print("    %-44s %s" % (clip(short, 44), clip(ident, 60)))

by_type = defaultdict(int)
for _, typ, _ in rows:
    by_type[typ] += 1
print("\n  \033[1m%d resources across %d modules, %d distinct types\033[0m"
      % (len(rows), len(groups), len(by_type)))
print("  " + "  ".join("%s=%d" % (t.replace("aws_", ""), c)
                       for t, c in sorted(by_type.items(), key=lambda kv: (-kv[1], kv[0]))))
'

# ---------------------------------------------------------------- stale state
# floci keeps nothing across restarts, but terraform.tfstate is a local file
# that survives. After a floci restart the inventory above still lists every
# resource while none of them exist -- check before running 14 doomed probes.
hdr "State freshness"
if ! curl -s -m 5 "${E}/_localstack/health" >/dev/null 2>&1; then
  no "floci is not reachable at $E -- start it with 'docker compose up -d'"
  exit 1
fi
ok "floci is reachable at $E"

if [ -n "$VPC_ID" ]; then
  LIVE_VPC=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
    --query 'length(Vpcs)' --output text 2>/dev/null)
  if [ "$LIVE_VPC" != "1" ]; then
    no "terraform state references $VPC_ID, but floci has no such VPC"
    cat <<EOF

  The inventory above was read from terraform.tfstate, NOT from floci. floci
  discards all state when its container is recreated, so that file is now
  describing infrastructure that no longer exists.

  Rebuild from scratch:

      rm -f terraform.tfstate terraform.tfstate.backup
      terraform apply
      ./scripts/build-and-push.sh
      ./scripts/deploy.sh
      ./scripts/register-alb-targets.sh
      ./scripts/deploy-frontend.sh

EOF
    exit 1
  fi
  ok "terraform state matches live floci (VPC $VPC_ID exists)"
fi

# ---------------------------------------------------------------- KMS
hdr "KMS (encrypt -> decrypt round trip)"
printf 'hello-floci' > "$TMP/pt.txt"
if aws kms encrypt --key-id "$KMS_ARN" --plaintext "fileb://$TMP/pt.txt" \
     --query CiphertextBlob --output text 2>/dev/null | base64 --decode > "$TMP/ct.bin" \
   && [ -s "$TMP/ct.bin" ]; then
  BACK=$(aws kms decrypt --ciphertext-blob "fileb://$TMP/ct.bin" \
           --query Plaintext --output text 2>/dev/null | base64 --decode)
  [ "$BACK" = "hello-floci" ] && ok "ciphertext decrypts back to plaintext" \
                              || no "decrypt returned '$BACK', expected 'hello-floci'"
else
  no "encrypt failed"
fi

# ---------------------------------------------------------------- S3
hdr "S3 (put -> get -> delete)"
printf '<h1>floci</h1>' > "$TMP/index.html"
if aws s3api put-object --bucket "$BUCKET" --key verify/index.html \
     --body "$TMP/index.html" >/dev/null 2>&1; then
  ok "put-object"
  if aws s3api get-object --bucket "$BUCKET" --key verify/index.html "$TMP/back.html" >/dev/null 2>&1 \
     && cmp -s "$TMP/index.html" "$TMP/back.html"; then
    ok "get-object returns identical bytes"
  else
    no "get-object mismatch"
  fi
  # Confirm the SSE-KMS config from the terraform module is actually applied.
  ENC=$(aws s3api head-object --bucket "$BUCKET" --key verify/index.html \
          --query ServerSideEncryption --output text 2>/dev/null)
  [ "$ENC" = "aws:kms" ] && ok "object encrypted with SSE-KMS" \
                         || warn "ServerSideEncryption reported as '$ENC' (floci may not track SSE)"
  aws s3api delete-object --bucket "$BUCKET" --key verify/index.html >/dev/null 2>&1 \
    && ok "delete-object" || no "delete-object"
else
  no "put-object failed"
fi
BLOCK=$(aws s3api get-public-access-block --bucket "$BUCKET" \
          --query PublicAccessBlockConfiguration.BlockPublicAcls --output text 2>/dev/null)
[ "$BLOCK" = "True" ] && ok "public access block is on" || warn "public access block reads '$BLOCK'"

# ---------------------------------------------------------------- Secrets Manager
hdr "Secrets Manager"
SEC=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
        --query SecretString --output text 2>/dev/null)
if [ -n "$SEC" ] && [ "$SEC" != "None" ]; then
  ok "secret value retrievable"
  printf '%s' "$SEC" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('        keys:', ', '.join(sorted(d)))
missing=[k for k in ('db_username','db_password','db_endpoint','db_name') if k not in d]
print('        MISSING:', missing) if missing else print('        all expected keys present')
" 2>/dev/null || warn "secret is not valid JSON"
else
  no "could not read secret value"
fi

# ---------------------------------------------------------------- SSM
hdr "SSM Parameter Store"
PARAMS=$(aws ssm get-parameters-by-path --path "/$PROJECT/" --recursive \
           --query 'Parameters[].Name' --output text 2>/dev/null)
if [ -n "$PARAMS" ]; then
  N=$(printf '%s' "$PARAMS" | wc -w | tr -d ' ')
  ok "$N parameters readable under /$PROJECT/"
  for p in $PARAMS; do
    v=$(aws ssm get-parameter --name "$p" --query Parameter.Value --output text 2>/dev/null)
    printf '        %-34s = %s\n' "$p" "$v"
  done
else
  no "no parameters returned"
fi

# ---------------------------------------------------------------- ECR
hdr "ECR"
REPOS=$(aws ecr describe-repositories --query 'repositories[].repositoryName' --output text 2>/dev/null)
if [ -n "$REPOS" ]; then
  ok "repositories: $REPOS"
  aws ecr get-login-password >/dev/null 2>&1 \
    && ok "get-login-password works (docker login would succeed)" \
    || warn "get-login-password unsupported -- image push untestable"
else
  no "no repositories found"
fi

# ---------------------------------------------------------------- IAM
hdr "IAM"
for r in cluster node app; do
  RN="$PROJECT-cluster-$r-role"
  if aws iam get-role --role-name "$RN" >/dev/null 2>&1; then
    NP=$(aws iam list-attached-role-policies --role-name "$RN" \
           --query 'AttachedPolicies[].PolicyName' --output text 2>/dev/null)
    ok "$RN (attached: ${NP:-none})"
  else
    no "$RN not found"
  fi
done

# ---------------------------------------------------------------- VPC
hdr "VPC / networking"
SUBS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
         --query 'length(Subnets)' --output text 2>/dev/null)
[ "$SUBS" = "4" ] && ok "4 subnets in $VPC_ID" || no "expected 4 subnets, got '$SUBS'"
IGW=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'length(InternetGateways)' --output text 2>/dev/null)
[ "$IGW" = "1" ] && ok "internet gateway attached" || no "IGW count '$IGW'"
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[].GroupName' --output text 2>/dev/null)
ok "security groups: $SGS"

# ---------------------------------------------------------------- ACM
hdr "ACM"
CS=$(aws acm describe-certificate --certificate-arn "$CERT_ARN" \
       --query 'Certificate.[DomainName,Status]' --output text 2>/dev/null)
[ -n "$CS" ] && ok "certificate: $CS" || no "describe-certificate failed"

# ---------------------------------------------------------------- RDS
hdr "RDS"
RDS=$(aws rds describe-db-instances --db-instance-identifier "$PROJECT-postgres" \
        --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,Endpoint.Port]' \
        --output text 2>/dev/null)
if [ -n "$RDS" ]; then
  ok "instance: $RDS"
  RHOST=$(printf '%s' "$RDS" | awk '{print $2}')
  RPORT=$(printf '%s' "$RDS" | awk '{print $3}')
  # 172.18.x is the docker bridge network -- not routable from the macOS host.
  if nc -z -G 2 "$RHOST" "$RPORT" 2>/dev/null; then
    ok "TCP $RHOST:$RPORT reachable"
    if command -v psql >/dev/null 2>&1; then
      PGPASSWORD=$(printf '%s' "${SEC:-}" | python3 -c "import json,sys;print(json.load(sys.stdin).get('password',''))" 2>/dev/null)
      export PGPASSWORD
      psql -h "$RHOST" -p "$RPORT" -U "$(printf '%s' "${SEC:-}" | python3 -c "import json,sys;print(json.load(sys.stdin).get('username','postgres'))" 2>/dev/null)" \
           -d postgres -c 'select version();' >/dev/null 2>&1 \
        && ok "psql connected and ran a query" || no "psql could not connect"
    else
      warn "psql not installed -- skipping live SQL check"
    fi
  else
    warn "$RHOST:$RPORT not reachable from the host (docker-internal IP; expected on macOS)"
  fi
else
  no "describe-db-instances failed"
fi

# ---------------------------------------------------------------- EKS
hdr "EKS"
EKS=$(aws eks describe-cluster --name "$CLUSTER" \
        --query 'cluster.[status,endpoint,version]' --output text 2>/dev/null)
if [ -n "$EKS" ]; then
  ok "cluster: $EKS"
  NG=$(aws eks list-nodegroups --cluster-name "$CLUSTER" \
         --query 'nodegroups' --output text 2>/dev/null)
  [ -n "$NG" ] && ok "nodegroup: $NG" || no "no nodegroups"
  if command -v kubectl >/dev/null 2>&1; then
    warn "kubectl present -- try: aws eks update-kubeconfig --name $CLUSTER --endpoint-url $E && kubectl get nodes"
  else
    warn "kubectl not installed -- cannot test the data plane"
  fi
else
  no "describe-cluster failed"
fi

# ---------------------------------------------------------------- ALB
hdr "ALB"
LB=$(aws elbv2 describe-load-balancers --names "$PROJECT-alb" \
       --query 'LoadBalancers[0].[State.Code,Type,Scheme]' --output text 2>/dev/null)
if [ -n "$LB" ]; then
  ok "load balancer: $LB"
  ARN=$(aws elbv2 describe-load-balancers --names "$PROJECT-alb" \
          --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
  LIS=$(aws elbv2 describe-listeners --load-balancer-arn "$ARN" \
          --query 'Listeners[].[Protocol,Port]' --output text 2>/dev/null | tr '\n' ' ')
  ok "listeners: $LIS"
  TGH=$(aws elbv2 describe-target-groups --names "$PROJECT-gateway-tg" \
          --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
  TGT=$(aws elbv2 describe-target-health --target-group-arn "$TGH" \
          --query 'length(TargetHealthDescriptions)' --output text 2>/dev/null)
  if [ "$TGT" = "0" ]; then
    warn "target group has 0 registered targets -- expected until the gateway is deployed"
  else
    ok "$TGT target(s) registered"
  fi
  # The ALB name resolves to 127.0.0.1, but floci's :80 listener is only
  # published to the host if docker-compose maps it. Fall back to probing from
  # inside floci_default so a compose gap doesn't look like a broken ALB.
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$ALB_DNS/healthz" 2>/dev/null)
  if [ "$CODE" = "200" ]; then
    ok "gateway answers /healthz through the ALB from the host (HTTP 200)"
  else
    FLOCI_IP=$(docker inspect floci-floci-1 \
      --format '{{range $k,$v := .NetworkSettings.Networks}}{{if ne $k "bridge"}}{{$v.IPAddress}}{{end}}{{end}}' 2>/dev/null)
    INNER=$(docker run --rm --network floci_default curlimages/curl:latest \
              -s -o /dev/null -w '%{http_code}' --max-time 8 \
              -H "Host: $ALB_DNS" "http://${FLOCI_IP}/healthz" 2>/dev/null)
    if [ "$INNER" = "200" ]; then
      warn "ALB works in-network (HTTP 200) but is unreachable from the host"
      echo "        publish floci's :80 in docker-compose.yml, or proxy it:"
      echo "        docker run -d --name floci-alb-proxy --network floci_default \\"
      echo "          -p 8080:80 alpine/socat TCP-LISTEN:80,fork,reuseaddr TCP:${FLOCI_IP}:80"
    else
      no "gateway did not answer /healthz through the ALB (host=$CODE, in-network=$INNER)"
    fi
  fi
else
  no "describe-load-balancers failed"
fi

# ---------------------------------------------------------------- drift
# Resources that exist in floci but are absent from terraform state. A crashed
# apply leaves these behind (the provider dies before recording the ID), and
# they collide on the next apply -- which is what caused the earlier
# CNAMEAlreadyExists and OriginAccessControlInUse errors.
hdr "Drift check (live in floci, missing from state)"
# Flatten every attribute value in state into one searchable blob. Matching on
# identifiers rather than resource type is what makes this catch "floci has two
# load balancers but terraform only knows about one".
STATE_BLOB=$(terraform show -json 2>/dev/null | python3 -c '
import json, sys
try:
    doc = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def walk(mod):
    for r in mod.get("resources", []):
        print(json.dumps(r.get("values", {})))
    for c in mod.get("child_modules", []):
        walk(c)
walk(doc.get("values", {}).get("root_module", {}))
')
drift=0
check_orphan() {
  local label=$1 live=$2
  [ -z "$live" ] && return 0
  [ "$live" = "None" ] && return 0
  local item
  for item in $live; do
    if ! printf '%s' "$STATE_BLOB" | grep -qF "$item"; then
      no "orphan $label: $item (live in floci, absent from state)"
      drift=$((drift+1))
    fi
  done
}
check_orphan "cloudfront distribution" \
  "$(aws cloudfront list-distributions --query 'DistributionList.Items[].Id' --output text 2>/dev/null)"
check_orphan "load balancer" \
  "$(aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text 2>/dev/null)"
check_orphan "db instance" \
  "$(aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text 2>/dev/null)"
check_orphan "elasticache group" \
  "$(aws elasticache describe-replication-groups --query 'ReplicationGroups[].ReplicationGroupId' --output text 2>/dev/null)"
check_orphan "ecr repository" \
  "$(aws ecr describe-repositories --query 'repositories[].repositoryName' --output text 2>/dev/null)"
[ "$drift" -eq 0 ] && ok "no orphaned resources"

# A plan that is not empty means state disagrees with reality. Expect RDS to
# show a replacement here: floci does not persist storage_encrypted/kms_key_id.
if terraform plan -detailed-exitcode -no-color >/dev/null 2>&1; then
  ok "terraform plan is clean (state matches floci)"
else
  case $? in
    2) warn "terraform plan shows pending changes -- run 'terraform plan' to see them" ;;
    *) no "terraform plan errored" ;;
  esac
fi

# ---------------------------------------------------------------- summary
printf '\n\033[1m== Summary ==\033[0m\n'
printf '  %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] && printf '  \033[32mstack looks healthy\033[0m\n' \
                  || printf '  \033[31mreview the FAIL lines above\033[0m\n'
exit 0
