#!/usr/bin/env bash
cat <<'EOF'
REFERENCE SOLUTION (INSTRUCTIONS ONLY) — Q15

1) Identify the correct namespace:
   - Target namespace is: mtls

2) Enable sidecar injection for that namespace:
   - Use ONE of:
     a) kubectl label ns mtls istio-injection=enabled --overwrite
     b) kubectl label ns mtls istio.io/rev=default --overwrite   (if revision-based injection is used)

3) Recreate pods so sidecars are injected:
   - Fastest, deterministic:
     kubectl -n mtls delete pod --all
     kubectl -n mtls get pods -w

4) Verify each pod includes istio-proxy:
   - kubectl -n mtls get pod -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'

5) Enforce STRICT mTLS:
   - Apply PeerAuthentication/default in mtls:
     apiVersion: security.istio.io/v1beta1
     kind: PeerAuthentication
     metadata:
       name: default
       namespace: mtls
     spec:
       mtls:
         mode: STRICT

6) Validate:
   - ./grader.sh
EOF
