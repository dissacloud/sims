#!/usr/bin/env bash
# Q12 Cleanup/Reset — restores the original 3-container alpine Deployment and removes generated artifacts.
# Safe/robust behaviour:
# - If a lab backup exists (recommended), it restores ~/alpine-deployment.yaml from that backup (pristine).
# - Otherwise it re-applies whatever is currently at ~/alpine-deployment.yaml (best-effort).
# - Removes ~/alpine.spdx.

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

NS="alpine"
MANIFEST="${HOME}/alpine-deployment.yaml"
SPDX_OUT="${HOME}/alpine.spdx"

echo "== Q12 Cleanup/Reset =="
echo "Date: $(date -Is)"
echo "Namespace: ${NS}"
echo "Manifest:  ${MANIFEST}"
echo "SPDX:      ${SPDX_OUT}"
echo

# Find newest backup dir created by the lab setup (if present)
LATEST_BACKUP="$(ls -1dt /root/cis-q12-backups-* 2>/dev/null | head -n1 || true)"
BACKUP_MANIFEST=""
if [[ -n "${LATEST_BACKUP}" ]] && [[ -f "${LATEST_BACKUP}/alpine-deployment.yaml.original" ]]; then
  BACKUP_MANIFEST="${LATEST_BACKUP}/alpine-deployment.yaml.original"
fi

echo "[1] Ensuring namespace exists..."
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}" >/dev/null

echo "[2] Restoring manifest..."
if [[ -n "${BACKUP_MANIFEST}" ]]; then
  echo "✅ Using backup manifest: ${BACKUP_MANIFEST}"
  cp -f "${BACKUP_MANIFEST}" "${MANIFEST}"
else
  echo "⚠️  No backup manifest found under /root/cis-q12-backups-*/alpine-deployment.yaml.original"
  if [[ ! -f "${MANIFEST}" ]]; then
    echo "❌ Cannot proceed: ${MANIFEST} not found and no backup available."
    echo "Remediation: re-run the Q12 lab setup script to recreate the original manifest + backups."
    exit 2
  fi
  echo "✅ Will re-apply existing: ${MANIFEST} (best-effort)"
fi

echo "[3] Applying manifest to the cluster..."
kubectl -n "${NS}" apply -f "${MANIFEST}" >/dev/null

echo "[4] Waiting for rollout..."
# Try to infer Deployment name from the manifest; fallback to 'alpine' if unknown.
DEPLOY_NAME="$(awk '
  $1=="kind:" && $2=="Deployment" {in_dep=1}
  in_dep && $1=="name:" {print $2; exit}
' "${MANIFEST}" 2>/dev/null || true)"
DEPLOY_NAME="${DEPLOY_NAME:-alpine}"

kubectl -n "${NS}" rollout status "deploy/${DEPLOY_NAME}" --timeout=120s >/dev/null 2>&1 || true

echo "[5] Removing generated SPDX output (if any)..."
rm -f "${SPDX_OUT}" || true

echo
echo "✅ Q12 reset complete."
echo "   - Manifest restored at: ${MANIFEST}"
echo "   - Deployment applied in namespace: ${NS}"
echo "   - SPDX removed: ${SPDX_OUT}"
