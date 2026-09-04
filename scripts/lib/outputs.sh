#!/usr/bin/env bash
#------------------------------------------------------------------
# Stack output access for the demo scripts.
#------------------------------------------------------------------
# Splitting one root module into four Terragrunt stacks means there is no
# single `terraform output` any more. This merges all four into one flat
# .outputs.json and exposes tf_out() so the scripts keep reading values by
# name, exactly as they did before.
#
# Usage:
#   source scripts/lib/outputs.sh      # then: tf_out alb_dns_name
#   ./scripts/lib/outputs.sh --refresh # rebuild the cache
#   ./scripts/lib/outputs.sh NAME      # print one value
#------------------------------------------------------------------

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TG_ROOT="$(cd "$_LIB_DIR/../.." && pwd)"
OUTPUTS_JSON="$TG_ROOT/.outputs.json"
STACKS=(bootstrap iam stateful standard)

export TG_TF_PATH="${TG_TF_PATH:-terraform}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

tg_refresh_outputs() {
  local tmp merged=()
  tmp="$(mktemp -d)"

  for s in "${STACKS[@]}"; do
    terragrunt output -json --non-interactive \
      --working-dir "$TG_ROOT/terragrunt/aws/$s" >"$tmp/$s.json" 2>/dev/null || echo '{}' >"$tmp/$s.json"
    merged+=("$tmp/$s.json")
  done

  python3 - "$OUTPUTS_JSON" "${merged[@]}" <<'PY'
import json, sys

dest, files = sys.argv[1], sys.argv[2:]
flat = {}
for f in files:
    try:
        with open(f) as fh:
            doc = json.load(fh)
    except Exception:
        continue
    # `terraform output -json` wraps each value as {"value":..., "type":...}
    for k, v in doc.items():
        flat[k] = v.get("value") if isinstance(v, dict) and "value" in v else v

with open(dest, "w") as fh:
    json.dump(flat, fh, indent=2)
print(f"  {len(flat)} outputs merged from {len(files)} stacks", file=sys.stderr)
PY
  rm -rf "$tmp"
}

# Print one output. Scalars print bare; maps and lists print as JSON, so the
# callers that pipe into python3 keep working unchanged.
tf_out() {
  [ -f "$OUTPUTS_JSON" ] || tg_refresh_outputs
  python3 -c "
import json, sys
try:
    v = json.load(open('$OUTPUTS_JSON')).get('$1')
except Exception:
    v = None
if v is None:
    print('')
elif isinstance(v, str):
    print(v)
else:
    print(json.dumps(v))
"
}

# Direct invocation
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --refresh|"") tg_refresh_outputs ;;
    *)            tf_out "$1" ;;
  esac
fi
