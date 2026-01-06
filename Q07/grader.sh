#!/usr/bin/env bash
set -euo pipefail

APISERVER="/etc/kubernetes/manifests/kube-apiserver.yaml"
POLICY="/etc/kubernetes/logpolicy/audit-policy.yaml"
LOGFILE="/var/log/kubernetes/audit-logs.txt"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"

pass=0; fail=0
ok(){ echo "[PASS] $1"; pass=$((pass+1)); }
bad(){ echo "[FAIL] $1"; fail=$((fail+1)); }

echo "== Q7 Auto-Grader (Enhanced) =="

# 1) apiserver manifest present
[[ -f "$APISERVER" ]] && ok "kube-apiserver manifest present" || bad "kube-apiserver manifest missing"

# 2) apiserver ready
if KUBECONFIG="$ADMIN_KUBECONFIG" kubectl get --raw='/readyz' >/dev/null 2>&1; then
  ok "kube-apiserver ready"
else
  bad "kube-apiserver not ready (check flags + mounts)"
fi

# 3) audit flags
grep -q -- "--audit-policy-file=/etc/kubernetes/logpolicy/audit-policy.yaml" "$APISERVER" && ok "audit-policy-file flag set" || bad "audit-policy-file flag missing"
grep -q -- "--audit-log-path=/var/log/kubernetes/audit-logs.txt" "$APISERVER" && ok "audit-log-path flag set" || bad "audit-log-path flag missing"
grep -q -- "--audit-log-maxage=10" "$APISERVER" && ok "audit-log-maxage=10 set" || bad "audit-log-maxage missing/incorrect"
grep -q -- "--audit-log-maxbackup=2" "$APISERVER" && ok "audit-log-maxbackup=2 set" || bad "audit-log-maxbackup missing/incorrect"

# 4) mounts (must exist or apiserver cannot read/write)
grep -q "mountPath: /etc/kubernetes/logpolicy" "$APISERVER" && ok "audit policy mounted into apiserver" || bad "audit policy NOT mounted (volumeMount missing)"
grep -q "mountPath: /var/log/kubernetes" "$APISERVER" && ok "audit log dir mounted into apiserver" || bad "audit log dir NOT mounted (volumeMount missing)"

# 5) policy file presence
[[ -f "$POLICY" ]] && ok "audit policy file present" || bad "audit policy file missing"
[[ -f "$LOGFILE" ]] && ok "audit log file path exists" || bad "audit log file missing"

echo
echo "== Generating deterministic audit events (workload generator) =="
set +e
KUBECONFIG="$ADMIN_KUBECONFIG" kubectl get ns >/dev/null 2>&1
KUBECONFIG="$ADMIN_KUBECONFIG" kubectl create ns audit-gen-ns --dry-run=client -o yaml | KUBECONFIG="$ADMIN_KUBECONFIG" kubectl apply -f - >/dev/null 2>&1

# Deployment interaction in webapps (should log request body if policy correct)
KUBECONFIG="$ADMIN_KUBECONFIG" kubectl -n webapps annotate deploy/audit-gen q7-run="$(date +%s)" --overwrite >/dev/null 2>&1
KUBECONFIG="$ADMIN_KUBECONFIG" kubectl -n webapps rollout restart deploy/audit-gen >/dev/null 2>&1 || true

# ConfigMap & Secret interactions (must be Metadata only)
KUBECONFIG="$ADMIN_KUBECONFIG" kubectl -n webapps create cm q7-cm --from-literal=a=b --dry-run=client -o yaml | KUBECONFIG="$ADMIN_KUBECONFIG" kubectl apply -f - >/dev/null 2>&1
KUBECONFIG="$ADMIN_KUBECONFIG" kubectl -n webapps create secret generic q7-secret --from-literal=p=q --dry-run=client -o yaml | KUBECONFIG="$ADMIN_KUBECONFIG" kubectl apply -f - >/dev/null 2>&1
KUBECONFIG="$ADMIN_KUBECONFIG" kubectl -n webapps patch secret q7-secret -p '{"metadata":{"annotations":{"q7":"1"}}}' >/dev/null 2>&1

# “Other requests” (should be Metadata)
KUBECONFIG="$ADMIN_KUBECONFIG" kubectl get pods -A >/dev/null 2>&1
set -e

