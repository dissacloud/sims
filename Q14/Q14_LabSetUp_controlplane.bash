#!/usr/bin/env bash
# Q14 Lab Setup — controlplane orchestrator
#
# Creates intentionally insecure Docker settings on the TARGET node for Question 14.
#
# Run on: controlplane
# Writes: /root/.q14_target  (TARGET_NODE=<name>)
#
# Optional:
#   TARGET_NODE=<nodeName> to pin the target selection.

set -euo pipefail
trap '' PIPE

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
TARGET_FILE="/root/.q14_target"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== Q14 Lab Setup (controlplane) =="
echo "Date: $(date -Is)"
echo "KUBECONFIG: $KUBECONFIG"

# --- Select target node ---
if [[ -n "${TARGET_NODE:-}" ]]; then
  WORKER="$TARGET_NODE"
else
  # pick the first node that is NOT labelled as control-plane
  WORKER="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' \
    | awk '$2==""{print $1; exit 0}')"
fi

if [[ -z "${WORKER:-}" ]]; then
  echo "ERROR: Could not auto-detect a worker node. Set TARGET_NODE explicitly." >&2
  exit 2
fi

echo "Target node (cks000037): $WORKER"

# Persist target for grader/cleanup
printf 'TARGET_NODE=%s\n' "$WORKER" | sudo tee "$TARGET_FILE" >/dev/null
sudo chmod 600 "$TARGET_FILE"

# Sanity: if developer is accidentally present on controlplane docker group, remove it
# to avoid confusion when testing.
if getent group docker >/dev/null 2>&1; then
  if getent group docker | grep -qE '(^|,)developer(,|$)'; then
    echo "[info] Removing 'developer' from docker group on controlplane (hygiene)..."
    sudo gpasswd -d developer docker >/dev/null 2>&1 || true
  fi
fi

# --- Copy + execute worker setup ---
echo "[1] Testing SSH connectivity to $WORKER..."
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$WORKER" "echo SSH_OK: $(hostname)" >/dev/null

echo "[2] Copying worker setup script..."
scp -o StrictHostKeyChecking=accept-new "$SCRIPT_DIR/Q14_LabSetUp_worker.bash" "$WORKER:/tmp/Q14_LabSetUp_worker.bash" >/dev/null

echo "[3] Executing worker setup (sudo bash)..."
ssh -o StrictHostKeyChecking=accept-new "$WORKER" "sudo bash /tmp/Q14_LabSetUp_worker.bash" 

echo
echo "[4] Verification (target node):"
ssh -o StrictHostKeyChecking=accept-new "$WORKER" "set -e; echo '--- docker group ---'; getent group docker || true; echo '--- developer ---'; id developer 2>/dev/null || echo 'developer missing'; echo '--- docker.sock ---'; ls -l /var/run/docker.sock 2>/dev/null || true; echo '--- dockerd TCP listeners ---'; ss -lntp 2>/dev/null | grep -E '(:2375\b|dockerd)' || true" || true

echo
echo "✅ Q14 lab environment ready. Target node recorded in $TARGET_FILE"
