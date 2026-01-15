#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-mtls}"
fail(){ echo "[FAIL] $*"; exit 1; }
pass(){ echo "[PASS] $*"; }

echo "== Grader: Q15 Istio L4 mTLS STRICT =="

kubectl get nodes >/dev/null 2>&1 || fail "kubectl not working"
if kubectl get nodes --no-headers | awk '{print $2}' | grep -vq '^Ready$'; then
  kubectl get nodes -o wide
  fail "One or more nodes are not Ready"
fi
pass "All nodes Ready"

kubectl get ns istio-system >/dev/null 2>&1 || fail "istio-system namespace missing"
kubectl -n istio-system get pods >/dev/null 2>&1 || fail "cannot list istio-system pods"
pass "Istio present"

kubectl get ns "${NS}" >/dev/null 2>&1 || fail "Target namespace '${NS}' missing"

labels="$(kubectl get ns "${NS}" --show-labels --no-headers || true)"
if echo "$labels" | grep -q 'istio-injection=enabled'; then
  pass "Namespace ${NS} has istio-injection=enabled"
elif echo "$labels" | grep -q 'istio.io/rev='; then
  pass "Namespace ${NS} has istio.io/rev=... (revision-based injection)"
else
  echo "$labels"
  fail "Namespace ${NS} does not have injection enabled (need istio-injection=enabled OR istio.io/rev=...)"
fi

# Pods list (avoid “prints nothing” confusion)
pods="$(kubectl -n "${NS}" get pods -o name || true)"
[ -n "$pods" ] || fail "No pods found in ${NS}"

bad=0
while read -r p; do
  [ -n "$p" ] || continue
  cname="$(kubectl -n "${NS}" get "$p" -o jsonpath='{range .spec.containers[*]}{.name}{" "}{end}' || true)"
  echo "${p#pod/} -> ${cname}"
  echo "$cname" | grep -qw istio-proxy || bad=1
done <<< "$pods"

[ "$bad" -eq 0 ] || fail "One or more pods in ${NS} missing istio-proxy sidecar"
pass "All pods have istio-proxy"

kubectl -n "${NS}" get peerauthentication default >/dev/null 2>&1 || fail "PeerAuthentication/default missing in ${NS}"
mode="$(kubectl -n "${NS}" get peerauthentication default -o jsonpath='{.spec.mtls.mode}' || true)"
[ "$mode" = "STRICT" ] || fail "PeerAuthentication/default in ${NS} is '$mode' (expected STRICT)"
pass "PeerAuthentication/default is STRICT in ${NS}"

echo "Info (decoy, not graded):"
kubectl -n istio-system get peerauthentication strict-decoy >/dev/null 2>&1 && echo " - strict-decoy present" || echo " - strict-decoy not found"

echo "== Grade: PASS =="