# Give apiserver a moment to flush logs
sleep 2

echo
echo "== Policy semantic checks (via audit log content) =="

python3 - <<'PY'
import json, os, sys

logfile = "/var/log/kubernetes/audit-logs.txt"
if not os.path.exists(logfile):
    print("[FAIL] audit log file missing for semantic checks")
    sys.exit(2)

# Read last N lines for recent events
N = 4000
with open(logfile, "r", encoding="utf-8", errors="ignore") as f:
    lines = f.readlines()[-N:]

events = []
for ln in lines:
    ln = ln.strip()
    if not ln:
        continue
    try:
        events.append(json.loads(ln))
    except Exception:
        continue

def is_resource(ev, resource):
    obj = ev.get("objectRef") or {}
    return obj.get("resource") == resource

def ns_name(ev):
    obj = ev.get("objectRef") or {}
    return obj.get("namespace")

def has_key(ev, key):
    return key in ev

# 1) Secret interactions must be Metadata ONLY => must NOT include requestObject/responseObject
secret_events = [e for e in events if is_resource(e, "secrets")]
bad_secret = [e for e in secret_events if "requestObject" in e or "responseObject" in e]
if not secret_events:
    print("[FAIL] No secret audit events found (generator ran but no events observed)")
    sys.exit(2)
if bad_secret:
    print("[FAIL] Secret events include requestObject/responseObject (Secrets must be Metadata level)")
    sys.exit(2)
print("[PASS] Secret events are Metadata-only (no requestObject/responseObject)")

# 2) ConfigMap interactions should be Metadata (not strictly required to be body-free in all configs, but per task yes)
cm_events = [e for e in events if is_resource(e, "configmaps")]
bad_cm = [e for e in cm_events if "requestObject" in e or "responseObject" in e]
if not cm_events:
    print("[FAIL] No configmap audit events found")
    sys.exit(2)
if bad_cm:
    print("[FAIL] ConfigMap events include requestObject/responseObject (should be Metadata)")
    sys.exit(2)
print("[PASS] ConfigMap events are Metadata-only")

# 3) Deployments in namespace webapps must include request body => expect requestObject present for a deployments event in webapps
dep_events = [e for e in events if is_resource(e, "deployments") and ns_name(e) == "webapps"]
dep_with_body = [e for e in dep_events if "requestObject" in e]
if not dep_events:
    print("[FAIL] No deployment audit events found in namespace webapps")
    sys.exit(2)
if not dep_with_body:
    print("[FAIL] Deployment events in webapps missing requestObject (expected Request level for request body)")
    sys.exit(2)
print("[PASS] Deployment events in webapps include requestObject (Request level)")

# 4) Namespaces interactions at RequestResponse => expect responseObject in a namespaces event
ns_events = [e for e in events if is_resource(e, "namespaces")]
ns_with_resp = [e for e in ns_events if "responseObject" in e]
if not ns_events:
    print("[FAIL] No namespace audit events found")
    sys.exit(2)
if not ns_with_resp:
    print("[FAIL] Namespace events missing responseObject (expected RequestResponse level)")
    sys.exit(2)
print("[PASS] Namespace events include responseObject (RequestResponse level)")

# 5) Catch-all Metadata: ensure we have at least one event without requestObject/responseObject that is not secrets/configmaps
other = []
for e in events:
    r = (e.get("objectRef") or {}).get("resource")
    if r in ("secrets", "configmaps", "deployments", "namespaces"):
        continue
    other.append(e)
other_metaish = [e for e in other if "requestObject" not in e and "responseObject" not in e]
if not other_metaish:
    print("[FAIL] No catch-all Metadata-like events found (expected general requests at Metadata)")
    sys.exit(2)
print("[PASS] Catch-all Metadata behavior observed (other requests without bodies)")
PY

if [[ $? -eq 0 ]]; then
  ok "Audit policy semantics verified via log content"
else
  bad "Audit policy semantics failed (see messages above)"
fi

# 6) log file non-empty (after generator)
if [[ -s "$LOGFILE" ]]; then
  ok "audit log file contains data"
else
  bad "audit log file empty (audit may not be enabled or log path/mount incorrect)"
fi

echo
echo "Summary: $pass PASS / $fail FAIL"
[[ "$fail" -eq 0 ]] && exit 0 || exit 2
