#!/usr/bin/env bash
#------------------------------------------------------------------
# Pin AWS credentials into the kubeconfig's exec block.
#------------------------------------------------------------------
# `aws eks update-kubeconfig` writes an exec-based user entry:
#
#   exec:
#     command: aws
#     args: [--region, us-east-1, eks, get-token, --cluster-name, ...]
#
# `aws eks get-token` signs an STS request offline and never calls AWS, so it
# works fine against floci -- but it still needs credentials in its own
# environment. Anything that does not inherit your shell fails:
#
#   * GUI clients (Lens, k9s launched from Finder, IDE plugins) report
#       (NoCredentials) Unable to locate credentials
#       exec: executable aws failed with exit code 253
#   * the Terraform kubernetes/helm providers, which spawn `aws` themselves
#
# Pinning the (throwaway) credentials into the exec block fixes both at once.
#
# Idempotent; run it after every `aws eks update-kubeconfig`.
#------------------------------------------------------------------
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
CLUSTER_NAME="${1:-smartcloud-cluster}"

AWS_KEY="${AWS_ACCESS_KEY_ID:-test}"
AWS_SECRET="${AWS_SECRET_ACCESS_KEY:-test}"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

[ -f "$KUBECONFIG_PATH" ] || { echo "no kubeconfig at $KUBECONFIG_PATH" >&2; exit 1; }

cp "$KUBECONFIG_PATH" "${KUBECONFIG_PATH}.bak"

python3 - "$KUBECONFIG_PATH" "$CLUSTER_NAME" "$AWS_KEY" "$AWS_SECRET" "$AWS_REGION" <<'PY'
import re, sys

path, cluster, key, secret, region = sys.argv[1:6]
src = open(path).read()

# Matched textually rather than with a YAML library: pyyaml is not installed
# by default on macOS and this script should need no pip install.
pattern = re.compile(
    r'(- name: arn:aws:eks:[^\n]*cluster/' + re.escape(cluster) + r'\n'
    r'  user:\n'
    r'    exec:\n'
    r'(?:      [^\n]*\n|      - [^\n]*\n|        [^\n]*\n)*)',
    re.M,
)

m = pattern.search(src)
if not m:
    print(f"  no exec-based user entry for {cluster}; nothing to do")
    sys.exit(0)

block = m.group(1)

# Strip any env: we previously inserted, so re-runs stay idempotent.
stripped = re.sub(
    r'      env:\n(?:      - name: [^\n]*\n        value: [^\n]*\n)+',
    '', block)

env_yaml = (
    "      env:\n"
    f"      - name: AWS_ACCESS_KEY_ID\n        value: {key}\n"
    f"      - name: AWS_SECRET_ACCESS_KEY\n        value: {secret}\n"
    f"      - name: AWS_DEFAULT_REGION\n        value: {region}\n"
)

# Insert immediately after `exec:` so indentation stays valid.
updated = stripped.replace("    exec:\n", "    exec:\n" + env_yaml, 1)

if updated == block:
    print("  kubeconfig already pinned; no change")
else:
    open(path, 'w').write(src.replace(block, updated, 1))
    print(f"  pinned AWS_* into the exec block for {cluster}")
PY

echo "  backup: ${KUBECONFIG_PATH}.bak"
