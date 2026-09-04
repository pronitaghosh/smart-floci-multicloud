#!/usr/bin/env bash
# Superseded by the Makefile. Kept as a shim so muscle memory and older docs
# keep working.
#
# The stale-state reconciliation this script used to do is gone: state now
# lives under .state/<environment>/<stack>/ per Terragrunt stack, and
# `make up` is idempotent.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "scripts/rebuild-all.sh is deprecated -- use the Makefile:"
echo ""
echo "  make up        # apply all four stacks, then build, deploy, register, frontend"
echo "  make plan-all  # plan every stack"
echo "  make help      # everything else"
echo ""
echo "Running 'make up' for you..."
exec make up
