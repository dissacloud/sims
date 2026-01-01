#!/usr/bin/env bash
# Q14 STRICT Grader v2 — aligned to solution steps
# Checks:
# 1) developer is NOT in docker group
# 2) /var/run/docker.sock group owner is root
# 3) dockerd is NOT listening on any TCP port (especially 2375/2376); no tcp:// in config/args
# 4) Kubernetes cluster healthy (nodes Ready)
set -euo pipefail
trap '' PIPE

WORKER="${WORKER:-node01}"
export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need kubectl
need ssh

echo "== Q14 STRICT Grader v2 =="
echo "Date: $(date -Is)"
echo "Worker: $WORKER"
echo

# [A] Cluster health
if kubectl get --raw='/readyz' >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API not reachable" "Export KUBECONFIG and ensure control-plane is healthy"
fi

NOT_READY="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{print $1}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
if [[ -z "$NOT_READY" ]]; then
  add_pass "All nodes are Ready"
else
  add_fail "All nodes are Ready" "NotReady nodes: ${NOT_READY}" "kubectl describe node <name>; resolve underlying issue"
fi

# [B] SSH reachability
if ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "true" >/dev/null 2>&1; then
  add_pass "SSH to worker works (BatchMode)"
else
  add_fail "SSH to worker works (BatchMode)" "Cannot SSH non-interactively to $WORKER" "Configure passwordless SSH or run checks directly on the worker"
fi

# From here on, if SSH is not available, skip worker checks to avoid misleading output.
SSH_OK=0
if ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "true" >/dev/null 2>&1; then
  SSH_OK=1
fi

if [[ "$SSH_OK" -eq 1 ]]; then
  # [1] developer removed from docker group
  DEV_GROUPS="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "id -nG developer 2>/dev/null || true" | tr -d '\r')"
  if [[ -z "$DEV_GROUPS" ]]; then
    add_warn "developer docker group membership" "User 'developer' not found (cannot validate membership)" "If the task expects it, ensure user exists; otherwise ignore"
  else
    if echo " $DEV_GROUPS " | grep -q " docker "; then
      add_fail "developer removed from docker group" "developer still in groups: $DEV_GROUPS" "On worker: sudo gpasswd -d developer docker"
    else
      add_pass "developer removed from docker group"
    fi
  fi

  # [2] docker.sock group is root
  SOCK_STAT="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "stat -c '%U:%G %a' /var/run/docker.sock 2>/dev/null || true" | tr -d '\r')"
  if [[ -z "$SOCK_STAT" ]]; then
    add_fail "docker.sock exists" "Could not stat /var/run/docker.sock" "Ensure Docker is installed/running: sudo systemctl restart docker"
  else
    # parse "owner:group mode"
    SOCK_GROUP="$(echo "$SOCK_STAT" | awk -F'[: ]' '{print $2}' 2>/dev/null || true)"
    if [[ "$SOCK_GROUP" == "root" ]]; then
      add_pass "docker.sock group owner is root"
    else
      add_fail "docker.sock group owner is root" "Found $SOCK_STAT" "Configure dockerd group to root (daemon.json \"group\":\"root\") and restart docker"
    fi
  fi

  # [3] No TCP listeners for dockerd (and no tcp:// in config/args)
  LISTEN_TCP="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "sudo ss -lntp 2>/dev/null | egrep -i '(:2375|:2376|dockerd).*LISTEN|LISTEN.*(:2375|:2376)' || true" | tr -d '\r')"
  DOCKERD_ARGS="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "ps -ef | grep -E '[d]ockerd' || true" | tr -d '\r')"
  DAEMON_JSON="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "sudo test -f /etc/docker/daemon.json && sudo cat /etc/docker/daemon.json || true" | tr -d '\r')"
  OVERRIDE_CONF="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "sudo test -f /etc/systemd/system/docker.service.d/override.conf && sudo cat /etc/systemd/system/docker.service.d/override.conf || true" | tr -d '\r')"

  if [[ -n "$LISTEN_TCP" ]]; then
    add_fail "Docker not listening on TCP" "Found TCP listener(s): $LISTEN_TCP" "Remove tcp:// from daemon.json/systemd overrides; restart docker"
  elif echo "$DOCKERD_ARGS$DAEMON_JSON$OVERRIDE_CONF" | grep -qE 'tcp://'; then
    add_fail "Docker not listening on TCP" "tcp:// found in config/args" "Remove -H tcp://... and hosts entries; restart docker"
  else
    add_pass "Docker not listening on TCP"
  fi

  # [4] Sanity: docker service active
  DOCKER_ACTIVE="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "systemctl is-active docker 2>/dev/null || true" | tr -d '\r')"
  if [[ "$DOCKER_ACTIVE" == "active" ]]; then
    add_pass "Docker service is active"
  else
    add_fail "Docker service is active" "systemctl is-active docker returned '$DOCKER_ACTIVE'" "sudo systemctl restart docker; check journalctl -u docker"
  fi
else
  add_warn "Worker checks skipped" "SSH not available to $WORKER" "Run this grader on the worker directly or fix SSH"
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
