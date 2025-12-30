#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Cleanup/Reset =="

NS="alpine"
DEP="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
SPDX_OUT="$HOME/alpine.spdx"

echo "[1] Deleting deployment (if present)..."
kubectl -n "$NS" delete deploy "$DEP" --ignore-not-found || true

echo "[2] Deleting namespace (if present)..."
kubectl delete ns "$NS" --ignore-not-found || true

echo "[3] Removing local files..."
rm -f "$MANIFEST" "$SPDX_OUT" || true

# Optional: remove bom wrapper (keep syft unless you want to remove it manually)
if [[ "${REMOVE_BOM_WRAPPER:-false}" == "true" ]]; then
  echo "[4] Removing bom wrapper (/usr/local/bin/bom)..."
  sudo rm -f /usr/local/bin/bom || true
fi

echo "✅ Q12 cleanup complete."
