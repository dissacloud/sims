#!/usr/bin/env bash
# Q11 Solution — EXAM-STYLE MANUAL INSTRUCTIONS (no auto-fix)
# Prints the exact command sequence to run manually (drain -> upgrade -> uncordon).
#
# Usage:
#   bash Q11_Solution_v2.bash
#   WORKER=node01 CP_NODE=controlplane bash Q11_Solution_v2.bash

set -euo pipefail

WORKER="${WORKER:-node01}"
CP_NODE="${CP_NODE:-controlplane}"
ADMIN_KUBECONFIG="${ADMIN_KUBECONFIG:-/etc/kubernetes/admin.conf}"

echo
echo "==================== Q11 — Solution Steps (Manual) ===================="
echo "Date: $(date -Is)"
echo "Worker: ${WORKER}"
echo "Control-plane node: ${CP_NODE}"
echo "KUBECONFIG: ${ADMIN_KUBECONFIG}"
echo

cat <<'EOF'
Goal
----
Bring the worker kubelet version back in line with the control plane using:
  1) Drain worker
  2) Upgrade kubelet on worker (to match control-plane)
  3) Verify nodeInfo updates
  4) Uncordon worker
EOF
echo

echo "Step 1 — Confirm versions"
cat <<EOF
export KUBECONFIG=${ADMIN_KUBECONFIG}
kubectl get nodes
kubectl get node ${CP_NODE} -o jsonpath='{.status.nodeInfo.kubeletVersion}{"\n"}'
kubectl get node ${WORKER}  -o jsonpath='{.status.nodeInfo.kubeletVersion}{"\n"}'
EOF
echo

echo "Step 2 — Drain worker (BEFORE upgrade)"
cat <<EOF
kubectl drain ${WORKER} --ignore-daemonsets --delete-emptydir-data --force
EOF
echo

echo "Step 3 — SSH to worker"
cat <<EOF
ssh ${WORKER}
EOF
echo

echo "Step 4 — Upgrade kubelet on worker (binary-based)"
cat <<'EOF'
# On the WORKER node:

TARGET_TAG=<SET_ME_TO_CONTROLPLANE_KUBELETVERSION>   # e.g. v1.34.3
ARCH=amd64
URL="https://dl.k8s.io/release/${TARGET_TAG}/bin/linux/${ARCH}/kubelet"

sudo systemctl stop kubelet
sudo curl -fL "${URL}" -o /tmp/kubelet
sudo chmod +x /tmp/kubelet
/tmp/kubelet --version

sudo install -m 0755 /tmp/kubelet /usr/bin/kubelet
sudo systemctl daemon-reload
sudo systemctl start kubelet
kubelet --version
EOF
echo

echo "Step 5 — Exit worker; verify version updated"
cat <<EOF
exit
kubectl get node ${WORKER} -o jsonpath='{.status.nodeInfo.kubeletVersion}{"\n"}'
kubectl get nodes
EOF
echo

echo "Step 6 — Uncordon worker (AFTER upgrade)"
cat <<EOF
kubectl uncordon ${WORKER}
EOF
echo

echo "Step 7 — Final checks"
cat <<EOF
kubectl get nodes
kubectl describe node ${WORKER} | egrep -i 'Unschedulable|Ready|Kubelet Version'
EOF
echo
