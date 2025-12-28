#!/usr/bin/env bash
# Q11 Lab Setup — Worker Node Upgrade (kubeadm) — CONTROLPLANE
# Prepares an exam-style scenario and captures a strict grader baseline.
# Run on: controlplane

set -euo pipefail

echo "🚀 Q11 Lab Setup — Worker Node Upgrade (kubeadm)"
echo

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
k(){ KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl "$@"; }

BACKUP="/root/cis-q11-backups-$(date +%Y%m%d%H%M%S)"
mkdir -p "${BACKUP}"

echo "📦 Backing up baseline to: ${BACKUP}"
k get nodes -o wide > "${BACKUP}/nodes.before.txt" || true
k get deploy -A -o yaml > "${BACKUP}/deployments.before.yaml" || true
k get sts -A -o yaml > "${BACKUP}/statefulsets.before.yaml" || true

# Stable baseline location used by the grader
mkdir -p /root/.q11
cp -f "${BACKUP}/nodes.before.txt" /root/.q11/nodes.before.txt || true
cp -f "${BACKUP}/deployments.before.yaml" /root/.q11/deployments.before.yaml || true
cp -f "${BACKUP}/statefulsets.before.yaml" /root/.q11/statefulsets.before.yaml || true

CONTROLPLANE_NODE="$(k get nodes -o jsonpath='{.items[?(@.metadata.name=="controlplane")].metadata.name}' 2>/dev/null || true)"
if [[ -z "${CONTROLPLANE_NODE}" ]]; then
  CONTROLPLANE_NODE="$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

WORKER_NODE="$(k get nodes -o jsonpath='{.items[?(@.metadata.name=="compute-0")].metadata.name}' 2>/dev/null || true)"
if [[ -z "${WORKER_NODE}" ]]; then
  WORKER_NODE="$(k get nodes --no-headers 2>/dev/null | awk '{print $1}' | grep -v '^controlplane$' | head -n1 || true)"
fi

if [[ -z "${WORKER_NODE}" ]]; then
  echo "❌ Could not identify worker node (expected compute-0)."
  echo "   Nodes seen:"
  k get nodes -o wide || true
  exit 1
fi

CP_VER="$(k get node "${CONTROLPLANE_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
WK_VER="$(k get node "${WORKER_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"

echo "🧾 Detected:"
echo "   Control plane node: ${CONTROLPLANE_NODE} (kubelet ${CP_VER})"
echo "   Worker node:        ${WORKER_NODE} (kubelet ${WK_VER})"
echo

# Create a small "do-not-touch" fixture workload to make workload-integrity grading meaningful
k get ns q11-fixture >/dev/null 2>&1 || k create ns q11-fixture >/dev/null
cat <<'YAML' | k -n q11-fixture apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: q11-fixture
  labels:
    app: q11-fixture
spec:
  replicas: 1
  selector:
    matchLabels:
      app: q11-fixture
  template:
    metadata:
      labels:
        app: q11-fixture
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
YAML

# Baseline AFTER fixture (this is what "unchanged workloads" means for grading)
k get deploy -A -o yaml > /root/.q11/deployments.baseline.yaml || true
k get sts -A -o yaml > /root/.q11/statefulsets.baseline.yaml || true
echo "${CONTROLPLANE_NODE}" > /root/.q11/controlplane.node || true
echo "${WORKER_NODE}" > /root/.q11/worker.node || true
echo "${CP_VER}" > /root/.q11/controlplane.kubeletVersion || true

cat > /root/.q11/README.txt <<EOF
Q11 baseline captured.

Target: Upgrade worker node "${WORKER_NODE}" to match control plane kubelet version "${CP_VER}".

Notes:
- Perform the upgrade as you would in the exam.
- Do not edit or delete workloads. Draining/uncordoning is fine.
- Run the grader on controlplane:
    bash Q11_Grader_Strict.bash
EOF

echo "✅ Q11 environment ready."
echo
echo "👉 Worker node to upgrade: ${WORKER_NODE}"
echo "👉 Target version (match control plane kubelet): ${CP_VER}"
echo
echo "Tip: connect using: ssh ${WORKER_NODE}"
