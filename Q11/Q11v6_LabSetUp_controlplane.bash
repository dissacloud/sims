#!/usr/bin/env bash
# Q11 v6 Lab Setup (controlplane) — robust, no-silent-exit version.
# Creates kubelet version skew on the worker by running a worker-side script over SSH.
#
# Key fixes vs v5:
# - No silent exit on 'kubectl version' / jsonpath failures under set -euo pipefail.
# - Prints explicit progress at each step (including kubectl/ssh/scp failures).
# - Auto-detects worker but also accepts WORKER=node01 explicitly.
#
# Usage:
#   WORKER=node01 KUBELET_TAG=v1.33.3 bash Q11v6_LabSetUp_controlplane.bash

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
WORKER="${WORKER:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 127; }; }
need kubectl
need ssh
need scp

echo "== Q11 v6 Setup (kubelet skew) =="
echo "Date: $(date -Is)"
echo "KUBECONFIG: $KUBECONFIG"
echo "Requested kubelet tag: $KUBELET_TAG"
echo

echo "[0] Basic API check..."
if kubectl get nodes >/dev/null 2>&1; then
  echo "✅ kubectl can reach the API"
else
  echo "❌ kubectl cannot reach the API using KUBECONFIG=$KUBECONFIG"
  echo "Run: KUBECONFIG=$KUBECONFIG kubectl get nodes -v=6"
  exit 2
fi
echo

# Get control-plane server version (tolerant)
echo "[1] Detecting control-plane version..."
set +e
CP_VERSION="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"
rc=$?
set -e
if [[ $rc -ne 0 || -z "${CP_VERSION}" ]]; then
  echo "⚠️  Could not parse Server Version via 'kubectl version --short' (rc=$rc)."
  echo "Continuing anyway; skew creation does not require CP version."
  CP_VERSION="<unknown>"
fi
echo "Control-plane server version: v${CP_VERSION}"
echo

# Auto-detect worker if not provided
if [[ -z "${WORKER}" ]]; then
  echo "[2] Auto-detecting a worker node (non-control-plane)..."
  set +e
  WORKER="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' 2>/dev/null     | awk '$2=="" {print $1}' | head -n1)"
  rc=$?
  set -e
  if [[ $rc -ne 0 || -z "${WORKER}" ]]; then
    echo "❌ Failed to auto-detect a worker node."
    echo "Remediation: set WORKER explicitly, e.g.: WORKER=node01 bash $0"
    exit 3
  fi
fi

echo "Worker selected: $WORKER"
echo

# Confirm SSH reachability (not batch-only; we want visible errors)
echo "[3] Testing SSH connectivity to $WORKER ..."
set +e
ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "echo 'SSH_OK: ' \$(hostname)"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "❌ SSH test failed to $WORKER (rc=$rc)."
  echo "If your lab requires password auth, try: ssh $WORKER (manually) and confirm it works."
  echo "If hostname doesn't resolve, use the worker's IP or add /etc/hosts entry."
  exit 4
fi
echo

echo "[4] Copying scripts to worker..."
set +e
scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11v5_LabSetUp_worker.bash "$WORKER:/tmp/Q11v5_LabSetUp_worker.bash"
scp_rc1=$?
scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11v5_Cleanup_Reset_worker.bash "$WORKER:/tmp/Q11v5_Cleanup_Reset_worker.bash"
scp_rc2=$?
set -e
if [[ $scp_rc1 -ne 0 || $scp_rc2 -ne 0 ]]; then
  echo "❌ SCP failed (setup rc=$scp_rc1, cleanup rc=$scp_rc2)."
  exit 5
fi
echo "✅ Scripts copied."
echo

echo "[5] Executing worker setup (will use sudo on worker)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" bash -s -- "$KUBELET_TAG" <<'EOSSH'
set -euo pipefail
KUBELET_TAG="$1"
echo "Worker pre-check:"
echo "  Host: $(hostname)"
echo "  Current kubelet: $(kubelet --version 2>/dev/null || echo '<kubelet missing>')"
chmod +x /tmp/Q11v5_LabSetUp_worker.bash /tmp/Q11v5_Cleanup_Reset_worker.bash
echo "Running: sudo KUBELET_TAG=$KUBELET_TAG bash /tmp/Q11v5_LabSetUp_worker.bash"
sudo KUBELET_TAG="$KUBELET_TAG" bash /tmp/Q11v5_LabSetUp_worker.bash
echo "Worker post-check:"
echo "  kubelet: $(kubelet --version 2>/dev/null || echo '<kubelet missing>')"
EOSSH

echo
echo "[6] Waiting for node object to reflect new kubeletVersion..."
sleep 10
kubectl get nodes -o wide || true

echo
echo "✅ If $WORKER still shows v1.34.x after ~60s, run on the worker:"
echo "   sudo KUBELET_TAG=$KUBELET_TAG bash /tmp/Q11v5_LabSetUp_worker.bash"
