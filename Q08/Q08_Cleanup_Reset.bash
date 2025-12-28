#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Q08 Cleanup/Reset"

# Delete the two NetworkPolicies if they exist
kubectl -n prod delete netpol deny-policy --ignore-not-found >/dev/null
kubectl -n data delete netpol allow-from-prod --ignore-not-found >/dev/null

# Remove sim namespaces/resources (only those created for this sim)
# We labelled namespaces with cis-q08=true; delete those namespaces.
for ns in prod data dev; do
  if kubectl get ns "${ns}" -o jsonpath='{.metadata.labels.cis-q08}' 2>/dev/null | grep -qx "true"; then
    echo "Deleting namespace ${ns} (cis-q08=true) ..."
    kubectl delete ns "${ns}" --ignore-not-found >/dev/null
  else
    echo "Skipping namespace ${ns} (not labelled cis-q08=true)"
  fi
done

echo "✅ Cleanup complete."
