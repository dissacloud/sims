#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-clever-cactus}"
DEPLOY="${DEPLOY:-clever-cactus}"
SECRET="${SECRET:-clever-cactus}"

fail(){ echo "[FAIL] $*"; exit 1; }
pass(){ echo "[PASS] $*"; }

echo "== Grader: Q16 TLS Secret =="

# Namespace exists
kubectl get ns "${NS}" >/dev/null 2>&1 || fail "Namespace '${NS}' missing"
pass "Namespace exists"

# Deployment exists
kubectl -n "${NS}" get deploy "${DEPLOY}" >/dev/null 2>&1 || fail "Deployment '${DEPLOY}' missing in ${NS}"
pass "Deployment exists"

# Check Deployment references secret by expected name (and ensure it was not changed away)
ref="$(kubectl -n "${NS}" get deploy "${DEPLOY}" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="tls")].secret.secretName}')"
[ "$ref" = "${SECRET}" ] || fail "Deployment tls volume does not reference secretName='${SECRET}' (do not modify deployment)"
pass "Deployment still references expected secret"

# Secret exists in correct namespace
kubectl -n "${NS}" get secret "${SECRET}" >/dev/null 2>&1 || fail "Secret '${SECRET}' not found in namespace '${NS}'"
pass "Secret exists in correct namespace"

# Secret type is TLS
stype="$(kubectl -n "${NS}" get secret "${SECRET}" -o jsonpath='{.type}')"
[ "$stype" = "kubernetes.io/tls" ] || fail "Secret type is '${stype}' (expected kubernetes.io/tls)"
pass "Secret type is kubernetes.io/tls"

# TLS keys exist
crt="$(kubectl -n "${NS}" get secret "${SECRET}" -o jsonpath='{.data.tls\.crt}' | wc -c)"
key="$(kubectl -n "${NS}" get secret "${SECRET}" -o jsonpath='{.data.tls\.key}' | wc -c)"
[ "$crt" -gt 10 ] || fail "tls.crt missing/empty"
[ "$key" -gt 10 ] || fail "tls.key missing/empty"
pass "tls.crt and tls.key present"

# Pods become Ready
kubectl -n "${NS}" rollout status deploy/"${DEPLOY}" --timeout=120s >/dev/null 2>&1 || {
  kubectl -n "${NS}" get pods -o wide || true
  fail "Deployment did not become Ready after secret creation"
}
pass "Deployment is Ready"

echo "== Grade: PASS =="
