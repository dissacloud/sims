#!/usr/bin/env bash
set -euo pipefail

echo "== Q13 Lab Setup — restricted PSA + nginx-unprivileged (broken by PSA) =="

NS="confidential"
DEP="nginx-unprivileged"
MANIFEST="$HOME/nginx-unprivileged.yaml"
BACKUP_DIR="/root/cis-q13-backups-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need kubectl

# [0] Namespace + restricted PSA labels
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null
kubectl label ns "$NS"   pod-security.kubernetes.io/enforce=restricted   pod-security.kubernetes.io/enforce-version=latest   pod-security.kubernetes.io/warn=restricted   pod-security.kubernetes.io/warn-version=latest   pod-security.kubernetes.io/audit=restricted   pod-security.kubernetes.io/audit-version=latest   --overwrite >/dev/null

# [1] Write the manifest (correct image+port), but intentionally NOT compliant with restricted PSA.
#     This ensures the ReplicaSet will fail to create pods (exam-style).
cat > "$MANIFEST" <<'YAML'
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
      # Intentionally missing restricted-required fields:
      # - securityContext.runAsNonRoot
      # - securityContext.seccompProfile
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged:1.25-alpine
        ports:
        - containerPort: 8080
        securityContext:
          # Intentionally violates restricted:
          allowPrivilegeEscalation: true
          capabilities:
            add:
            - NET_ADMIN
YAML

cp -f "$MANIFEST" "$BACKUP_DIR/nginx-unprivileged.yaml.original"

# [2] Apply (expected to create Deployment/RS; RS will be blocked from creating Pods by PSA)
kubectl -n "$NS" apply -f "$MANIFEST" >/dev/null || true

echo
echo "Manifest location:"
echo "  $MANIFEST"
echo "Backup copy:"
echo "  $BACKUP_DIR/nginx-unprivileged.yaml.original"
echo
echo "Expected initial state:"
echo "  - Deployment/ReplicaSet exists"
echo "  - ReplicaSet fails to create Pods due to PodSecurity 'restricted' enforcement"
echo
echo "Validation commands:"
echo "  kubectl -n $NS get deploy,rs,pods"
echo "  kubectl -n $NS describe rs -l app=$DEP | sed -n '/Events:/,\$p'"
echo
echo "✅ Q13 environment ready."
