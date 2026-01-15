#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-mtls}"

fail(){ echo "[FAIL] $*"; exit 1; }
pass(){ echo "[PASS] $*"; }

echo "== Grader: Q15 (Classic-only) Istio L4 mTLS STRICT =="

kubectl get nodes >/dev/null 2>&1 || fail "kubectl not working"
if kubectl get nodes --no-headers | awk '{print $2}' | grep -vq '^Ready$'; then
  kubectl get nodes -o wide
  fail "One or more nodes are not Ready"
fi
pass "All nodes Ready"

kubectl get ns istio-system >/dev/null 2>&1 || fail "istio-system missing"
eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
[ -n "$eps" ] || fail "istiod has no endpoints; webhook may fail (fail-closed)"
pass "Istio present and istiod endpoints available"

kubectl get ns "${NS}" >/dev/null 2>&1 || fail "Target namespace '${NS}' missing"

labels="$(kubectl get ns "${NS}" --show-labels --no-headers)"

echo "$labels" | grep -q 'istio-injection=enabled' \
  || fail "Namespace ${NS} must be labeled istio-injection=enabled"

# Explicitly disallow revision label in this sim
echo "$labels" | grep -q 'istio.io/rev=' \
  && fail "Namespace ${NS} must NOT use istio.io/rev in this sim"

pass "Namespace labels correct for classic injection"

pods="$(kubectl -n "${NS}" get pods -o name || true)"
[ -n "$pods" ] || fail "No pods found in ${NS}"

bad=0
while read -r p; do
  [ -n "$p" ] || continue
  containers="$(kubectl -n "${NS}" get "$p" -o jsonpath='{range .spec.containers[*]}{.name}{" "}{end}')"
  echo "${p#pod/} -> $containers"
  echo "$containers" | grep -qw istio-proxy || bad=1
done <<< "$pods"

[ "$bad" -eq 0 ] || fail "One or more pods in ${NS} missing istio-proxy sidecar"
pass "All pods have istio-proxy"

kubectl -n "${NS}" get peerauthentication default >/dev/null 2>&1 || fail "PeerAuthentication/default missing in ${NS}"
mode="$(kubectl -n "${NS}" get peerauthentication default -o jsonpath='{.spec.mtls.mode}')"
[ "$mode" = "STRICT" ] || fail "PeerAuthentication/default in ${NS} is '$mode' (expected STRICT)"
pass "PeerAuthentication/default is STRICT"

echo "== Grade: PASS =="
