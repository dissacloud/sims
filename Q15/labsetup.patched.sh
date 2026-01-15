#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-mtls}"
DECOY_NS="${DECOY_NS:-mtls-decoy}"
MISLEAD_NS="${MISLEAD_NS:-mtls1}"

# Choose an Istio version that is known-stable for labs.
# You can override at runtime: ISTIO_VERSION=1.22.3 bash labsetup.sh
ISTIO_VERSION="${ISTIO_VERSION:-1.22.3}"

# Pin netshoot to reduce image-pull variance in shared lab environments.
# You can override: NETSHOOT_IMAGE=nicolaka/netshoot:latest bash labsetup.sh
NETSHOOT_IMAGE="${NETSHOOT_IMAGE:-nicolaka/netshoot:v0.13}"

echo "== Q15 Lab Setup (Istio L4 mTLS strict) =="
echo "Target namespace: ${NS}"
echo "Decoy namespace:  ${DECOY_NS}"
echo "Istio version:    ${ISTIO_VERSION}"

ensure_istio() {
  if kubectl get ns istio-system >/dev/null 2>&1; then
    echo "[OK] istio-system already exists"
    return 0
  fi

  echo "[WARN] istio-system namespace not found. Installing Istio..."

  # Ensure curl exists
  if ! command -v curl >/dev/null 2>&1; then
    echo "[INFO] curl not found; installing..."
    sudo apt-get update -y >/dev/null
    sudo apt-get install -y curl >/dev/null
  fi

  # Download Istio (includes istioctl)
  # This uses the official Istio download script.
  # If outbound egress is blocked in your lab, this will fail.
  echo "[INFO] Downloading Istio ${ISTIO_VERSION}..."
  curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" sh - >/dev/null

  local ISTIO_DIR="istio-${ISTIO_VERSION}"
  if [ ! -d "${ISTIO_DIR}" ]; then
    echo "[ERROR] Istio directory ${ISTIO_DIR} not found after download." >&2
    exit 2
  fi

  export PATH="$PWD/${ISTIO_DIR}/bin:$PATH"

  if ! command -v istioctl >/dev/null 2>&1; then
    echo "[ERROR] istioctl not available after download. Check PATH." >&2
    exit 2
  fi

  echo "[INFO] Installing Istio control plane (demo profile)..."
  istioctl install -y --set profile=demo >/dev/null

  echo "[INFO] Waiting for istiod..."
  kubectl -n istio-system rollout status deploy/istiod --timeout=180s >/dev/null

  echo "[OK] Istio installed"
}

require_istio_webhook_ready() {
  echo "[INFO] Verifying Istio webhook path is ready..."

  # 1) Wait for istiod rollout
  kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null || true

  # 2) Require endpoints to exist (webhook depends on service routing)
  local eps
  eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  if [ -z "$eps" ]; then
    echo "[WARN] istiod has no endpoints yet; restarting istiod"
    kubectl -n istio-system rollout restart deploy/istiod >/dev/null || true
    kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null || true
  fi

  eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  [ -n "$eps" ] || { echo "[ERROR] istiod still has no endpoints; webhook calls will fail"; return 1; }

  # 3) Basic in-cluster reachability check to istiod:443 (best-effort)
  kubectl create ns tmp-debug >/dev/null 2>&1 || true
  if ! kubectl -n tmp-debug run curl --image=curlimages/curl:8.5.0 --restart=Never -i --rm --         sh -lc 'nslookup istiod.istio-system.svc >/dev/null 2>&1 && (echo | timeout 3 nc -v istiod.istio-system.svc 443 >/dev/null 2>&1)'         >/dev/null 2>&1; then
    echo "[WARN] istiod:443 not reachable from a pod yet; restarting istiod once"
    kubectl -n istio-system rollout restart deploy/istiod >/dev/null || true
    kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null || true
  fi

  echo "[OK] Istio webhook path appears ready"
  return 0
}

ensure_istio

echo "[1] Verify Istio control plane (istiod) exists"
kubectl -n istio-system get pods

# Extra guard: reduce webhook timeouts in noisy lab environments
require_istio_webhook_ready || true

# 2) Create target namespace (mtls) with injection DISABLED initially
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}" >/dev/null

# Remove any injection labels to start "broken"
kubectl label ns "${NS}" istio-injection- --overwrite >/dev/null 2>&1 || true
kubectl label ns "${NS}" istio.io/rev- --overwrite >/dev/null 2>&1 || true

# TRAP: Create a decoy namespace that ALREADY has injection enabled
kubectl get ns "${DECOY_NS}" >/dev/null 2>&1 || kubectl create ns "${DECOY_NS}" >/dev/null
kubectl label ns "${DECOY_NS}" istio-injection=enabled --overwrite >/dev/null

# TRAP: Another “looks-correct” namespace name variant (common mistake)
kubectl get ns "${MISLEAD_NS}" >/dev/null 2>&1 || kubectl create ns "${MISLEAD_NS}" >/dev/null
kubectl label ns "${MISLEAD_NS}" istio-injection=enabled --overwrite >/dev/null

# 3) Deploy simple TCP server + client in the TARGET namespace (without sidecars)
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
            apk add --no-cache socat >/dev/null 2>&1 || true
            while true; do socat -v TCP-LISTEN:9000,reuseaddr,fork EXEC:'/bin/cat'; done
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

# 4) Add a PERMISSIVE PeerAuthentication in the target namespace (must be changed to STRICT)
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

# TRAP: Decoy STRICT policy in wrong namespace (istio-system)
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

echo "[5] Wait for pods"
kubectl -n "${NS}" rollout status deploy/tcp-echo --timeout=180s
kubectl -n "${NS}" rollout status deploy/tcp-client --timeout=180s

echo
echo "== Lab state summary =="
echo "- Target ns '${NS}' injection label (should be absent):"
kubectl get ns "${NS}" --show-labels
echo "- Decoy ns '${DECOY_NS}' injection label (enabled):"
kubectl get ns "${DECOY_NS}" --show-labels
echo "- Target ns pods (should have NO istio-proxy yet):"
kubectl -n "${NS}" get pods -o wide
echo "- Target PeerAuthentication (PERMISSIVE):"
kubectl -n "${NS}" get peerauthentication default -o yaml | sed -n '1,60p'
echo
echo "Run: ./question.sh"
