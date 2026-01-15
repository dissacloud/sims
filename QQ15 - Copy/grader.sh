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

# Istio presence + endpoint sanity (webhook is fail-closed)
kubectl get ns istio-system >/dev/null 2>&1 || fail "istio-system namespace missing"
kubectl -n istio-system get pods >/dev/null 2>&1 || fail "cannot list istio-system pods"
eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
[ -n "$eps" ] || fail "istiod has no endpoints; sidecar injector webhook may fail (fail-closed)"
pass "Istio present and istiod endpoints available"

# Ensure revision-tag webhook exists (this lab depends on it)
kubectl get mutatingwebhookconfiguration istio-revision-tag-default >/dev/null 2>&1 \
  || fail "istio-revision-tag-default webhook missing (lab broken)"

# Target namespace exists
kubectl get ns "${NS}" >/dev/null 2>&1 || fail "Target namespace '${NS}' missing"

# Enforce the real selector contract:
# - MUST have istio.io/rev=default
# - MUST NOT have istio-injection key set
labels="$(kubectl get ns "${NS}" --show-labels --no-headers)"

echo "$labels" | grep -q 'istio.io/rev=default' \
  || fail "Namespace ${NS} must be labeled istio.io/rev=default"

if echo "$labels" | grep -q 'istio-injection='; then
  echo "$labels"
  fail "Namespace ${NS} must NOT have istio-injection set (selector requires DoesNotExist)"
fi
pass "Namespace ${NS} labels satisfy injector selector"

# All pods in namespace must have istio-proxy
pods="$(kubectl -n "${NS}" get pods -o name || true)"
[ -n "$pods" ] || fail "No pods found in ${NS}"

bad=0
while read -r p; do
  [ -n "$p" ] || continue
  containers="$(kubectl -n "${NS}" get "$p" -o jsonpath='{range .spec.containers[*]}{.name}{" "}{end}')"
  echo "${p#pod/}  ->  $containers"
  echo "$containers" | grep -qw istio-proxy || bad=1
done <<< "$pods"

[ "$bad" -eq 0 ] || fail "One or more pods in ${NS} missing istio-proxy sidecar"
pass "All pods have istio-proxy"

# PeerAuthentication/default must be STRICT in target namespace
kubectl -n "${NS}" get peerauthentication default >/dev/null 2>&1 || fail "PeerAuthentication/default missing in ${NS}"
mode="$(kubectl -n "${NS}" get peerauthentication default -o jsonpath='{.spec.mtls.mode}')"
[ "$mode" = "STRICT" ] || fail "PeerAuthentication/default in ${NS} is '$mode' (expected STRICT)"
pass "PeerAuthentication/default is STRICT in ${NS}"

echo "Info: decoy PeerAuthentication in istio-system (not graded):"
kubectl -n istio-system get peerauthentication strict-decoy >/dev/null 2>&1 && echo " - strict-decoy present" || echo " - strict-decoy not found"

echo "== Grade: PASS =="
