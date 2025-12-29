#!/usr/bin/env bash
# Q11 (APT-based) Solution — INSTRUCTIONS ONLY (exam-style)
#
# This script prints the command sequence to:
#  - drain the worker
#  - align worker apt repo to the control-plane minor (pkgs.k8s.io minor channel)
#  - upgrade kubeadm + kubelet/kubectl using apt and kubeadm upgrade node
#  - uncordon the worker
#
# It does NOT change the cluster.

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-node01}"

k(){ KUBECONFIG="${KUBECONFIG}" kubectl "$@"; }

CP_NODE="$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo controlplane)"
CP_KUBELET_VER="$(k get node "${CP_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
CP_MINOR="$(echo "${CP_KUBELET_VER}" | sed -E 's/^v?([0-9]+\.[0-9]+)\..*/\1/;t;d')"

echo "== Q11 APT Solution (instructions only) =="
echo "Date: $(date -Is)"
echo "Control-plane node: ${CP_NODE}"
echo "Control-plane kubelet: ${CP_KUBELET_VER:-<unknown>}"
echo "Control-plane minor:   ${CP_MINOR:-<unknown>}"
echo "Worker:               ${WORKER}"
echo

cat <<EOF
# 0) Baseline
export KUBECONFIG=${KUBECONFIG}
kubectl get nodes -o wide

# 1) Drain worker (must be BEFORE upgrading)
kubectl drain ${WORKER} --ignore-daemonsets --delete-emptydir-data

# 2) On the worker: set Kubernetes apt repo to the control-plane MINOR channel (pkgs.k8s.io)
ssh ${WORKER} "sudo mkdir -p /etc/apt/keyrings && sudo apt-get update -y && sudo apt-get install -y ca-certificates curl gnupg"

# Replace <CP_MINOR> if this script couldn't detect it; example: 1.34
ssh ${WORKER} "curl -fsSL https://pkgs.k8s.io/core:/stable:/v${CP_MINOR:-<CP_MINOR>}/deb/Release.key | sudo gpg --dearmor --batch --yes --no-tty -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg"
ssh ${WORKER} "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${CP_MINOR:-<CP_MINOR>}/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null"
ssh ${WORKER} "sudo apt-get update -y"

# 3) Upgrade worker using standard kubeadm/apt flow
#    (a) upgrade kubeadm first
ssh ${WORKER} "sudo apt-mark unhold kubeadm kubelet kubectl >/dev/null 2>&1 || true"
ssh ${WORKER} "apt-cache madison kubeadm | head"
ssh ${WORKER} "sudo apt-get install -y kubeadm"

#    (b) run kubeadm upgrade node
ssh ${WORKER} "sudo kubeadm upgrade node"

#    (c) upgrade kubelet + kubectl
ssh ${WORKER} "apt-cache madison kubelet | head"
ssh ${WORKER} "sudo apt-get install -y kubelet kubectl"
ssh ${WORKER} "sudo systemctl daemon-reload && sudo systemctl restart kubelet"

#    (optional) hold packages afterwards
ssh ${WORKER} "sudo apt-mark hold kubeadm kubelet kubectl >/dev/null 2>&1 || true"

# 4) Verify node versions and readiness
kubectl get nodes -o wide

# 5) Uncordon worker (must be LAST)
kubectl uncordon ${WORKER}
kubectl get nodes

# 6) Run strict grader
bash Q11_Apt_Grader_Strict.bash
EOF
