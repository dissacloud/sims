#!/usr/bin/env bash
set -euo pipefail

echo "== Q13 Lab Setup v2 — Restricted PSA + Noncompliant nginx-unprivileged =="

NS="confidential"
MANIFEST="$HOME/nginx-unprivileged.yaml"
BACKUP_DIR="/root/cis-q13-backups-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

# [0] Namespace + enforce restricted PSA labels
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

# Enforce restricted in this namespace (exam-style); also set warn/audit for visibility
kubectl label ns "$NS" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  --overwrite >/dev/null

# [1] Write a manifest that uses the RIGHT image + port, but is INTENTIONALLY NOT COMPLIANT
# so Pods will be forbidden by PSA restricted.
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
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged:1.25-alpine
        ports:
        - containerPort: 8080
        # Intentionally noncompliant fields (restricted PSA should block pod creation):
        securityContext:
          privileged: true
          allowPrivilegeEscalation: true
          capabilities:
            add: ["NET_ADMIN"]
          runAsNonRoot: false
YAML

cp -f "$MANIFEST" "$BACKUP_DIR/nginx-unprivileged.yaml.original"

# [2] Apply — expected outcome is PSA forbids Pod creation
kubectl -n "$NS" apply -f "$MANIFEST" >/dev/null || true

echo
echo "Manifest location:"
echo "  $MANIFEST"
echo
echo "Expected failure mode (exam-style):"
echo "  ReplicaSet events should show PodSecurity restricted violations."
echo
echo "Quick checks:"
echo "  kubectl -n $NS get deploy,rs,pods"
echo "  kubectl -n $NS describe rs -l app=nginx-unprivileged | sed -n '/Events:/,\$p'"
echo
echo "✅ Q13 environment ready (noncompliant deployment present; pods should be blocked)."
