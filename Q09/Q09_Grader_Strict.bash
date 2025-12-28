#!/usr/bin/env bash
# Q09 Strict Grader — HTTPS Ingress (ordering + exact-field matching)
# - Enforces first-element ordering for spec.tls[0] and spec.rules[0].http.paths[0]
# - Enforces exact host/service/secret/path/pathType/port
# - Requires HTTP->HTTPS redirect annotation (nginx-style) with exact value "true"
#
# Expected:
# namespace: prod
# ingress name: web
# host: web.k8s.local
# service: web:80
# tls secret: web-cert
# redirect: nginx.ingress.kubernetes.io/ssl-redirect: "true"  (or force-ssl-redirect)

set -u
trap '' PIPE

NS="prod"
ING="web"
HOST="web.k8s.local"
SVC="web"
PORT="80"
SECRET="web-cert"
APIV="networking.k8s.io/v1"
KIND="Ingress"

pass=0; fail=0; warn=0
out=()

p(){ out+=("[PASS] $1"); pass=$((pass+1)); }
f(){ out+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
w(){ out+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

jp(){ kubectl -n "$NS" get ingress "$ING" -o "jsonpath=$1" 2>/dev/null || true; }

echo "== Q09 Strict Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Target: ${NS}/${ING}"
echo

# Existence
if kubectl -n "$NS" get ingress "$ING" >/dev/null 2>&1; then
  p "Ingress ${NS}/${ING} exists"
else
  f "Ingress ${NS}/${ING} exists" \
    "Ingress not found" \
    "Create an Ingress named '${ING}' in namespace '${NS}'"
fi

# Basic identity (apiVersion/kind/name/ns) — strict
api="$(jp '{.apiVersion}')"
kind="$(jp '{.kind}')"
name="$(jp '{.metadata.name}')"
ns="$(jp '{.metadata.namespace}')"

[[ "$api" == "$APIV" ]] && p "apiVersion is ${APIV}" || f "apiVersion is ${APIV}" "Got '${api}'" "Use apiVersion: ${APIV}"
[[ "$kind" == "$KIND" ]] && p "kind is ${KIND}" || f "kind is ${KIND}" "Got '${kind}'" "Use kind: ${KIND}"
[[ "$name" == "$ING" ]] && p "metadata.name is ${ING}" || f "metadata.name is ${ING}" "Got '${name}'" "Set metadata.name: ${ING}"
[[ "$ns" == "$NS" ]] && p "metadata.namespace is ${NS}" || f "metadata.namespace is ${NS}" "Got '${ns}'" "Set metadata.namespace: ${NS}"

# Redirect annotation — strict: must be exactly "true" on one of the common nginx keys
ann_ssl="$(jp '{.metadata.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect}')"
ann_force="$(jp '{.metadata.annotations.nginx\.ingress\.kubernetes\.io/force-ssl-redirect}')"

if [[ "$ann_ssl" == "true" || "$ann_force" == "true" ]]; then
  p "HTTP -> HTTPS redirect annotation is set to \"true\" (nginx)"
else
  f "HTTP -> HTTPS redirect annotation is set to \"true\" (nginx)" \
    "Missing nginx ssl redirect annotation or value is not 'true' (ssl-redirect='${ann_ssl:-<empty>}', force-ssl-redirect='${ann_force:-<empty>}')" \
    "Add annotation: nginx.ingress.kubernetes.io/ssl-redirect: \"true\" (or force-ssl-redirect: \"true\")"
fi

# --- Strict TLS checks (ordering enforced) ---
# Require tls[0].secretName == web-cert
tls_secret="$(jp '{.spec.tls[0].secretName}')"
if [[ "$tls_secret" == "$SECRET" ]]; then
  p "spec.tls[0].secretName is ${SECRET}"
else
  f "spec.tls[0].secretName is ${SECRET}" \
    "Got '${tls_secret:-<empty>}'" \
    "Set spec.tls[0].secretName: ${SECRET} (and ensure this is the first tls entry)"
fi

# Require tls[0].hosts[0] == web.k8s.local
tls_host0="$(jp '{.spec.tls[0].hosts[0]}')"
if [[ "$tls_host0" == "$HOST" ]]; then
  p "spec.tls[0].hosts[0] is ${HOST}"
else
  f "spec.tls[0].hosts[0] is ${HOST}" \
    "Got '${tls_host0:-<empty>}'" \
    "Set spec.tls[0].hosts: [${HOST}] (ensure host is first entry)"
fi

# --- Strict rule checks (ordering enforced) ---
rule_host0="$(jp '{.spec.rules[0].host}')"
if [[ "$rule_host0" == "$HOST" ]]; then
  p "spec.rules[0].host is ${HOST}"
else
  f "spec.rules[0].host is ${HOST}" \
    "Got '${rule_host0:-<empty>}'" \
    "Set spec.rules[0].host: ${HOST} (and ensure it is the first rule)"
fi

# Path checks: paths[0].path == / ; pathType Prefix
path0="$(jp '{.spec.rules[0].http.paths[0].path}')"
ptype0="$(jp '{.spec.rules[0].http.paths[0].pathType}')"

if [[ "$path0" == "/" ]]; then
  p "spec.rules[0].http.paths[0].path is /"
else
  f "spec.rules[0].http.paths[0].path is /" \
    "Got '${path0:-<empty>}'" \
    "Set spec.rules[0].http.paths[0].path: /"
fi

if [[ "$ptype0" == "Prefix" ]]; then
  p "spec.rules[0].http.paths[0].pathType is Prefix"
else
  f "spec.rules[0].http.paths[0].pathType is Prefix" \
    "Got '${ptype0:-<empty>}'" \
    "Set spec.rules[0].http.paths[0].pathType: Prefix"
fi

# Backend service name/port strict
b_svc="$(jp '{.spec.rules[0].http.paths[0].backend.service.name}')"
b_port="$(jp '{.spec.rules[0].http.paths[0].backend.service.port.number}')"

if [[ "$b_svc" == "$SVC" ]]; then
  p "backend.service.name is ${SVC}"
else
  f "backend.service.name is ${SVC}" \
    "Got '${b_svc:-<empty>}'" \
    "Set backend.service.name: ${SVC}"
fi

if [[ "$b_port" == "$PORT" ]]; then
  p "backend.service.port.number is ${PORT}"
else
  f "backend.service.port.number is ${PORT}" \
    "Got '${b_port:-<empty>}'" \
    "Set backend.service.port.number: ${PORT}"
fi

# Ensure referenced secret/service exist (strict)
if kubectl -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then
  p "TLS Secret ${NS}/${SECRET} exists"
else
  f "TLS Secret ${NS}/${SECRET} exists" \
    "Secret not found" \
    "Do not change the secret name; ensure '${SECRET}' exists in '${NS}'"
fi

if kubectl -n "$NS" get svc "$SVC" >/dev/null 2>&1; then
  p "Service ${NS}/${SVC} exists"
else
  f "Service ${NS}/${SVC} exists" \
    "Service not found" \
    "Do not change the service name; ensure '${SVC}' exists in '${NS}'"
fi

echo
for line in "${out[@]}"; do
  printf "%s\n\n" "$line" || true
done

echo "== Summary =="
echo "${pass} checks PASS"
echo "${warn} checks WARN"
echo "${fail} checks FAIL"

if [[ "$fail" -eq 0 ]]; then
  exit 0
else
  exit 2
fi

