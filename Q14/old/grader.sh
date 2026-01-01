#!/usr/bin/env bash
set -euo pipefail

WORKER="${WORKER:-node01}"

fail() { echo "[FAIL] $*"; exit 1; }
pass() { echo "[PASS] $*"; }

echo "== Grader: CKS Q14 =="

# Cluster health
if kubectl get nodes --no-headers | awk '{print $2}' | grep -vq '^Ready$'; then
  kubectl get nodes -o wide
  fail "One or more nodes are not Ready"
else
  pass "All nodes are Ready"
fi

# Worker checks
ssh -o StrictHostKeyChecking=no "${WORKER}" "sudo bash -s" <<'EOS'
set -euo pipefail

# A) developer not in docker group
if id developer >/dev/null 2>&1; then
  if id -nG developer | tr ' ' '\n' | grep -qx docker; then
    echo "[FAIL] developer is still in docker group"
    exit 10
  else
    echo "[PASS] developer removed from docker group"
  fi
else
  echo "[FAIL] developer user not found"
  exit 11
fi

# B) docker.sock group is root
if [ -S /var/run/docker.sock ]; then
  grp="$(stat -c '%G' /var/run/docker.sock)"
  if [ "$grp" = "root" ]; then
    echo "[PASS] /var/run/docker.sock group is root"
  else
    echo "[FAIL] /var/run/docker.sock group is '$grp' (expected root)"
    ls -l /var/run/docker.sock || true
    exit 12
  fi
else
  echo "[FAIL] /var/run/docker.sock missing/not socket"
  exit 13
fi

# C) No TCP listener (2375)
if ss -lntp | grep -E ':2375' >/dev/null 2>&1; then
  echo "[FAIL] Docker TCP listener detected on :2375"
  ss -lntp | grep -E ':2375' || true
  exit 14
else
  echo "[PASS] No Docker TCP listener on :2375"
fi

exit 0
EOS

pass "All Q14 checks passed"
echo "== Grade: PASS =="
