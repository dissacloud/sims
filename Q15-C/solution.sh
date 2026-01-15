#!/usr/bin/env bash
cat <<'EOF'
REFERENCE SOLUTION (INSTRUCTIONS ONLY) — Q15 (Classic Injection)

1) Enable sidecar injection on target namespace:
   kubectl label ns mtls istio-injection=enabled --overwrite

2) Recreate pods so new pods get the sidecar:
   kubectl -n mtls delete pod --all

3) Verify sidecars:
   kubectl -n mtls get pod -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'

4) Enforce STRICT mTLS:
   kubectl apply -f - <<'YAML'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: mtls
spec:
  mtls:
    mode: STRICT
YAML

5) Validate:
   ./grader.sh
EOF
