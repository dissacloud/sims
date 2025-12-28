#!/usr/bin/env bash
cat <<'EOF'
Question 9 — HTTPS Ingress

Create an Ingress resource named 'web' in namespace 'prod' with:
- Host: web.k8s.local
- Route all paths to Service 'web'
- Enable TLS using Secret 'web-cert'
- Redirect HTTP to HTTPS

Test:
  curl -L http://web.k8s.local
EOF
