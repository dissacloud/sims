#!/usr/bin/env bash
set -euo pipefail

NS="monitoring"
SA="stats-monitor-sa"
DEPLOY="stats-monitor"

pass=0; fail=0

p(){ echo "[PASS] $1"; pass=$((pass+1)); }
f(){ echo "[FAIL] $1"; fail=$((fail+1)); }

echo "== Q10 Auto-Verifier =="
echo "Date: $(date -Is)"
echo

if kubectl -n "$NS" get sa "$SA" -o jsonpath='{.automountServiceAccountToken}' | grep -q false; then
  p "ServiceAccount automount disabled"
else
  f "ServiceAccount automount not disabled"
fi

yaml="$(kubectl -n "$NS" get deploy "$DEPLOY" -o yaml)"

echo "$yaml" | grep -q 'projected:' && p "Projected volume configured" || f "Projected volume missing"
echo "$yaml" | grep -q 'serviceAccountToken:' && p "ServiceAccountToken projection present" || f "serviceAccountToken projection missing"
echo "$yaml" | grep -q 'name: token' && p "Volume named token" || f "Volume not named token"
echo "$yaml" | grep -q 'readOnly: true' && p "Token mounted read-only" || f "Token not mounted read-only"

echo
echo "== Summary =="
echo "$pass PASS / $fail FAIL"

[[ "$fail" -eq 0 ]]
