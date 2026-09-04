#!/usr/bin/env bash
# Injects the live ALB DNS name into the frontend, then syncs it to S3.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLOCI_ENDPOINT=${FLOCI_ENDPOINT:-http://localhost:4566}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

aws() { command aws --endpoint-url "$FLOCI_ENDPOINT" "$@"; }

# Null-safe: cloudfront_domain_name is null while that module is disabled.
# Stack outputs come from four Terragrunt states now, merged by this helper.
# tf_out() is already null-safe: a disabled module yields an empty string.
source "$(dirname "${BASH_SOURCE[0]}")/lib/outputs.sh"

BUCKET=$(tf_out frontend_bucket)
ALB_DNS=$(tf_out alb_dns_name)
CF_DOMAIN=$(tf_out cloudfront_domain_name)

if [ -z "$BUCKET" ] || [ -z "$ALB_DNS" ]; then
  echo "frontend_bucket or alb_dns_name is empty -- has terraform apply run?" >&2
  exit 1
fi

echo "=== Wiring GATEWAY_URL=http://${ALB_DNS} into the frontend ==="
mkdir -p dist

# ALB_DNS is passed through the environment rather than interpolated into the
# heredoc, so a value containing quotes can't break out of the generated JS.
GATEWAY_URL="http://${ALB_DNS}" python3 <<'PYEOF'
import json
import os

gateway_url = os.environ["GATEWAY_URL"]
with open("services/frontend/index.html") as f:
    page = f.read()

# json.dumps produces a correctly escaped JS string literal; escaping "</"
# additionally stops a crafted value from closing the <script> element early.
literal = json.dumps(gateway_url).replace("</", "<\\/")
tag = f"<script>window.GATEWAY_URL = {literal};</script>"
if "</head>" not in page:
    raise SystemExit("services/frontend/index.html has no </head> to inject into")

with open("dist/index.html", "w") as f:
    f.write(page.replace("</head>", tag + "\n</head>", 1))
PYEOF

echo "=== Syncing to s3://${BUCKET} ==="
aws s3 cp dist/index.html "s3://${BUCKET}/index.html" --content-type text/html

echo ""
echo "Frontend deployed. Gateway URL wired to: http://${ALB_DNS}"
if [ -n "$CF_DOMAIN" ]; then
  echo "CloudFront domain: ${CF_DOMAIN}"
else
  echo "CloudFront: disabled (enable_cloudfront=false) -- reach the object directly:"
  echo "  ${FLOCI_ENDPOINT}/${BUCKET}/index.html"
fi
