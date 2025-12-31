#!/usr/bin/env bash
set -euo pipefail

echo "== Q13 Lab Setup — PSS restricted (confidential namespace) =="

NS="confidential"
FILE="$HOME/nginx-unprivileged.yaml"
BACKUP="/root/cis-q13-backups-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"

# Create namespace
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

# Step A: Create the NON-COMPLIANT deployment first (before enforcing restricted),
# so the Deployment object exists, then we flip enforcement and force a recreate.
cat <<'YAML' > "$FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-unprivileged
  namespace: confidential
  labels:
    app: nginx-unprivileged
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-unprivileged
  template:
    metadata:
      labels:
        app: nginx-unprivileged
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        securityContext:
          # Intentionally NON-compliant with restricted:
          privileged: true
          allowPrivilegeEscalation: true
          runAsNonRoot: false
          capabilities:
            add: ["NET_ADMIN"]
YAML

cp -f "$FILE" "$BACKUP/nginx-unprivileged.yaml.original"

echo "[0] Applying initial (non-compliant) Deployment before enforcement..."
kubectl apply -f "$FILE" >/dev/null

echo "[1] Waiting briefly for initial pod to appear (best-effort)..."
sleep 3
kubectl -n "$NS" get deploy nginx-unprivileged >/dev/null 2>&1 || true

# Step B: Enforce restricted PSS (and audit/warn too, exam-style)
echo "[2] Enforcing Pod Security Standards: restricted (namespace labels)..."
kubectl label ns "$NS" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  --overwrite >/dev/null

# Step C: Force the controller to attempt new pod creation under restricted (should fail)
echo "[3] Forcing pod recreation under restricted (should become non-running until fixed)..."
kubectl -n "$NS" delete pod -l app=nginx-unprivileged --ignore-not-found >/dev/null 2>&1 || true
sleep 2

echo
echo "Manifest to fix: $FILE"
echo "Backup copy:     $BACKUP/nginx-unprivileged.yaml.original"
echo
echo "Current status (expected: no ready pods until you fix security context):"
kubectl -n "$NS" get deploy,rs,pods -l app=nginx-unprivileged -o wide || true
echo
echo "✅ Q13 environment ready."
