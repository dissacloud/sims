#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Q09 Lab Setup — HTTPS Ingress"

BACKUP="/root/cis-q09-backups-20251228130011"
mkdir -p "$BACKUP"

kubectl get ns prod >/dev/null 2>&1 || kubectl create ns prod
kubectl label ns prod env=prod --overwrite

cat <<'YAML' | kubectl -n prod apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
YAML

kubectl -n prod get secret web-cert >/dev/null 2>&1 || kubectl -n prod create secret tls web-cert   --cert=/etc/kubernetes/pki/apiserver.crt   --key=/etc/kubernetes/pki/apiserver.key

echo "✅ Q09 environment ready"
