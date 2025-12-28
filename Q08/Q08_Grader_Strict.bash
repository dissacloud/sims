#!/usr/bin/env bash
# Q08 Strict Grader — NetworkPolicies across namespaces
# Enforces strict spec shape + functional connectivity.

set -u
trap '' PIPE

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"

NS_PROD="prod"
NS_DATA="data"
NS_DEV="dev"

NP_DENY="deny-policy"
NP_ALLOW="allow-from-prod"

SVC_PROD="prod-web"
SVC_DATA="data-web"

POD_PROD_TEST="prod-tester"
POD_DEV_TEST="dev-tester"

pass=0; fail=0; warn=0
results=()

k() { KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl "$@"; }

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q08 Strict Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Namespaces: prod/data/dev"
echo

# --- Basic reachability ---
if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API not reachable" "Fix control plane before grading"
fi

for ns in "${NS_PROD}" "${NS_DATA}" "${NS_DEV}"; do
  if k get ns "${ns}" >/dev/null 2>&1; then
    add_pass "Namespace exists: ${ns}"
  else
    add_fail "Namespace exists: ${ns}" "Namespace missing" "Re-run lab setup or recreate namespace ${ns}"
  fi
done

# --- Helper strict assertions ---
require_empty_podselector_allpods() {
  # Strict: podSelector must not have matchLabels (select all pods)
  local ns="$1" np="$2"
  local ml
  ml="$(k -n "${ns}" get netpol "${np}" -o jsonpath='{.spec.podSelector.matchLabels}' 2>/dev/null || true)"
  if [[ -z "${ml}" ]]; then
    add_pass "${ns}/${np} selects all pods (podSelector empty)"
  else
    add_fail "${ns}/${np} selects all pods (podSelector empty)" \
      "podSelector.matchLabels is not empty (${ml})" \
      "Set spec.podSelector: {} (remove matchLabels)"
  fi
}

require_policytypes_exact_ingress() {
  local ns="$1" np="$2"
  local pt
  pt="$(k -n "${ns}" get netpol "${np}" -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null || true)"
  # Strict: exactly "Ingress"
  if [[ "${pt}" == "Ingress" ]]; then
    add_pass "${ns}/${np} policyTypes exactly [Ingress]"
  else
    add_fail "${ns}/${np} policyTypes exactly [Ingress]" \
      "policyTypes is '${pt}'" \
      "Set spec.policyTypes: [Ingress]"
  fi
}

# --- Check deny-policy in prod ---
if k -n "${NS_PROD}" get netpol "${NP_DENY}" >/dev/null 2>&1; then
  add_pass "${NS_PROD}/${NP_DENY} exists"
else
  add_fail "${NS_PROD}/${NP_DENY} exists" \
    "NetworkPolicy not found" \
    "Create it: kubectl -n prod apply -f <file> (name: deny-policy)"
fi

if k -n "${NS_PROD}" get netpol "${NP_DENY}" >/dev/null 2>&1; then
  require_empty_podselector_allpods "${NS_PROD}" "${NP_DENY}"
  require_policytypes_exact_ingress "${NS_PROD}" "${NP_DENY}"

  # Strict: deny-all ingress => ingress must be absent or empty array
  ing="$(k -n "${NS_PROD}" get netpol "${NP_DENY}" -o jsonpath='{.spec.ingress}' 2>/dev/null || true)"
  if [[ -z "${ing}" || "${ing}" == "[]" ]]; then
    add_pass "${NS_PROD}/${NP_DENY} has no ingress rules (deny all ingress)"
  else
    add_fail "${NS_PROD}/${NP_DENY} has no ingress rules (deny all ingress)" \
      "spec.ingress is not empty (${ing})" \
      "Remove all ingress rules (leave spec.ingress empty/absent)"
  fi
fi

# --- Check allow-from-prod in data ---
if k -n "${NS_DATA}" get netpol "${NP_ALLOW}" >/dev/null 2>&1; then
  add_pass "${NS_DATA}/${NP_ALLOW} exists"
else
  add_fail "${NS_DATA}/${NP_ALLOW} exists" \
    "NetworkPolicy not found" \
    "Create it: kubectl -n data apply -f <file> (name: allow-from-prod)"
fi

