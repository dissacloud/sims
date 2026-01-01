#!/usr/bin/env bash
# Q14 Lab Setup — controlplane orchestrator (v2)
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

echo "== Q14 Lab Setup (controlplane) v2 =="
echo "Date: $(date -Is)"
echo "KUBECONFIG: $KUBECONFIG"
echo

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

echo "[debug] Nodes:"
kubectl get nodes -o wide
echo
echo "[debug] Selected target node (cks000037): $WORKER"
echo

# Persist target for grader/cleanup
printf 'TARGET_NODE=%s\n' "$WORKER" | sudo tee "$TARGET_FILE" >/dev/null
sudo chmod 600 "$TARGET_FILE"

# -------------------------------------------------------------------
# Hygiene: If *controlplane* has developer in docker group, remove it
# (so the question state is isolated to the target node)
# -------------------------------------------------------------------
if getent group docker >/dev/null 2>&1; then
  # getent format: docker:x:<gid>:member1,member2
  if getent group docker | grep -qE '(^|:|,)developer(,|$)'; then
    if getent passwd developer >/dev/null 2>&1; then
      echo "[info] Removing 'developer' from docker group on controlplane (hygiene)..."
      sudo gpasswd -d developer docker >/dev/null 2>&1 || true
    else
      # If developer user doesn't exist locally, just avoid confusion (no-op)
      echo "[info] 'developer' not present as a local user on controlplane; skipping hygiene removal."
    fi
  fi
fi

echo
echo "[hygiene] controlplane docker group now:"
(getent group docker || true)
echo

# --- Copy + execute worker setup ---
echo "[1] Testing SSH connectivity to $WORKER..."
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$WORKER" \
  "echo SSH_OK: \$(hostname -s)" >/dev/null

echo "[2] Copying worker setup script..."
scp -o StrictHostKeyChecking=accept-new \
  "$SCRIPT_DIR/Q14_LabSetUp_worker.bash" \
  "$WORKER:/tmp/Q14_LabSetUp_worker.bash" >/dev/null

echo "[3] Executing worker setup (sudo bash)..."
ssh -o StrictHostKeyChecking=accept-new "$WORKER" \
  "sudo bash /tmp/Q14_LabSetUp_worker.bash"

echo
echo "[4] Verification (target node):"
ssh -o StrictHostKeyChecking=accept-new "$WORKER" '
  set -e
  echo "--- remote host ---"; hostname -s
  echo "--- docker group ---"; getent group docker || true
  echo "--- developer ---"; id developer 2>/dev/null || echo "developer missing"
  echo "--- docker.sock ---"; ls -l /var/run/docker.sock 2>/dev/null || true
  echo "--- dockerd TCP listeners ---"; ss -lntp 2>/dev/null | grep -E "(:2375\b|dockerd)" || true
' || true

echo
echo "✅ Q14 lab environment ready. Target node recorded in $TARGET_FILE"
