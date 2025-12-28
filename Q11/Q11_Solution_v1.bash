#!/usr/bin/env bash
# Q11 Solution — upgrade worker kubelet to match control-plane (binary-based, exam-style flow)
#
# Usage:
#   WORKER=node01 bash Q11_Solution_v1.bash

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"
CP_NODE="${CP_NODE:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 127; }; }
need kubectl
need ssh

echo "== Q11 Solution =="
echo "Date: $(date -Is)"
echo

if [[ -z "${CP_NODE}" ]]; then
  CP_NODE="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
if [[ -z "${WORKER}" ]]; then
  WORKER="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [[ -z "${CP_NODE}" || -z "${WORKER}" ]]; then
  echo "ERROR: Could not determine CP_NODE or WORKER."
  echo "Set explicitly, e.g.: CP_NODE=controlplane WORKER=node01 bash $0"
  exit 2
fi

CP_VER="$(kubectl get node "${CP_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
WK_VER="$(kubectl get node "${WORKER}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"

echo "Control-plane: ${CP_NODE} kubelet=${CP_VER:-unknown}"
echo "Worker:        ${WORKER} kubelet=${WK_VER:-unknown}"
echo

if [[ -z "${CP_VER}" ]]; then
  echo "ERROR: Could not read control-plane kubeletVersion."
  exit 3
fi

TARGET_TAG="${CP_VER}"  # e.g. v1.34.3
echo "Target worker kubelet: ${TARGET_TAG}"
echo

if [[ "${WK_VER}" == "${CP_VER}" ]]; then
  echo "Worker already matches control-plane. Nothing to do."
  exit 0
fi

echo "[1] Drain worker (cordon + evict)..."
kubectl drain "${WORKER}" --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=180s
echo "✅ Drained ${WORKER}"
echo

echo "[2] Upgrade kubelet on worker to ${TARGET_TAG} (binary swap)..."
ssh "${WORKER}" bash -s -- "${TARGET_TAG}" <<'EOSSH'
set -euo pipefail
TAG="$1"
ARCH="amd64"
URL="https://dl.k8s.io/release/${TAG}/bin/linux/${ARCH}/kubelet"
TMP="/tmp/kubelet-${TAG}"
DEST="/usr/bin/kubelet"
BACKUP="/root/cis-q11-upgrade-backup"

echo "Worker: $(hostname)"
echo "Downloading: ${URL}"
mkdir -p "${BACKUP}"

sudo systemctl stop kubelet || true
sleep 1

sudo cp -a "${DEST}" "${BACKUP}/kubelet.before" || true

sudo curl -fL "${URL}" -o "${TMP}"
sudo chmod +x "${TMP}"
"${TMP}" --version

sudo cp -a "${TMP}" "${DEST}.new"
sudo chmod 0755 "${DEST}.new"
sudo mv -f "${DEST}.new" "${DEST}"
sudo chmod 0755 "${DEST}"

sudo systemctl daemon-reload
sudo systemctl start kubelet

echo "kubelet now:"
kubelet --version || true
EOSSH

echo
echo "[3] Wait for node to report updated version..."
for i in {1..40}; do
  cur="$(kubectl get node "${WORKER}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
  if [[ "${cur}" == "${CP_VER}" ]]; then
    echo "✅ Worker version updated: ${cur}"
    break
  fi
  sleep 2
done

echo
echo "[4] Uncordon worker..."
kubectl uncordon "${WORKER}"
echo "✅ Uncordoned ${WORKER}"
echo

echo "[5] Final state:"
kubectl get nodes -o wide
echo
echo "✅ Q11 completed."
