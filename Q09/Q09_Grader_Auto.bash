#!/usr/bin/env bash
set -u
trap '' PIPE

NS=prod
ING=web
SVC=web
SECRET=web-cert
HOST=web.k8s.local

pass=0; fail=0; warn=0; out=()

p(){ out+=("[PASS] $1"); pass=$((pass+1)); }
f(){ out+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }

echo "== Q09 Auto-Verifier =="
echo "Date: $(date -Is)"
echo

kubectl -n $NS get ingress $ING >/dev/null 2>&1 && p "Ingress exists" || f "Ingress exists" "Not found" "Create Ingress web in prod"

spec="$(kubectl -n $NS get ingress $ING -o yaml 2>/dev/null || true)"

echo "$spec" | grep -q "host: $HOST" && p "Host $HOST configured" || f "Host $HOST configured" "Missing host" "Set rules.host=$HOST"

echo "$spec" | grep -q "name: $SVC" && p "Routes to Service $SVC" || f "Routes to Service $SVC" "Backend mismatch" "Point backend to service web"

echo "$spec" | grep -q "secretName: $SECRET" && p "TLS enabled" || f "TLS enabled" "TLS secret missing" "Add spec.tls.secretName=web-cert"

echo "$spec" | grep -qi "ssl-redirect" && p "HTTP redirected to HTTPS" || f "HTTP redirected to HTTPS" "Redirect missing" "Add nginx.ingress.kubernetes.io/ssl-redirect: "true""

echo
for i in "${out[@]}"; do echo "$i"; echo; done
echo "== Summary =="
echo "$pass PASS / $fail FAIL"
[[ $fail -eq 0 ]] && exit 0 || exit 2
