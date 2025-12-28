#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Q10 Lab Setup — ServiceAccount token hardening (exam-style file edit)"

BACKUP="/root/cis-q10-backups-20251228162620"
mkdir -p "$BACKUP"

NS="monitoring"
SA="stats-monitor-sa"
DEP="stats-monitor"
WORKDIR="$HOME/stats-monitor"
MANIFEST="${WORKDIR}/deployment.yaml"

kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}"

# Baseline SA: automount enabled (candidate must set false)
if ! kubectl -n "${NS}" get sa "${SA}" >/dev/null 2>&1; then
  kubectl -n "${NS}" create sa "${SA}"
fi
kubectl -n "${NS}" patch sa "${SA}" -p '{"automountServiceAccountToken": true}' >/dev/null 2>&1 || true

mkdir -p "${WORKDIR}"
cat > "${MANIFEST}" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stats-monitor
  namespace: monitoring
  labels:
    app: stats-monitor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stats-monitor
  template:
    metadata:
      labels:
        app: stats-monitor
    spec:
      serviceAccountName: stats-monitor-sa
      # Intentional baseline: relies on default token automount (will break after SA hardening)
      containers:
      - name: monitor
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          TOKEN="/var/run/secrets/kubernetes.io/serviceaccount/token"
          echo "[stats-monitor] Starting. Expecting token at $TOKEN"
          if [ ! -f "$TOKEN" ]; then
            echo "[stats-monitor] ERROR: token missing at $TOKEN"
            exit 1
          fi
          echo "[stats-monitor] Token present. Sleeping..."
          sleep 3600
YAML

# Backups
kubectl -n "${NS}" get deploy "${DEP}" -o yaml >/dev/null 2>&1 && \
  kubectl -n "${NS}" get deploy "${DEP}" -o yaml > "${BACKUP}/deploy.yaml" || true
kubectl -n "${NS}" get sa "${SA}" -o yaml > "${BACKUP}/sa.yaml" || true
cp -f "${MANIFEST}" "${BACKUP}/deployment.yaml"

kubectl apply -f "${MANIFEST}" >/dev/null

echo
echo "✅ Q10 baseline ready."
echo "   Edit:  ${MANIFEST}"
echo "   Apply: kubectl apply -f ${MANIFEST}"
echo "   Backup: ${BACKUP}"
