#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Lab Setup — Alpine SBOM =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"

# Namespace
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

# Deployment manifest
cat <<'YAML' > "$MANIFEST"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alpine
  namespace: alpine
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alpine
  template:
    metadata:
      labels:
        app: alpine
    spec:
      containers:
      - name: alpine-317
        image: alpine:3.17
        command: ["sleep","3600"]

      - name: alpine-318
        image: alpine:3.18
        command: ["sleep","3600"]

      - name: alpine-319
        image: alpine:3.19
        command: ["sleep","3600"]
YAML

kubectl apply -f "$MANIFEST"

echo
echo "Deployment created:"
kubectl -n alpine rollout status deploy/alpine

echo
echo "Manifest location:"
echo "  $MANIFEST"

echo
echo "✅ Q12 environment ready"
