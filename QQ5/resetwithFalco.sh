#!/usr/bin/env bash
set -euo pipefail

echo "[reset-no-falco] Removing sim resources in namespace 'ollama'..."

# Delete the namespace (removes all sim objects inside)
if kubectl get ns ollama >/dev/null 2>&1; then
  kubectl delete ns ollama --wait=true
else
  echo "[reset-no-falco] Namespace 'ollama' not found (nothing to delete)."
fi

echo "[reset-no-falco] Done."

