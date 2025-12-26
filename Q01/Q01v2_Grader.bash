#!/usr/bin/env bash
set -euo pipefail

# Q01 v2 Auto-Verifier (Grader)
# Checks effective kubelet config YAML keys and etcd manifest args and prints a kube-bench-like summary.

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"
ETCD_MANIFEST="/etc/kubernetes/manifests/etcd.yaml"
MODE="${1:-controlplane}"   # controlplane|node

pass=0
fail=0
warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

yaml_get() {
  # Basic YAML key getter using python3 + PyYAML if available.
  # Usage: yaml_get <file> <dot.path>
  local file="$1"
  local path="$2"
  python3 - <<'PY' "$file" "$path"
import sys, os
file=sys.argv[1]; path=sys.argv[2]
try:
    import yaml
except Exception:
    print("__NO_PYYAML__")
    sys.exit(0)

with open(file,'r',encoding='utf-8') as f:
    data=yaml.safe_load(f)

cur=data
for part in path.split('.'):
    if cur is None:
        print("")
        sys.exit(0)
    if isinstance(cur, dict):
        cur=cur.get(part)
    else:
        print("")
        sys.exit(0)

# Normalize booleans/None
if cur is True: print("true")
elif cur is False: print("false")
elif cur is None: print("")
else: print(str(cur))
PY
}

grep_yaml_fallback_bool() {
  # Fallback for booleans in nested blocks (not a full YAML parser, but works for this lab)
  # grep_yaml_fallback_bool <file> <regex_for_key_line>
  local file="$1"
  local key_regex="$2"
  # returns "true"/"false"/"" based on first match
  local line
  line="$(grep -E "$key_regex" "$file" 2>/dev/null | head -n1 || true)"
  if [[ -z "$line" ]]; then echo ""; return; fi
  if echo "$line" | grep -qi "true"; then echo "true"; elif echo "$line" | grep -qi "false"; then echo "false"; else echo ""; fi
}

get_kubelet_anonymous_enabled() {
  local v
  v="$(yaml_get "$KUBELET_CONFIG" "authentication.anonymous.enabled")"
  if [[ "$v" == "__NO_PYYAML__" ]]; then
    # Look for "enabled: <bool>" under anonymous:
    # naive: find the first enabled under anonymous in vicinity (use awk range)
    v="$(awk '
      $1=="anonymous:" {in_anon=1; next}
      in_anon && $1=="enabled:" {print tolower($2); exit}
      in_anon && $1!="" && $1!~"^#" && $1!~"enabled:" && $1!~"^-" && $1!~"^  " {in_anon=0}
    ' "$KUBELET_CONFIG" 2>/dev/null | head -n1)"
  fi
  echo "$v"
}

get_kubelet_webhook_enabled() {
  local v
  v="$(yaml_get "$KUBELET_CONFIG" "authentication.webhook.enabled")"
  if [[ "$v" == "__NO_PYYAML__" ]]; then
    v="$(awk '
      $1=="webhook:" {in_wh=1; next}
      in_wh && $1=="enabled:" {print tolower($2); exit}
      in_wh && $1!="" && $1!~"^#" && $1!~"enabled:" && $1!~"^-" && $1!~"^  " {in_wh=0}
    ' "$KUBELET_CONFIG" 2>/dev/null | head -n1)"
  fi
  echo "$v"
}

get_kubelet_authz_mode() {
  local v
  v="$(yaml_get "$KUBELET_CONFIG" "authorization.mode")"
  if [[ "$v" == "__NO_PYYAML__" ]]; then
    v="$(awk '
      $1=="authorization:" {in_authz=1; next}
      in_authz && $1=="mode:" {print $2; exit}
      in_authz && $1!="" && $1!~"^#" && $1!~"mode:" && $1!~"^-" && $1!~"^  " {in_authz=0}
    ' "$KUBELET_CONFIG" 2>/dev/null | head -n1)"
  fi
  echo "$v"
}

get_etcd_client_cert_auth() {
  # returns "true"/"false"/""
  local v
  if [[ ! -f "$ETCD_MANIFEST" ]]; then echo ""; return; fi
  # handle both "--client-cert-auth=true" and "--client-cert-auth true"
  if grep -qE -- '--client-cert-auth(=| )[Tt]rue' "$ETCD_MANIFEST"; then
    echo "true"
  elif grep -qE -- '--client-cert-auth(=| )[Ff]alse' "$ETCD_MANIFEST"; then
    echo "false"
  else
    echo ""
  fi
}

