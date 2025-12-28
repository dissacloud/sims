#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Q10 Lab Setup — ServiceAccount Token Hardening"

kubectl get ns monitoring >/dev/null 2>&1 || kubectl create ns monitoring

cat <<'YAML' | kubectl -n monitoring apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: stats-monitor-sa
automountServiceAccountToken: true
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stats-monitor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stats-monitor
  template:
    metadata:
      labels:
        app: stats-monitor
    spec:
      serviceAccountName: stats-monitor-sa
      containers:
      - name: monitor
        image: busybox
        command: ["sh","-c","sleep 3600"]
YAML

echo "✅ Q10 environment ready"
