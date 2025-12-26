#!/usr/bin/env bash
# Q01 v2 Grader — Auto-detecting (single-command)
# Automatically detects control-plane vs worker and runs appropriate checks.

set -euo pipefail

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"
ETCD_MANIFEST="/etc/kubernetes/manifests/etcd.yaml"

pass=0
fail=0
warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

yaml_get() {
  local file="$1"; local path="$2"
  python3 - <<'PY' "$file" "$path"
import sys
file=sys.argv[1]; path=sys.argv[2]
try:
    import yaml
except Exception:
    print("__NO_PYYAML__"); sys.exit(0)
with open(file,'r',encoding='utf-8') as f:
    data=yaml.safe_load(f)
cur=data
for p in path.split('.'):
    if isinstance(cur, dict):
        cur=cur.get(p)
    else:
        print(""); sys.exit(0)
if cur is True: print("true")
elif cur is False: print("false")
elif cur is None: print("")
else: print(str(cur))
PY
}

get_kubelet_anonymous_enabled() {
  local v; v="$(yaml_get "$KUBELET_CONFIG" "authentication.anonymous.enabled")"
  [[ "$v" == "__NO_PYYAML__" ]] && v="$(awk '$1=="anonymous:"{a=1} a&&$1=="enabled:"{print tolower($2);exit}' "$KUBELET_CONFIG" 2>/dev/null)"
  echo "$v"
}

get_kubelet_webhook_enabled() {
  local v; v="$(yaml_get "$KUBELET_CONFIG" "authentication.webhook.enabled")"
  [[ "$v" == "__NO_PYYAML__" ]] && v="$(awk '$1=="webhook:"{w=1} w&&$1=="enabled:"{print tolower($2);exit}' "$KUBELET_CONFIG" 2>/dev/null)"
  echo "$v"
}

get_kubelet_authz_mode() {
  local v; v="$(yaml_get "$KUBELET_CONFIG" "authorization.mode")"
  [[ "$v" == "__NO_PYYAML__" ]] && v="$(awk '$1=="authorization:"{a=1} a&&$1=="mode:"{print $2;exit}' "$KUBELET_CONFIG" 2>/dev/null)"
  echo "$v"
}

get_etcd_client_cert_auth() {
  if [[ ! -f "$ETCD_MANIFEST" ]]; then echo ""; return; fi
  if grep -qE -- '--client-cert-auth(=| )[Tt]rue' "$ETCD_MANIFEST"; then echo "true"
  elif grep -qE -- '--client-cert-auth(=| )[Ff]alse' "$ETCD_MANIFEST"; then echo "false"
  else echo ""; fi
}

MODE="node"
if [[ -f "$ETCD_MANIFEST" ]] || kubectl get pods -n kube-system 2>/dev/null | grep -q '^etcd-'; then
  MODE="controlplane"
fi

echo "== Q01 v2 Auto-Verifier (single-command) =="
echo "Detected role: ${MODE}"
echo "Date: $(date -Is)"
echo

if [[ ! -f "${KUBELET_CONFIG}" ]]; then
  add_fail "4.2.x Kubelet config file present"     "${KUBELET_CONFIG} not found"     "Ensure this is a kubeadm node and kubelet config exists"
else
  add_pass "4.2.x Kubelet config file present"
fi

anon="$(get_kubelet_anonymous_enabled || true)"
[[ "$anon" == "false" ]]   && add_pass "4.2.1 Anonymous auth disabled"   || add_fail "4.2.1 Anonymous auth disabled"       "authentication.anonymous.enabled='${anon:-missing}'"       "Set authentication.anonymous.enabled: false and restart kubelet"

wh="$(get_kubelet_webhook_enabled || true)"
[[ "$wh" == "true" ]]   && add_pass "4.2.5 Webhook authentication enabled"   || add_fail "4.2.5 Webhook authentication enabled"       "authentication.webhook.enabled='${wh:-missing}'"       "Set authentication.webhook.enabled: true and restart kubelet"

authz="$(get_kubelet_authz_mode || true)"
if [[ -n "$authz" && "$authz" != "AlwaysAllow" ]]; then
  [[ "$authz" == "Webhook" || "$authz" == "Node,RBAC" ]]     && add_pass "4.2.2 Authorization mode not AlwaysAllow"     || add_warn "4.2.2 Authorization mode not AlwaysAllow"         "authorization.mode='${authz}'"         "Prefer authorization.mode: Webhook (or Node,RBAC)"
else
  add_fail "4.2.2 Authorization mode not AlwaysAllow"     "authorization.mode='${authz:-missing}'"     "Set authorization.mode to Webhook (preferred) or Node,RBAC"
fi

if [[ "$MODE" == "controlplane" ]]; then
  etcd_val="$(get_etcd_client_cert_auth || true)"
  [[ "$etcd_val" == "true" ]]     && add_pass "2.2.4 etcd client cert auth enabled"     || add_fail "2.2.4 etcd client cert auth enabled"         "client-cert-auth='${etcd_val:-missing}'"         "Set --client-cert-auth=true in ${ETCD_MANIFEST}"
else
  add_warn "2.2.4 etcd client cert auth enabled"     "Skipped on worker node"     "Run grader on controlplane to validate etcd"
fi

for r in "${results[@]}"; do echo "$r"; echo; done
echo "== Summary =="
echo "${pass} checks PASS"
echo "${warn} checks WARN"
echo "${fail} checks FAIL"

[[ "$fail" -eq 0 ]] && exit 0 || exit 2
