#!/usr/bin/env bash
#------------------------------------------------------------------
# GCP stack output access for the demo scripts.
#------------------------------------------------------------------
# Splitting one root module into four Terragrunt stacks means there is no
# single `terraform output` any more. This merges all four into one flat
# .outputs-gcp.json and exposes tf_out_gcp() so the scripts keep reading
# values by name. Mirrors scripts/lib/outputs.sh for the AWS tree.
#
# Usage:
#   source scripts/lib/outputs-gcp.sh   # then: tf_out_gcp cluster_names
#   ./scripts/lib/outputs-gcp.sh --refresh # rebuild the cache
#   ./scripts/lib/outputs-gcp.sh NAME   # print one value
#------------------------------------------------------------------

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TG_ROOT="$(cd "$_LIB_DIR/../.." && pwd)"
OUTPUTS_JSON="$TG_ROOT/.outputs-gcp.json"
STACKS=(bootstrap iam stateful standard)

tg_refresh_outputs_gcp() {
  local tmp merged=()
  tmp="$(mktemp -d)"

  for s in "${STACKS[@]}"; do
    terragrunt output -json --non-interactive \
      --working-dir "$TG_ROOT/terragrunt/gcp/${s}" >"$tmp/${s}.json" 2>/dev/null || echo '{}' >"$tmp/${s}.json"
    merged+=("$tmp/${s}.json")
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
tf_out_gcp() {
  [ -f "$OUTPUTS_JSON" ] || tg_refresh_outputs_gcp
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
    --refresh|"") tg_refresh_outputs_gcp ;;
    *)            tf_out_gcp "$1" ;;
  esac
fi
