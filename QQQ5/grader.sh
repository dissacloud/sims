#!/usr/bin/env bash
set -euo pipefail
fail(){ echo "[FAIL] $1"; exit 1; }
pass(){ echo "[PASS] $1"; }

api_repl="$(kubectl -n ollama get deploy ollama-api -o jsonpath='{.spec.replicas}')"
bad_repl="$(kubectl -n ollama get deploy ollama-memory-scraper -o jsonpath='{.spec.replicas}')"

[[ "$api_repl" == "1" ]] || fail "ollama-api must remain replicas=1 (got $api_repl)"
pass "ollama-api unchanged"

[[ "$bad_repl" == "0" ]] || fail "offending deployment must be replicas=0 (got $bad_repl)"
pass "offending deployment scaled to 0"

kubectl -n ollama get deploy ollama-api >/dev/null || fail "ollama-api deployment missing (should not delete)"
kubectl -n ollama get deploy ollama-memory-scraper >/dev/null || fail "ollama-memory-scraper deployment missing (should not delete)"
pass "no deployments deleted"

echo "All checks passed."
