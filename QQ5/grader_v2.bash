#!/usr/bin/env bash
set -euo pipefail

NS="ai"
DEP_BAD="ollama"
DEP_GOOD="helper"

pass(){ echo "[PASS] $1"; }
fail(){ echo "[FAIL] $1"; exit 1; }

echo "[grader] 0) Docker must be installed and running..."
command -v docker >/dev/null 2>&1 || fail "docker binary not found"
sudo docker info >/dev/null 2>&1 || fail "docker daemon not responding (sudo docker info failed)"
pass "Docker is running"

echo "[grader] 1) Namespace must exist..."
kubectl get ns "${NS}" >/dev/null 2>&1 || fail "Namespace '${NS}' not found"
pass "Namespace exists"

echo "[grader] 2) Deployments must exist..."
kubectl -n "${NS}" get deploy "${DEP_BAD}" >/dev/null 2>&1 || fail "Deployment '${DEP_BAD}' not found"
kubectl -n "${NS}" get deploy "${DEP_GOOD}" >/dev/null 2>&1 || fail "Deployment '${DEP_GOOD}' not found"
pass "Deployments exist"

echo "[grader] 3) '${DEP_BAD}' must be scaled to 0 replicas..."
rep_bad="$(kubectl -n "${NS}" get deploy "${DEP_BAD}" -o jsonpath='{.spec.replicas}')"
[[ "${rep_bad}" == "0" ]] || fail "Deployment '${DEP_BAD}' replicas is '${rep_bad}', expected '0'"
pass "ollama replicas = 0"

echo "[grader] 4) '${DEP_GOOD}' must remain at 1 replica..."
rep_good="$(kubectl -n "${NS}" get deploy "${DEP_GOOD}" -o jsonpath='{.spec.replicas}')"
[[ "${rep_good}" == "1" ]] || fail "Deployment '${DEP_GOOD}' replicas is '${rep_good}', expected '1'"
pass "helper replicas = 1"

echo "[grader] 5) No '${DEP_BAD}' pods should remain..."
cnt="$(kubectl -n "${NS}" get pods -l app="${DEP_BAD}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
[[ "${cnt}" == "0" ]] || fail "Expected 0 pods for app=${DEP_BAD}, found ${cnt}"
pass "No ollama pods running"

echo
echo "[grader] All checks passed."
