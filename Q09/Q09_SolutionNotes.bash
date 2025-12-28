#!/usr/bin/env bash
cat <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: prod
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - web.k8s.local
    secretName: web-cert
  rules:
  - host: web.k8s.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
EOF
