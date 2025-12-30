#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Cleanup / Reset v4 =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
SPDX="$HOME/alpine.spdx"
STATE_FILE="/root/.q12_target_version"

kubectl -n "$NS" delete deploy alpine --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns "$NS" --ignore-not-found >/dev/null 2>&1 || true

rm -f "$MANIFEST" "$SPDX" >/dev/null 2>&1 || true
rm -f "$STATE_FILE" >/dev/null 2>&1 || true

if command -v docker >/dev/null 2>&1; then
  docker image rm -f q12-alpine:target q12-alpine:alt1 q12-alpine:alt2 >/dev/null 2>&1 || true
elif command -v nerdctl >/dev/null 2>&1; then
  nerdctl image rm -f q12-alpine:target q12-alpine:alt1 q12-alpine:alt2 >/dev/null 2>&1 || true
fi

echo "✅ Cleanup complete."
