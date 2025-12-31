#!/usr/bin/env bash
set -euo pipefail

NS="confidential"
FILE="$HOME/nginx-unprivileged.yaml"

echo "== Q13 Cleanup/Reset =="

kubectl delete ns "$NS" --ignore-not-found

rm -f "$FILE" 2>/dev/null || true

echo "✅ Q13 cleaned."
