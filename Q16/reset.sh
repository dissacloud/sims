#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-clever-cactus}"
DEPLOY="${DEPLOY:-clever-cactus}"
SECRET="${SECRET:-clever-cactus}"

echo "== Reset Q16 to broken baseline (secret missing) =="

kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}" >/dev/null

# Ensure app resources exist (re-apply)
kubectl -n "${NS}" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: ${DEPLOY}
  ports:
  - name: https
    port: 443
    targetPort: 8443
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-tls-conf
data:
  default.conf: |
    server {
      listen 8443 ssl;
      server_name web.k8s.local;

      ssl_certificate     /etc/tls/tls.crt;
      ssl_certificate_key /etc/tls/tls.key;

      location / {
        return 200 "ok\n";
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOY}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DEPLOY}
  template:
    metadata:
      labels:
        app: ${DEPLOY}
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8443
        volumeMounts:
        - name: tls
          mountPath: /etc/tls
          readOnly: true
        - name: nginx-conf
          mountPath: /etc/nginx/conf.d
          readOnly: true
      volumes:
      - name: tls
        secret:
          secretName: ${SECRET}
          optional: false
      - name: nginx-conf
        configMap:
          name: nginx-tls-conf
EOF

# Delete the secret in target namespace (forces the task)
kubectl -n "${NS}" delete secret "${SECRET}" --ignore-not-found >/dev/null 2>&1 || true

echo "Reset complete. Run ./question.sh"
