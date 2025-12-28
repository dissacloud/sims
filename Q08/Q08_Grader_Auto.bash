#!/usr/bin/env bash
# Q08 Auto-Verifier (kube-bench-like)
set -u
trap '' PIPE

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k(){ KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl "$@"; }

echo "== Q08 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo

# Namespace checks
for ns in prod data; do
  if k get ns "${ns}" >/dev/null 2>&1; then
    add_pass "Namespace ${ns} exists"
  else
    add_fail "Namespace ${ns} exists" "Namespace missing" "Run the lab setup script"
  fi
done

# Label checks
if [[ "$(k get ns prod -o jsonpath='{.metadata.labels.env}' 2>/dev/null || true)" == "prod" ]]; then
  add_pass "prod namespace labeled env=prod"
else
  add_fail "prod namespace labeled env=prod" "Label env!=prod" "Label namespace: kubectl label ns prod env=prod --overwrite"
fi

if [[ "$(k get ns data -o jsonpath='{.metadata.labels.env}' 2>/dev/null || true)" == "data" ]]; then
  add_pass "data namespace labeled env=data"
else
  add_fail "data namespace labeled env=data" "Label env!=data" "Label namespace: kubectl label ns data env=data --overwrite"
fi

# deny-policy existence and structure
if k -n prod get netpol deny-policy >/dev/null 2>&1; then
  add_pass "NetworkPolicy deny-policy exists in prod"

  ps="$(k -n prod get netpol deny-policy -o jsonpath='{.spec.podSelector.matchLabels}' 2>/dev/null || true)"
  # empty selector typically prints {} or empty
  if [[ "${ps}" == "{}" || -z "${ps}" ]]; then
    add_pass "deny-policy selects all pods (podSelector: {})"
  else
    add_fail "deny-policy selects all pods (podSelector: {})" "podSelector not empty" "Set spec.podSelector: {}"
  fi

  ptypes="$(k -n prod get netpol deny-policy -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null || true)"
  if echo "${ptypes}" | grep -qw "Ingress"; then
    add_pass "deny-policy has policyTypes: Ingress"
  else
    add_fail "deny-policy has policyTypes: Ingress" "Ingress not set" "Set spec.policyTypes: [Ingress]"
  fi

  ingress_len="$(k -n prod get netpol deny-policy -o jsonpath='{.spec.ingress}' 2>/dev/null || true)"
  if [[ -z "${ingress_len}" || "${ingress_len}" == "[]" || "${ingress_len}" == "<no value>" ]]; then
    add_pass "deny-policy blocks all ingress (no ingress rules)"
  else
    add_fail "deny-policy blocks all ingress (no ingress rules)" "Ingress rules present" "Remove spec.ingress rules"
  fi
else
  add_fail "NetworkPolicy deny-policy exists in prod" "Not found" "Create NetworkPolicy deny-policy in prod"
fi

# allow-from-prod existence and structure
if k -n data get netpol allow-from-prod >/dev/null 2>&1; then
  add_pass "NetworkPolicy allow-from-prod exists in data"

  ps="$(k -n data get netpol allow-from-prod -o jsonpath='{.spec.podSelector.matchLabels}' 2>/dev/null || true)"
  if [[ "${ps}" == "{}" || -z "${ps}" ]]; then
    add_pass "allow-from-prod selects all pods in data (podSelector: {})"
  else
    add_fail "allow-from-prod selects all pods in data (podSelector: {})" "podSelector not empty" "Set spec.podSelector: {}"
  fi

  # Check namespaceSelector env=prod present
  ns_ok="$(k -n data get netpol allow-from-prod -o jsonpath='{.spec.ingress[0].from[0].namespaceSelector.matchLabels.env}' 2>/dev/null || true)"
  if [[ "${ns_ok}" == "prod" ]]; then
    add_pass "allow-from-prod allows from namespaceSelector env=prod"
  else
    add_fail "allow-from-prod allows from namespaceSelector env=prod" "namespaceSelector env!=prod or missing" "Set ingress.from.namespaceSelector.matchLabels.env: prod"
  fi

  ptypes="$(k -n data get netpol allow-from-prod -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null || true)"
  if echo "${ptypes}" | grep -qw "Ingress"; then
    add_pass "allow-from-prod has policyTypes: Ingress"
  else
    add_fail "allow-from-prod has policyTypes: Ingress" "Ingress not set" "Set spec.policyTypes: [Ingress]"
  fi
else
  add_fail "NetworkPolicy allow-from-prod exists in data" "Not found" "Create NetworkPolicy allow-from-prod in data"
fi

# Functional checks (best-effort)
# Ensure tester pods exist
if k -n prod get pod prod-tester >/dev/null 2>&1; then
  add_pass "prod-tester pod exists"
else
  add_fail "prod-tester pod exists" "Missing pod" "Run the lab setup script"
fi

if k -n dev get pod dev-tester >/dev/null 2>&1; then
  add_pass "dev-tester pod exists"
else
  add_fail "dev-tester pod exists" "Missing pod" "Run the lab setup script"
fi

# Helper to test HTTP reachability
http_try() {
  local ns="$1" pod="$2" url="$3"
  k -n "$ns" exec "$pod" -- sh -c "wget -qO- --timeout=2 ${url} >/dev/null"
}

# prod -> data should succeed once allow-from-prod exists
if http_try prod prod-tester http://data-web.data.svc.cluster.local >/dev/null 2>&1; then
  add_pass "Connectivity: prod-tester -> data-web (allowed)"
else
  add_fail "Connectivity: prod-tester -> data-web (allowed)" "Request failed" "Ensure allow-from-prod is applied in data with namespaceSelector env=prod"
fi

# dev -> data should fail
if http_try dev dev-tester http://data-web.data.svc.cluster.local >/dev/null 2>&1; then
  add_fail "Connectivity: dev-tester -> data-web (denied)" "Request unexpectedly succeeded" "Ensure allow-from-prod restricts ingress to env=prod only"
else
  add_pass "Connectivity: dev-tester -> data-web (denied as expected)"
fi

# dev -> prod should fail due to deny-policy
if http_try dev dev-tester http://prod-web.prod.svc.cluster.local >/dev/null 2>&1; then
  add_fail "Connectivity: dev-tester -> prod-web (denied)" "Request unexpectedly succeeded" "Ensure deny-policy in prod blocks all ingress"
else
  add_pass "Connectivity: dev-tester -> prod-web (denied as expected)"
fi

echo
for r in "${results[@]}"; do
  printf "%s\n\n" "$r" || true
done

echo "== Summary =="
echo "${pass} checks PASS"
echo "${warn} checks WARN"
echo "${fail} checks FAIL"

if [[ "${fail}" -eq 0 ]]; then
  exit 0
else
  exit 2
fi