echo "== Q01 v2 Auto-Verifier (kube-bench-like) =="
echo "Mode: ${MODE}"
echo "Date: $(date -Is)"
echo

# --- Kubelet checks (run on both controlplane and node) ---
if [[ ! -f "${KUBELET_CONFIG}" ]]; then
  add_fail "4.2.x Kubelet config file present" \
    "${KUBELET_CONFIG} not found" \
    "Ensure this is a kubeadm node and kubelet config exists at ${KUBELET_CONFIG}"
else
  add_pass "4.2.x Kubelet config file present"
fi

anon="$(get_kubelet_anonymous_enabled || true)"
if [[ "${anon}" == "false" ]]; then
  add_pass "4.2.1 Ensure anonymous auth is disabled (authentication.anonymous.enabled=false)"
else
  add_fail "4.2.1 Ensure anonymous auth is disabled (authentication.anonymous.enabled=false)" \
    "Found authentication.anonymous.enabled='${anon:-missing}'" \
    "Edit ${KUBELET_CONFIG} and set authentication.anonymous.enabled: false, then restart kubelet (systemctl restart kubelet)"
fi

wh="$(get_kubelet_webhook_enabled || true)"
if [[ "${wh}" == "true" ]]; then
  add_pass "4.2.5 Ensure webhook authentication is enabled (authentication.webhook.enabled=true)"
else
  add_fail "4.2.5 Ensure webhook authentication is enabled (authentication.webhook.enabled=true)" \
    "Found authentication.webhook.enabled='${wh:-missing}'" \
    "Edit ${KUBELET_CONFIG} and set authentication.webhook.enabled: true, then restart kubelet"
fi

authz="$(get_kubelet_authz_mode || true)"
if [[ -n "${authz}" && "${authz}" != "AlwaysAllow" ]]; then
  # Prefer Webhook for this lab, but accept Node,RBAC as secure
  if [[ "${authz}" == "Webhook" || "${authz}" == "Node,RBAC" || "${authz}" == "Node" || "${authz}" == "RBAC" ]]; then
    add_pass "4.2.2 Ensure authorization mode is not AlwaysAllow (authorization.mode != AlwaysAllow)"
  else
    add_warn "4.2.2 Ensure authorization mode is not AlwaysAllow (authorization.mode != AlwaysAllow)" \
      "authorization.mode='${authz}' is not AlwaysAllow but is uncommon for this lab" \
      "Prefer authorization.mode: Webhook (or Node,RBAC) to align with the task"
  fi
else
  add_fail "4.2.2 Ensure authorization mode is not AlwaysAllow (authorization.mode != AlwaysAllow)" \
    "Found authorization.mode='${authz:-missing}'" \
    "Edit ${KUBELET_CONFIG} and set authorization.mode: Webhook (preferred) or Node,RBAC, then restart kubelet"
fi

# --- etcd check (controlplane only) ---
if [[ "${MODE}" == "controlplane" ]]; then
  etcd_val="$(get_etcd_client_cert_auth || true)"
  if [[ -z "${etcd_val}" ]]; then
    add_fail "2.2.4 Ensure etcd --client-cert-auth is set to true" \
      "Could not find --client-cert-auth flag in ${ETCD_MANIFEST}" \
      "Edit ${ETCD_MANIFEST} and add - --client-cert-auth=true under etcd command args"
  elif [[ "${etcd_val}" == "true" ]]; then
    add_pass "2.2.4 Ensure etcd --client-cert-auth is set to true"
  else
    add_fail "2.2.4 Ensure etcd --client-cert-auth is set to true" \
      "Found --client-cert-auth='false'" \
      "Edit ${ETCD_MANIFEST} and set --client-cert-auth=true; kubelet will restart static pod automatically"
  fi
else
  add_warn "2.2.4 Ensure etcd --client-cert-auth is set to true" \
    "Skipped in MODE=node (etcd runs on controlplane)" \
    "Run: sudo bash Q01v2_Grader.bash controlplane on the controlplane node"
fi

# Print results in kube-bench-ish format
for r in "${results[@]}"; do
  echo "$r"
  echo
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
