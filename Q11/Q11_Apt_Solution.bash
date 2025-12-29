#!/usr/bin/env bash
# Q11 (APT-based) Solution — STANDARD EXAM FLOW (manual instructions)
#
# This prints the commands you should run (it does NOT execute them automatically).
#
# Usage:
#   bash Q11_Apt_Solution.bash
#   WORKER=node01 bash Q11_Apt_Solution.bash

set -euo pipefail

WORKER="${WORKER:-node01}"
ADMIN_KUBECONFIG="${ADMIN_KUBECONFIG:-/etc/kubernetes/admin.conf}"

echo
echo "==================== Q11 — APT-Based Solution (Manual) ===================="
echo "Date: $(date -Is)"
echo "Worker: ${WORKER}"
echo "KUBECONFIG: ${ADMIN_KUBECONFIG}"
echo

cat <<'EOF'
Goal
----
Upgrade the WORKER using the standard kubeadm/apt process:
  1) Drain worker
  2) On worker: install kubeadm target; run kubeadm upgrade node
  3) On worker: install kubelet + kubectl target; restart kubelet
  4) Uncordon worker
EOF
echo

echo "Step 1 — Determine target version from control plane"
cat <<EOF
export KUBECONFIG=${ADMIN_KUBECONFIG}
kubectl get nodes
CP_VER=\$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {print \$2}' | head -n1)
echo "Control-plane Server Version: \$CP_VER"
# In most exam tasks, target matches control-plane minor/patch as instructed.
EOF
echo

echo "Step 2 — Drain worker (BEFORE upgrade)"
cat <<EOF
kubectl drain ${WORKER} --ignore-daemonsets --delete-emptydir-data --force
EOF
echo

echo "Step 3 — SSH to worker and run the standard node upgrade"
cat <<EOF
ssh ${WORKER}
EOF
echo

cat <<'EOF'
# On the WORKER node (example uses <TARGET_VERSION> placeholder):
# Identify a valid apt version string first:
sudo apt-get update
apt-cache madison kubeadm | head

# Install kubeadm at the target version:
sudo apt-get install -y kubeadm=<TARGET_VERSION>

# Apply node-level upgrade (worker):
sudo kubeadm upgrade node

# Install kubelet and kubectl at the same target version:
sudo apt-get install -y kubelet=<TARGET_VERSION> kubectl=<TARGET_VERSION>

# Restart kubelet:
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Verify local:
kubelet --version
kubectl version --client --short
exit
EOF
echo

echo "Step 4 — Verify and uncordon"
cat <<EOF
kubectl get nodes -o wide
kubectl uncordon ${WORKER}
kubectl get nodes
EOF
echo

echo "Expected end-state:"
cat <<EOF
- ${WORKER} Ready=True
- ${WORKER} schedulable (uncordoned)
- ${WORKER}.status.nodeInfo.kubeletVersion matches control-plane kubeletVersion
EOF

echo "==========================================================================="
