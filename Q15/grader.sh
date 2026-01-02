#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-mtls}"
DECOY_NS="${DECOY_NS:-mtls-decoy}"

fail(){ echo "[FAIL] $*"; exit 1; }
pass(){ echo "[PASS] $*"; }

echo "== Grader: Q15 Istio L4 mTLS STRICT =="

# Cluster health baseline
kubectl get nodes >/dev/null 2>&1 || fail "kubectl not working"
if kubectl get nodes --no-headers | awk '{print $2}' | grep -vq '^Ready$'; then
  kubectl get nodes -o wide
  fail "One or more nodes are not Ready"
fi
pass "All nodes Ready"

# Istio presence
kubectl get ns istio-system >/dev/null 2>&1 || fail "istio-system namespace missing"
kubectl -n istio-system get pods >/dev/null 2>&1 || fail "cannot list istio-system pods"
pass "Istio namespace present"

# Target namespace exists
kubectl get ns "${NS}" >/dev/null 2>&1 || fail "Target namespace '${NS}' missing"

# Trap: If they only labeled the decoy namespace, target will still not be injected
labels="$(kubectl get ns "${NS}" --show-labels --no-headers)"
if echo "$labels" | grep -q 'istio-injection=enabled'; then
  pass "Namespace ${NS} has istio-injection=enabled"
elif echo "$labels" | grep -q 'istio.io/rev='; then
  pass "Namespace ${NS} has istio.io/rev=... (revision-based injection)"
else
  echo "$labels"
  fail "Namespace ${NS} does not have injection enabled (istio-injection=enabled OR istio.io/rev=...)"
fi

# All pods in namespace must have istio-proxy
pods="$(kubectl -n "${NS}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')"
[ -n "$pods" ] || fail "No pods found in ${NS}"

bad=0
while read -r p; do
  [ -n "$p" ] || continue
  containers="$(kubectl -n "${NS}" get pod "$p" -o jsonpath='{range .spec.containers[*]}{.name}{" "}{end}')"
  echo "$p  ->  $containers"
  echo "$containers" | grep -qw istio-proxy || bad=1
done <<< "$pods"

[ "$bad" -eq 0 ] || fail "One or more pods in ${NS} missing istio-proxy sidecar"
pass "All pods have istio-proxy"

# PeerAuthentication/default must be STRICT in target namespace
kubectl -n "${NS}" get peerauthentication default >/dev/null 2>&1 || fail "PeerAuthentication/default missing in ${NS}"
mode="$(kubectl -n "${NS}" get peerauthentication default -o jsonpath='{.spec.mtls.mode}')"
[ "$mode" = "STRICT" ] || fail "PeerAuthentication/default in ${NS} is '$mode' (expected STRICT)"
pass "PeerAuthentication/default is STRICT in ${NS}"

# Trap awareness: decoy STRICT in istio-system is irrelevant; do not grade against it, but show it
echo "Info: decoy PeerAuthentication in istio-system (not graded):"
kubectl -n istio-system get peerauthentication strict-decoy >/dev/null 2>&1 && echo " - strict-decoy present" || echo " - strict-decoy not found"

echo "== Grade: PASS =="
