#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Cleanup / Reset v2 =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
SPDX="$HOME/alpine.spdx"
STATE_FILE="/root/.q12_target"

kubectl -n "$NS" delete deploy alpine --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns "$NS" --ignore-not-found >/dev/null 2>&1 || true

rm -f "$MANIFEST" "$SPDX" "$STATE_FILE" >/dev/null 2>&1 || true

echo "✅ Cleanup complete."
