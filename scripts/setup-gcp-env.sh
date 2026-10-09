#!/usr/bin/env bash
# Provisions floci-pyenv with the GCP script prerequisites.
# Idempotent; safe to re-run. Runnable from anywhere.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PYENV="$PWD/floci-pyenv"
if [ ! -x "$PYENV/bin/python" ]; then
  echo "=== Creating floci-pyenv ==="
  python3 -m venv "$PYENV"
fi

echo "=== Installing scripts/requirements-gcp.txt into floci-pyenv ==="
"$PYENV/bin/pip" install -q -r scripts/requirements-gcp.txt

echo "=== Verifying ==="
"$PYENV/bin/python" -c "import google.cloud.firestore; print('  firestore client ready')"
