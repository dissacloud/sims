#!/usr/bin/env bash
# Q14 STRICT Grader v5 — ALIGNED to Q14_Solution.bash
#
# Matches solution validation points:
# Step 1: developer exists AND is NOT in docker group
# Step 2: /etc/docker/daemon.json has NO tcp:// hosts AND sets group=root
#         AND there is NO systemd override that adds tcp listeners
# Step 3: docker.sock group is root AND no TCP listeners on 2375/2376 (and no dockerd TCP LISTEN)
# Step 4: cluster nodes are Ready
#
# Run on: controlplane

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

echo "== Q14 STRICT Grader v5 =="
echo "Date: $(date -Is)"
echo "KUBECONFIG: ${KUBECONFIG}"
echo

# --- Step 0: API health + nodes Ready ---
if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API server not responding" "Export KUBECONFIG=/etc/kubernetes/admin.conf and retry"
fi

NOT_READY="$(k get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{print $1":"$2}' | xargs || true)"
if [[ -z "$NOT_READY" ]]; then
  add_pass "Cluster nodes are Ready"
else
  add_fail "Cluster nodes are Ready" "Not Ready nodes: $NOT_READY" "Fix node conditions before grading"
fi

# --- Identify target node (must be worker used in lab) ---
TARGET_NODE=""
if [[ -f "$TARGET_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$TARGET_FILE" || true
fi

if [[ -n "${TARGET_NODE:-}" ]]; then
  add_pass "Target node selected (${TARGET_NODE})"
else
  add_fail "Target node selected" "Missing $TARGET_FILE or TARGET_NODE not set" "Re-run Q14_LabSetUp_controlplane.bash to create $TARGET_FILE"
fi

# Stop early if no target node
if [[ -z "${TARGET_NODE:-}" ]]; then
  echo
  for r in "${results[@]}"; do echo "$r"; echo; done
  echo "== Summary =="; echo "${pass} PASS"; echo "${warn} WARN"; echo "${fail} FAIL"
  exit 1
fi

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
rssh(){ ssh ${SSH_OPTS} "${TARGET_NODE}" "$@" ; }

# ----------------------------------------
# Step 1 — developer exists and removed from docker group
# ----------------------------------------
if rssh "getent passwd developer" >/dev/null 2>&1; then
  add_pass "developer user exists on ${TARGET_NODE}"
else
  add_fail "developer user exists on ${TARGET_NODE}" "developer user not found" "This lab expects a 'developer' user on ${TARGET_NODE}; re-run Q14_LabSetUp_controlplane.bash"
fi

DOCKER_GROUP_LINE="$(rssh "getent group docker || true" 2>/dev/null || true)"
if [[ -z "$DOCKER_GROUP_LINE" ]]; then
  add_warn "docker group exists" "group 'docker' not found" "If Docker is installed, group should exist; otherwise install Docker"
else
  add_pass "docker group exists"
  # getent format: docker:x:<gid>:member1,member2
  if echo "$DOCKER_GROUP_LINE" | grep -qE '(^|[,:])developer([,:]|$)'; then
    add_fail "developer removed from docker group" "developer still appears in: $DOCKER_GROUP_LINE" "Run on ${TARGET_NODE}: sudo gpasswd -d developer docker"
  else
    add_pass "developer removed from docker group"
  fi
fi

# ----------------------------------------
# Step 2 — daemon.json has no tcp hosts and group=root; no systemd override adding tcp
# ----------------------------------------
DAEMON_JSON="$(rssh "sudo test -f /etc/docker/daemon.json && sudo cat /etc/docker/daemon.json || true" 2>/dev/null || true)"
if [[ -z "$DAEMON_JSON" ]]; then
  add_warn "/etc/docker/daemon.json present" "No /etc/docker/daemon.json found" "Per solution, create it with: {"group":"root"} and restart docker"
else
  add_pass "/etc/docker/daemon.json present"
  if echo "$DAEMON_JSON" | grep -qE '"hosts"[[:space:]]*:'; then
    add_fail "daemon.json has no tcp:// hosts" "daemon.json defines \"hosts\" (may include tcp://)" "Edit /etc/docker/daemon.json to remove \"hosts\" entirely (per solution) and restart docker"
  elif echo "$DAEMON_JSON" | grep -qE 'tcp://'; then
    add_fail "daemon.json has no tcp:// hosts" "Found tcp:// in daemon.json" "Remove tcp:// entries from /etc/docker/daemon.json and restart docker"
  else
    add_pass "daemon.json has no tcp:// hosts"
  fi

  if echo "$DAEMON_JSON" | grep -qE '"group"[[:space:]]*:[[:space:]]*"root"'; then
    add_pass "daemon.json sets group=root"
  else
    add_fail "daemon.json sets group=root" "daemon.json does not set \"group\": \"root\"" "Set daemon.json to exactly: {"group":"root"} and restart docker"
  fi
fi

OVERRIDE_PATH="/etc/systemd/system/docker.service.d/override.conf"
OVERRIDE_CONTENT="$(rssh "sudo test -f ${OVERRIDE_PATH} && sudo cat ${OVERRIDE_PATH} || true" 2>/dev/null || true)"
if [[ -z "$OVERRIDE_CONTENT" ]]; then
  add_pass "No docker systemd override.conf present"
else
  if echo "$OVERRIDE_CONTENT" | grep -qE 'tcp://'; then
    add_fail "No docker systemd override adds tcp" "override.conf contains tcp:// configuration" "Remove ${OVERRIDE_PATH} (per solution) and restart docker"
  else
    add_warn "docker systemd override present" "override.conf exists but no tcp:// found" "Per solution, remove override.conf to avoid unexpected ExecStart overrides"
  fi
fi

# ----------------------------------------
# Step 3 — docker.sock group is root; no TCP listeners
# ----------------------------------------
SOCK_GRP="$(rssh "stat -c '%G' /var/run/docker.sock 2>/dev/null || true" 2>/dev/null || true)"
if [[ -z "$SOCK_GRP" ]]; then
  add_warn "docker.sock present" "Could not stat /var/run/docker.sock" "Ensure Docker is running and the socket exists"
elif [[ "$SOCK_GRP" == "root" ]]; then
  add_pass "docker.sock group is root"
else
  add_fail "docker.sock group is root" "docker.sock group is '$SOCK_GRP'" "Fix per solution: set daemon.json group=root, remove override.conf, restart docker"
fi

LISTEN_2375_2376="$(rssh "sudo ss -lntp 2>/dev/null | grep -E ':(2375|2376)\b' || true" 2>/dev/null || true)"
if [[ -z "$LISTEN_2375_2376" ]]; then
  add_pass "No TCP listeners on 2375/2376"
else
  add_fail "No TCP listeners on 2375/2376" "Found listeners: $(echo "$LISTEN_2375_2376" | head -n 2 | xargs)" "Remove tcp:// from daemon.json and override.conf; then restart docker"
fi

DOCKERD_LISTEN="$(rssh "sudo ss -lntp 2>/dev/null | grep -i dockerd || true" 2>/dev/null || true)"
if [[ -z "$DOCKERD_LISTEN" ]]; then
  add_pass "No dockerd TCP LISTEN entries detected"
else
  if echo "$DOCKERD_LISTEN" | grep -qE ':(2375|2376)\b|0\.0\.0\.0:[0-9]+'; then
    add_fail "No dockerd TCP LISTEN entries detected" "dockerd appears to be listening on TCP: $(echo "$DOCKERD_LISTEN" | head -n 1 | xargs)" "Remove tcp:// configuration and restart docker"
  else
    add_warn "dockerd LISTEN entries present" "dockerd appears in ss output (may be unix socket only)" "Confirm no TCP listeners remain: sudo ss -lntp | egrep -i '(:2375|:2376|dockerd)'"
  fi
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