if k -n "${NS_DATA}" get netpol "${NP_ALLOW}" >/dev/null 2>&1; then
  require_empty_podselector_allpods "${NS_DATA}" "${NP_ALLOW}"
  require_policytypes_exact_ingress "${NS_DATA}" "${NP_ALLOW}"

  # Strict: exactly one ingress rule
  extra_ing="$(k -n "${NS_DATA}" get netpol "${NP_ALLOW}" -o jsonpath='{.spec.ingress[1]}' 2>/dev/null || true)"
  first_ing="$(k -n "${NS_DATA}" get netpol "${NP_ALLOW}" -o jsonpath='{.spec.ingress[0]}' 2>/dev/null || true)"
  if [[ -n "${first_ing}" && -z "${extra_ing}" ]]; then
    add_pass "${NS_DATA}/${NP_ALLOW} has exactly one ingress rule"
  else
    add_fail "${NS_DATA}/${NP_ALLOW} has exactly one ingress rule" \
      "Expected ingress[0] only; found extra ingress[1]=${extra_ing:-<none>} or missing ingress[0]" \
      "Ensure spec.ingress contains exactly one rule"
  fi

  # Strict: exactly one 'from' entry
  extra_from="$(k -n "${NS_DATA}" get netpol "${NP_ALLOW}" -o jsonpath='{.spec.ingress[0].from[1]}' 2>/dev/null || true)"
  first_from="$(k -n "${NS_DATA}" get netpol "${NP_ALLOW}" -o jsonpath='{.spec.ingress[0].from[0]}' 2>/dev/null || true)"
  if [[ -n "${first_from}" && -z "${extra_from}" ]]; then
    add_pass "${NS_DATA}/${NP_ALLOW} has exactly one ingress.from entry"
  else
    add_fail "${NS_DATA}/${NP_ALLOW} has exactly one ingress.from entry" \
      "Expected from[0] only; found extra from[1]=${extra_from:-<none>} or missing from[0]" \
      "Ensure spec.ingress[0].from contains exactly one entry"
  fi

  # Strict: from[0] must be namespaceSelector env=prod (and ONLY that)
  ns_sel_env="$(k -n "${NS_DATA}" get netpol "${NP_ALLOW}" -o jsonpath='{.spec.ingress[0].from[0].namespaceSelector.matchLabels.env}' 2>/dev/null || true)"
  pod_sel_present="$(k -n "${NS_DATA}" get netpol "${NP_ALLOW}" -o jsonpath='{.spec.ingress[0].from[0].podSelector}' 2>/dev/null || true)"
  ipblock_present="$(k -n "${NS_DATA}" get netpol "${NP_ALLOW}" -o jsonpath='{.spec.ingress[0].from[0].ipBlock}' 2>/dev/null || true)"

  if [[ "${ns_sel_env}" == "prod" ]]; then
    add_pass "${NS_DATA}/${NP_ALLOW} from.namespaceSelector matches env=prod"
  else
    add_fail "${NS_DATA}/${NP_ALLOW} from.namespaceSelector matches env=prod" \
      "namespaceSelector.matchLabels.env is '${ns_sel_env}'" \
      "Set ingress[0].from[0].namespaceSelector.matchLabels.env: prod (use namespace label env=prod)"
  fi

  if [[ -z "${pod_sel_present}" && -z "${ipblock_present}" ]]; then
    add_pass "${NS_DATA}/${NP_ALLOW} from[0] uses ONLY namespaceSelector (no podSelector/ipBlock)"
  else
    add_fail "${NS_DATA}/${NP_ALLOW} from[0] uses ONLY namespaceSelector (no podSelector/ipBlock)" \
      "Unexpected selector present (podSelector='${pod_sel_present:-<none>}', ipBlock='${ipblock_present:-<none>}')" \
      "Remove podSelector/ipBlock; keep only namespaceSelector"
  fi
fi

# --- Functional connectivity tests ---
# Use wget inside tester pods. If image lacks wget, we fail with a clear message.
url_data="http://${SVC_DATA}.${NS_DATA}.svc.cluster.local"
url_prod="http://${SVC_PROD}.${NS_PROD}.svc.cluster.local"

# prod -> data should succeed
if k -n "${NS_PROD}" get pod "${POD_PROD_TEST}" >/dev/null 2>&1; then
  if k -n "${NS_PROD}" exec "${POD_PROD_TEST}" -- sh -c "command -v wget >/dev/null 2>&1" >/dev/null 2>&1; then
    if k -n "${NS_PROD}" exec "${POD_PROD_TEST}" -- sh -c "wget -qO- --timeout=2 ${url_data} >/dev/null"; then
      add_pass "Functional: prod-tester -> data-web allowed"
    else
      add_fail "Functional: prod-tester -> data-web allowed" \
        "Request failed (should be allowed)" \
        "Ensure allow-from-prod in data permits ingress from namespaceSelector env=prod"
    fi
  else
    add_fail "Functional: prod-tester -> data-web allowed" \
      "wget not available in prod-tester pod" \
      "Use the provided lab setup (do not modify pods); re-run Q08_LabSetUp_controlplane.bash"
  fi
else
  add_fail "Functional: prod-tester -> data-web allowed" \
    "prod-tester pod missing" \
    "Re-run lab setup"
fi

# dev -> data should fail
if k -n "${NS_DEV}" get pod "${POD_DEV_TEST}" >/dev/null 2>&1; then
  if k -n "${NS_DEV}" exec "${POD_DEV_TEST}" -- sh -c "command -v wget >/dev/null 2>&1" >/dev/null 2>&1; then
    if k -n "${NS_DEV}" exec "${POD_DEV_TEST}" -- sh -c "wget -qO- --timeout=2 ${url_data} >/dev/null"; then
      add_fail "Functional: dev-tester -> data-web denied" \
        "Request succeeded (should be blocked)" \
        "Ensure allow-from-prod in data ONLY allows from namespaceSelector env=prod"
    else
      add_pass "Functional: dev-tester -> data-web denied"
    fi
  else
    add_fail "Functional: dev-tester -> data-web denied" \
      "wget not available in dev-tester pod" \
      "Use the provided lab setup (do not modify pods); re-run Q08_LabSetUp_controlplane.bash"
  fi
else
  add_fail "Functional: dev-tester -> data-web denied" \
    "dev-tester pod missing" \
    "Re-run lab setup"
fi

# dev -> prod should fail (due to prod deny-policy)
if k -n "${NS_DEV}" get pod "${POD_DEV_TEST}" >/dev/null 2>&1; then
  if k -n "${NS_DEV}" exec "${POD_DEV_TEST}" -- sh -c "command -v wget >/dev/null 2>&1" >/dev/null 2>&1; then
    if k -n "${NS_DEV}" exec "${POD_DEV_TEST}" -- sh -c "wget -qO- --timeout=2 ${url_prod} >/dev/null"; then
      add_fail "Functional: dev-tester -> prod-web denied (prod deny-policy)" \
        "Request succeeded (should be blocked)" \
        "Ensure deny-policy in prod blocks all ingress"
    else
      add_pass "Functional: dev-tester -> prod-web denied (prod deny-policy)"
    fi
  fi
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

