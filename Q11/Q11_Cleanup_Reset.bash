#!/usr/bin/env bash
# Q11 Cleanup / Reset — CONTROLPLANE
# Removes the Q11 fixture and baseline files.

set -euo pipefail

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
k(){ KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl "$@"; }

echo "🧹 Q11 Cleanup / Reset"

if k get ns q11-fixture >/dev/null 2>&1; then
  k delete ns q11-fixture --wait=false >/dev/null 2>&1 || true
  echo "✅ Deleted namespace q11-fixture (async)"
else
  echo "ℹ️ Namespace q11-fixture not present"
fi

rm -rf /root/.q11 || true
echo "✅ Removed baseline directory /root/.q11"

echo "Done."
