#!/usr/bin/env bash
# Q14 STRICT Grader v4 — aligned to solution steps (fixed)
#
# Verifies (on the TARGET node):
# 1) user 'developer' exists and is NOT a member of group 'docker'
# 2) Docker is NOT listening on any TCP port (explicitly checks 2375/2376)
# 3) /var/run/docker.sock is owned by group 'root'
# 4) Kubernetes cluster health (nodes Ready)

set -euo pipefail
trap '' PIPE

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
TARGET_FILE="/root/.q14_target"

pass=0; fail=0; warn=0
results=()
add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k(){ kubectl "$@"; }

echo "== Q14 STRICT Grader v4 =="
echo "Date: $(date -Is)"
echo

if ! k get --raw=/readyz >/dev/null 2>&1; then
  add_fail "API server reachable (/readyz)" "API server not responding" "Export KUBECONFIG=/etc/kubernetes/admin.conf and retry"
else
  add_pass "API server reachable (/readyz)"
fi

TARGET_NODE=""
if [[ -f "$TARGET_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$TARGET_FILE" || true
fi

if [[ -z "${TARGET_NODE:-}" ]]; then
  add_fail "Target node selected" "Missing $TARGET_FILE or TARGET_NODE not set" "Re-run Q14_LabSetUp_controlplane.bash to create $TARGET_FILE"
else
  add_pass "Target node selected (${TARGET_NODE})"
fi

# --- Kubernetes health ---
NOT_READY="$(k get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{print $1":"$2}' | xargs || true)"
if [[ -z "$NOT_READY" ]]; then
  add_pass "Cluster nodes are Ready"
else
  add_fail "Cluster nodes are Ready" "Not Ready nodes: $NOT_READY" "Fix node conditions before grading"
fi

# Stop here if we don't know target
if [[ -z "${TARGET_NODE:-}" ]]; then
  echo
  for r in "${results[@]}"; do echo "$r"; echo; done
  echo "== Summary =="; echo "${pass} PASS"; echo "${warn} WARN"; echo "${fail} FAIL"; exit 1
fi

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

# --- Step 1: developer exists and not in docker group ---
if ssh $SSH_OPTS "${TARGET_NODE}" "getent passwd developer" >/dev/null 2>&1; then
  add_pass "developer user exists on ${TARGET_NODE}"
else
  add_fail "developer user exists on ${TARGET_NODE}" "developer user not found" "This lab expects a 'developer' user on ${TARGET_NODE}; re-run Q14_LabSetUp_controlplane.bash"
fi

DOCKER_GROUP_LINE="$(ssh $SSH_OPTS "${TARGET_NODE}" "getent group docker || true" 2>/dev/null || true)"
if [[ -z "$DOCKER_GROUP_LINE" ]]; then
  add_warn "docker group exists" "group 'docker' not found" "If Docker is installed, group should exist; otherwise install Docker"
else
  add_pass "docker group exists"
  # FIX: correct delimiter-aware membership check for getent output: docker:x:<gid>:member1,member2
  if echo "$DOCKER_GROUP_LINE" | grep -qE '(^|[,:])developer([,:]|$)'; then
    add_fail "developer removed from docker group" "developer still appears in: $DOCKER_GROUP_LINE" "Run on ${TARGET_NODE}: sudo gpasswd -d developer docker"
  else
    add_pass "developer removed from docker group"
  fi
fi

# --- Step 2: docker.sock group root ---
SOCK_STAT="$(ssh $SSH_OPTS "${TARGET_NODE}" "stat -c '%G %A %n' /var/run/docker.sock 2>/dev/null || true" 2>/dev/null || true)"
if [[ -z "$SOCK_STAT" ]]; then
  add_warn "docker.sock present" "Could not stat /var/run/docker.sock" "Ensure Docker is running and the socket exists"
else
  SOCK_GRP="$(awk '{print $1}' <<<"$SOCK_STAT" || true)"
  if [[ "$SOCK_GRP" == "root" ]]; then
    add_pass "docker.sock group is root"
  else
    add_fail "docker.sock group is root" "docker.sock group is '$SOCK_GRP' ($SOCK_STAT)" "Set SocketGroup=root in docker.socket or remove daemon.json \"group\": \"docker\"; then restart docker/docker.socket"
  fi
fi

# --- Step 3: dockerd not listening on TCP (explicit ports) ---
# FIX: check port binding itself (2375/2376), not process string
LISTEN_2375="$(ssh $SSH_OPTS "${TARGET_NODE}" "ss -lnt 2>/dev/null | awk '{print \$4}' | grep -E ':(2375|2376)\$' || true" 2>/dev/null || true)"
if [[ -z "$LISTEN_2375" ]]; then
  add_pass "Docker not listening on TCP (2375/2376)"
else
  add_fail "Docker not listening on TCP (2375/2376)" "Found listeners: $(echo "$LISTEN_2375" | xargs)" "Remove tcp hosts from /etc/docker/daemon.json and any systemd overrides; then restart docker"
fi

echo
for r in "${results[@]}"; do
  echo "$r"
  echo
done

echo "== Summary =="
echo "${pass} PASS"
echo "${warn} WARN"
echo "${fail} FAIL"

[[ "$fail" -eq 0 ]]
