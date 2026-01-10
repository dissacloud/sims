#!/usr/bin/env bash
set -euo pipefail

NS="ai"
DEP_BAD="ollama"
DEP_GOOD="helper"

pass(){ echo "[PASS] $1"; }
fail(){ echo "[FAIL] $1"; exit 1; }

echo "[grader] 0) Docker must be running..."
if ! command -v docker >/dev/null 2>&1; then
  fail "docker binary not found"
fi
if ! sudo docker info >/dev/null 2>&1; then
  fail "docker daemon not responding (sudo docker info failed)"
fi
pass "Docker is installed and running"

echo "[grader] 1) Namespace exists..."
kubectl get ns "${NS}" >/dev/null 2>&1 || fail "Namespace '${NS}' not found"
pass "Namespace '${NS}' exists"

echo "[grader] 2) Deployments exist..."
kubectl -n "${NS}" get deploy "${DEP_BAD}" >/dev/null 2>&1 || fail "Deployment '${DEP_BAD}' not found"
kubectl -n "${NS}" get deploy "${DEP_GOOD}" >/dev/null 2>&1 || fail "Deployment '${DEP_GOOD}' not found"
pass "Deployments exist"

echo "[grader] 3) Misbehaving deployment must be scaled to 0..."
rep_bad="$(kubectl -n "${NS}" get deploy "${DEP_BAD}" -o jsonpath='{.spec.replicas}')"
[[ "${rep_bad}" == "0" ]] || fail "Deployment '${DEP_BAD}' replicas is '${rep_bad}', expected '0'"
pass "ollama replicas = 0"

echo "[grader] 4) Baseline deployment must remain at 1..."
rep_good="$(kubectl -n "${NS}" get deploy "${DEP_GOOD}" -o jsonpath='{.spec.replicas}')"
[[ "${rep_good}" == "1" ]] || fail "Deployment '${DEP_GOOD}' replicas is '${rep_good}', expected '1'"
pass "helper replicas = 1"

echo "[grader] 5) No ollama pods should remain..."
cnt="$(kubectl -n "${NS}" get pods -l app="${DEP_BAD}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
[[ "${cnt}" == "0" ]] || fail "Expected 0 pods for app=${DEP_BAD}, found ${cnt}"
pass "No ollama pods running"

echo
echo "[grader] All checks passed."
