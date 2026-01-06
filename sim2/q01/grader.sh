#!/usr/bin/env bash
set -euo pipefail

NODE="${NODE:-node01}"

fail(){ echo "[FAIL] $*"; exit 1; }
pass(){ echo "[PASS] $*"; }

echo "== Grader: Q1 CIS Benchmark =="

# Node reachable
ssh -o StrictHostKeyChecking=no "${NODE}" "true" || fail "Cannot SSH to ${NODE}"
pass "SSH to ${NODE} successful"

ssh "${NODE}" "sudo bash -s" <<'EOS'
set -euo pipefail
fail(){ echo "[FAIL] $*"; exit 1; }
pass(){ echo "[PASS] $*"; }

CFG="/var/lib/kubelet/config.yaml"

# kubelet config checks
grep -q 'anonymous:' "$CFG" || fail "kubelet authentication.anonymous missing"
grep -q 'enabled: false' "$CFG" || fail "anonymous-auth not set to false"
grep -q 'webhook:' "$CFG" || fail "kubelet webhook auth missing"
grep -q 'enabled: true' "$CFG" || fail "webhook authentication not enabled"
grep -q 'authorization:' "$CFG" || fail "kubelet authorization block missing"
grep -q 'mode: Webhook' "$CFG" || fail "authorization-mode is not Webhook"
pass "kubelet CIS settings correct"

# kubelet running
systemctl is-active --quiet kubelet || fail "kubelet not running"
pass "kubelet running"

# etcd manifest check
ETCD="/etc/kubernetes/manifests/etcd.yaml"
grep -q -- '--client-cert-auth=true' "$ETCD" || fail "etcd --client-cert-auth not true"
pass "etcd client-cert-auth enabled"
EOS

# Cluster health (from control-plane)
kubectl get nodes >/dev/null 2>&1 || fail "kubectl not working"
if kubectl get nodes --no-headers | awk '{print $2}' | grep -vq '^Ready$'; then
  kubectl get nodes -o wide
  fail "One or more nodes not Ready"
fi
pass "All nodes Ready"

echo "== Grade: PASS =="
