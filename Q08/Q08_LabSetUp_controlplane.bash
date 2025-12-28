#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up NetworkPolicy lab (Q08) — CONTROLPLANE (kubeadm)"

BASE_DIR="/root/sims/Q08"
mkdir -p "${BASE_DIR}"
cd "${BASE_DIR}"

TS="$(date +%Y%m%d%H%M%S)"
BK="/root/cis-q08-backups-${TS}"
mkdir -p "${BK}"

echo "📦 Backup dir: ${BK}"

# Namespaces for the sim
# We label namespaces with cis-q08=true so cleanup can safely remove what we create.
for ns in prod data dev; do
  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    kubectl create ns "${ns}" >/dev/null
  fi
  kubectl label ns "${ns}" cis-q08=true --overwrite >/dev/null
  kubectl label ns "${ns}" "env=${ns}" --overwrite >/dev/null
done

# prod namespace should be labeled env=prod; data env=data (already done above)
# Create simple services/deployments to validate policies functionally.

echo "🧩 Creating test deployments/services and client pods..."

# PROD: a small nginx server (to validate deny-policy blocks ingress)
cat > "${BK}/prod-web.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-web
  namespace: prod
  labels:
    app: prod-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prod-web
  template:
    metadata:
      labels:
        app: prod-web
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
  name: prod-web
  namespace: prod
spec:
  selector:
    app: prod-web
  ports:
  - port: 80
    targetPort: 80
YAML
kubectl apply -f "${BK}/prod-web.yaml" >/dev/null

# DATA: nginx server to validate allow-from-prod in data
cat > "${BK}/data-web.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-web
  namespace: data
  labels:
    app: data-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-web
  template:
    metadata:
      labels:
        app: data-web
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
  name: data-web
  namespace: data
spec:
  selector:
    app: data-web
  ports:
  - port: 80
    targetPort: 80
YAML
kubectl apply -f "${BK}/data-web.yaml" >/dev/null

# Client pods (already running, user must NOT modify them)
cat > "${BK}/clients.yaml" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: prod-tester
  namespace: prod
  labels:
    app: tester
spec:
  containers:
  - name: bb
    image: busybox:1.36
    command: ["sh","-c","sleep 365d"]
---
apiVersion: v1
kind: Pod
metadata:
  name: dev-tester
  namespace: dev
  labels:
    app: tester
spec:
  containers:
  - name: bb
    image: busybox:1.36
    command: ["sh","-c","sleep 365d"]
YAML
kubectl apply -f "${BK}/clients.yaml" >/dev/null

# Wait for readiness
kubectl -n prod rollout status deploy/prod-web --timeout=120s >/dev/null || true
kubectl -n data rollout status deploy/data-web --timeout=120s >/dev/null || true
kubectl -n prod wait --for=condition=Ready pod/prod-tester --timeout=120s >/dev/null || true
kubectl -n dev  wait --for=condition=Ready pod/dev-tester  --timeout=120s >/dev/null || true

# Helpful output
echo "✅ Q08 environment ready."
echo "   Namespaces: prod (env=prod), data (env=data), dev (env=dev)"
echo "   Services:   prod/prod-web, data/data-web"
echo "   Clients:    prod/prod-tester, dev/dev-tester"
echo
echo "Next: read Q08_Questions.bash for the task."
