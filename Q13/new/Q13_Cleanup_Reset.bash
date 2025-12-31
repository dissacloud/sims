#!/usr/bin/env bash
set -euo pipefail

echo "== Q13 Cleanup/Reset =="

NS="confidential"
MANIFEST="$HOME/nginx-unprivileged.yaml"

kubectl -n "$NS" delete deploy nginx-unprivileged --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns "$NS" --ignore-not-found >/dev/null 2>&1 || true

if [[ -f "$MANIFEST" ]]; then
  rm -f "$MANIFEST"
fi

echo "✅ Cleanup complete."
