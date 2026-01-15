#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-mtls}"
DECOY_NS="${DECOY_NS:-mtls-decoy}"
MISLEAD_NS="${MISLEAD_NS:-mtls1}"

# Stable Istio version for labs; override if needed.
ISTIO_VERSION="${ISTIO_VERSION:-1.22.3}"

# Pin image tag for determinism (no :latest drift)
NETSHOOT_IMAGE="${NETSHOOT_IMAGE:-nicolaka/netshoot:v0.13}"

fail(){ echo "[ERROR] $*" >&2; exit 2; }

echo "== Q15 Lab Setup (Istio L4 mTLS strict) =="
echo "Target namespace: ${NS}"
echo "Decoy namespace:  ${DECOY_NS}"
echo "Mislead namespace:${MISLEAD_NS}"
echo "Istio version:    ${ISTIO_VERSION}"
echo "Workload image:   ${NETSHOOT_IMAGE}"
echo

ensure_istio() {
  if kubectl get ns istio-system >/dev/null 2>&1; then
    echo "[OK] istio-system already exists"
    return 0
  fi

  echo "[WARN] istio-system namespace not found. Installing Istio..."

  if ! command -v curl >/dev/null 2>&1; then
    echo "[INFO] curl not found; installing..."
    sudo apt-get update -y >/dev/null
    sudo apt-get install -y curl >/dev/null
  fi

  echo "[INFO] Downloading Istio ${ISTIO_VERSION}..."
  curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" sh - >/dev/null

  local ISTIO_DIR="istio-${ISTIO_VERSION}"
  [ -d "${ISTIO_DIR}" ] || fail "Istio directory ${ISTIO_DIR} not found after download."

  export PATH="$PWD/${ISTIO_DIR}/bin:$PATH"
  command -v istioctl >/dev/null 2>&1 || fail "istioctl not found after download (PATH issue)."

  echo "[INFO] Installing Istio control plane (demo profile)..."
  istioctl install -y --set profile=demo >/dev/null

  echo "[INFO] Waiting for istiod..."
  kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null

  echo "[OK] Istio installed"
}

require_istiod_ready() {
  echo "[INFO] Ensuring istiod is ready and has endpoints..."
  kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null || true

  local eps
  eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  if [ -z "${eps}" ]; then
    echo "[WARN] istiod has no endpoints. Restarting istiod..."
    kubectl -n istio-system rollout restart deploy/istiod >/dev/null
    kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null
  fi

  eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  [ -n "${eps}" ] || fail "istiod still has no endpoints; sidecar injection webhook will fail (fail-closed)."
  echo "[OK] istiod endpoints: ${eps}"
}

ensure_istio
require_istiod_ready

echo "[1] Verify Istio control plane"
kubectl -n istio-system get pods -o wide
echo

echo "[2] Verify revision-tag injector exists (this lab depends on it)"
kubectl get mutatingwebhookconfiguration istio-revision-tag-default >/dev/null 2>&1 \
  || fail "Expected MutatingWebhookConfiguration istio-revision-tag-default not found."
echo "Injector namespaceSelector:"
kubectl get mutatingwebhookconfiguration istio-revision-tag-default -o jsonpath='{.webhooks[0].namespaceSelector}{"\n"}'
echo

# Namespaces
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}" >/dev/null
kubectl get ns "${DECOY_NS}" >/dev/null 2>&1 || kubectl create ns "${DECOY_NS}" >/dev/null
kubectl get ns "${MISLEAD_NS}" >/dev/null 2>&1 || kubectl create ns "${MISLEAD_NS}" >/dev/null

# Target namespace starts BROKEN: injection disabled (remove both labels)
kubectl label ns "${NS}" istio.io/rev- --overwrite >/dev/null 2>&1 || true
kubectl label ns "${NS}" istio-injection- --overwrite >/dev/null 2>&1 || true

# TRAPS:
# Decoy namespaces already have injection enabled (REVISION-BASED).
# IMPORTANT: istio-injection label must NOT exist, per injector selector.
kubectl label ns "${DECOY_NS}" istio.io/rev=default --overwrite >/dev/null
kubectl label ns "${DECOY_NS}" istio-injection- --overwrite >/dev/null 2>&1 || true

kubectl label ns "${MISLEAD_NS}" istio.io/rev=default --overwrite >/dev/null
kubectl label ns "${MISLEAD_NS}" istio-injection- --overwrite >/dev/null 2>&1 || true

# Deploy workloads in target namespace (WITHOUT sidecars initially)
kubectl -n "${NS}" delete deploy,svc --all --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "${NS}" delete peerauthentication default --ignore-not-found >/dev/null 2>&1 || true

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

# PERMISSIVE baseline (candidate must set STRICT)
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

echo "[3] Wait for baseline pods (should be present; typically 1/1 each because injection is off in target ns)"
kubectl -n "${NS}" rollout status deploy/tcp-echo --timeout=180s >/dev/null
kubectl -n "${NS}" rollout status deploy/tcp-client --timeout=180s >/dev/null

echo
echo "== Lab state summary =="
echo "- Target ns '${NS}' labels (should NOT have istio.io/rev and should NOT have istio-injection):"
kubectl get ns "${NS}" --show-labels
echo "- Decoy ns '${DECOY_NS}' labels (should have istio.io/rev=default and NO istio-injection):"
kubectl get ns "${DECOY_NS}" --show-labels
echo "- Mislead ns '${MISLEAD_NS}' labels (should have istio.io/rev=default and NO istio-injection):"
kubectl get ns "${MISLEAD_NS}" --show-labels
echo "- Target pods:"
kubectl -n "${NS}" get pods -o wide
echo "- Target PeerAuthentication/default mode:"
kubectl -n "${NS}" get peerauthentication default -o jsonpath='{.spec.mtls.mode}{"\n"}'
echo
echo "Run: ./question.sh"
