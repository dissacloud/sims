#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-mtls}"
DECOY_NS="${DECOY_NS:-mtls-decoy}"
MISLEAD_NS="${MISLEAD_NS:-mtls1}"

ISTIO_VERSION="${ISTIO_VERSION:-1.22.3}"

# Pinned images (avoid :latest drift)
NETSHOOT_IMAGE="${NETSHOOT_IMAGE:-nicolaka/netshoot:v0.13}"

echo "== Q15 Lab Setup (Istio L4 mTLS strict) =="
echo "Target namespace: ${NS}"
echo "Decoy namespace:  ${DECOY_NS}"
echo "Mislead namespace:${MISLEAD_NS}"
echo "Istio version:    ${ISTIO_VERSION}"
echo "Workload image:   ${NETSHOOT_IMAGE}"

ensure_istio() {
  if kubectl get ns istio-system >/dev/null 2>&1; then
    echo "[OK] istio-system already exists"
    return 0
  fi

  echo "[WARN] istio-system namespace not found. Installing Istio..."

  if ! command -v curl >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null
    sudo apt-get install -y curl >/dev/null
  fi

  echo "[INFO] Downloading Istio ${ISTIO_VERSION}..."
  curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" sh - >/dev/null

  local ISTIO_DIR="istio-${ISTIO_VERSION}"
  export PATH="$PWD/${ISTIO_DIR}/bin:$PATH"

  echo "[INFO] Installing Istio control plane (demo profile)..."
  istioctl install -y --set profile=demo >/dev/null

  echo "[INFO] Waiting for istiod..."
  kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null

  echo "[OK] Istio installed"
}

detect_injection_hint() {
  # Purpose: provide a stable hint to the lab author (not required for candidates)
  # We inspect namespaceSelector in common injector configs.
  local hint="istio-injection=enabled"
  if kubectl get mutatingwebhookconfiguration istio-sidecar-injector >/dev/null 2>&1; then
    local sel
    sel="$(kubectl get mutatingwebhookconfiguration istio-sidecar-injector -o jsonpath='{.webhooks[0].namespaceSelector}' 2>/dev/null || true)"
    if echo "$sel" | grep -q 'istio.io/rev'; then
      hint="istio.io/rev=default"
    fi
  fi
  echo "$hint"
}

ensure_istio

echo "[1] Istio control plane status:"
kubectl -n istio-system get pods

# Namespaces
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}" >/dev/null
kubectl get ns "${DECOY_NS}" >/dev/null 2>&1 || kubectl create ns "${DECOY_NS}" >/dev/null
kubectl get ns "${MISLEAD_NS}" >/dev/null 2>&1 || kubectl create ns "${MISLEAD_NS}" >/dev/null

# Start BROKEN: remove injection labels from target namespace
kubectl label ns "${NS}" istio-injection- --overwrite >/dev/null 2>&1 || true
kubectl label ns "${NS}" istio.io/rev- --overwrite >/dev/null 2>&1 || true

# TRAPS: decoys have injection enabled
kubectl label ns "${DECOY_NS}" istio-injection=enabled --overwrite >/dev/null 2>&1 || true
kubectl label ns "${MISLEAD_NS}" istio-injection=enabled --overwrite >/dev/null 2>&1 || true

# Workloads in target namespace (pods must start WITHOUT sidecars)
kubectl -n "${NS}" delete deploy,svc --all --ignore-not-found >/dev/null 2>&1 || true

cat <<EOF | kubectl -n "${NS}" apply -f -
apiVersion: v1
kind: Service
metadata:
  name: tcp-echo
spec:
  selector:
    app: tcp-echo
  ports:
  - name: tcp
    port: 9000
    targetPort: 9000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tcp-echo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tcp-echo
  template:
    metadata:
      labels:
        app: tcp-echo
    spec:
      containers:
      - name: server
        image: ${NETSHOOT_IMAGE}
        command: ["/bin/sh","-lc"]
        args:
          - |
            # netshoot is alpine-based; ensure socat exists
            apk add --no-cache socat >/dev/null 2>&1 || true
            while true; do socat -T 1 -v TCP-LISTEN:9000,reuseaddr,fork EXEC:'/bin/cat'; done
        ports:
        - containerPort: 9000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tcp-client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tcp-client
  template:
    metadata:
      labels:
        app: tcp-client
    spec:
      containers:
      - name: client
        image: ${NETSHOOT_IMAGE}
        command: ["/bin/sh","-lc"]
        args:
          - |
            sleep 365d
EOF

# Baseline PeerAuthentication in target: PERMISSIVE (must become STRICT)
kubectl -n "${NS}" delete peerauthentication default --ignore-not-found >/dev/null 2>&1 || true
cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ${NS}
spec:
  mtls:
    mode: PERMISSIVE
EOF

# Decoy STRICT policy in istio-system
cat <<'EOF' | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: strict-decoy
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF

echo "[2] Waiting for workloads..."
kubectl -n "${NS}" rollout status deploy/tcp-echo --timeout=180s >/dev/null
kubectl -n "${NS}" rollout status deploy/tcp-client --timeout=180s >/dev/null

echo
echo "== Lab state summary =="
echo "- Target ns '${NS}' labels (should NOT include injection labels):"
kubectl get ns "${NS}" --show-labels
echo "- Decoy ns '${DECOY_NS}' labels (should include injection):"
kubectl get ns "${DECOY_NS}" --show-labels
echo "- Mislead ns '${MISLEAD_NS}' labels (should include injection):"
kubectl get ns "${MISLEAD_NS}" --show-labels
echo "- Target pods (should have NO istio-proxy at baseline):"
kubectl -n "${NS}" get pods
echo "- Target PeerAuthentication/default (PERMISSIVE baseline):"
kubectl -n "${NS}" get peerauthentication default -o jsonpath='{.spec.mtls.mode}{"\n"}'

echo
echo "Lab author hint (detected injector preference): $(detect_injection_hint)"
echo "Run: ./question.sh"
