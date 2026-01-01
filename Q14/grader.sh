#!/usr/bin/env bash
set -euo pipefail

WORKER="${WORKER:-node01}"

fail(){ echo "[FAIL] $*"; exit 1; }
pass(){ echo "[PASS] $*"; }

echo "== Grader: CKS Q14 (forced fd:// path + traps) =="

# Cluster health
kubectl get nodes >/dev/null 2>&1 || fail "kubectl not working on control-plane"
if kubectl get nodes --no-headers | awk '{print $2}' | grep -vq '^Ready$'; then
  kubectl get nodes -o wide
  fail "One or more nodes are not Ready"
else
  pass "All Kubernetes nodes are Ready"
fi

# Worker checks
ssh -o StrictHostKeyChecking=no "${WORKER}" "sudo bash -s" <<'EOS'
set -euo pipefail

fail(){ echo "[FAIL] $*"; exit 1; }
pass(){ echo "[PASS] $*"; }

echo "-- Worker checks --"

# A) Ensure docker is running
systemctl is-active --quiet docker || { systemctl status docker --no-pager || true; fail "docker service is not running"; }
pass "docker service is running"

# B) Force fd:// decision path must be present
if ! systemctl cat docker | grep -q 'fd://'; then
  systemctl cat docker | sed -n '1,140p' || true
  fail "fd:// not present in docker ExecStart; sim integrity broken"
fi
pass "fd:// present in docker ExecStart (decision gate verified)"

# C) TRAP: daemon.json must NOT contain 'hosts'
if grep -q '"hosts"' /etc/docker/daemon.json; then
  echo "daemon.json:"
  cat /etc/docker/daemon.json || true
  fail "daemon.json contains 'hosts' while fd:// is used (this should not be done)"
fi
pass "daemon.json does not contain 'hosts' (fd:// rule followed)"

# D) developer removed from docker group ONLY
id developer >/dev/null 2>&1 || fail "developer user missing"
id ops >/dev/null 2>&1 || fail "ops user missing"

if id -nG developer | tr ' ' '\n' | grep -qx docker; then
  fail "developer is still in docker group"
fi
pass "developer removed from docker group"

# TRAP: ops must remain in docker group
if ! id -nG ops | tr ' ' '\n' | grep -qx docker; then
  fail "ops was removed from docker group (you must not remove other users)"
fi
pass "ops still in docker group (no collateral changes)"

# E) docker group still exists
getent group docker >/dev/null 2>&1 || fail "docker group missing (should not be deleted)"
pass "docker group exists"

# F) /var/run/docker.sock group is root
[ -S /var/run/docker.sock ] || fail "/var/run/docker.sock missing or not a socket"
sock_grp="$(stat -c '%G' /var/run/docker.sock)"
if [ "${sock_grp}" != "root" ]; then
  ls -l /var/run/docker.sock || true
  fail "docker.sock group is '${sock_grp}' (expected root)"
fi
pass "docker.sock group is root"

# G) Docker must not listen on TCP (no :2375, no dockerd LISTEN on tcp)
if ss -lntp | grep -E ':2375' >/dev/null 2>&1; then
  ss -lntp | grep -E ':2375' || true
  fail "dockerd is listening on TCP :2375"
fi

# Also ensure systemd ExecStart no longer includes tcp://
if systemctl cat docker | grep -q 'tcp://'; then
  systemctl cat docker | grep -E 'ExecStart|tcp://' || true
  fail "docker ExecStart still contains tcp://"
fi
pass "No docker TCP listener and no tcp:// in ExecStart"

echo "== Worker checks passed =="
EOS

pass "All checks passed"
echo "== Grade: PASS =="
