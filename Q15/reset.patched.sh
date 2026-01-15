#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-mtls}"
DECOY_NS="${DECOY_NS:-mtls-decoy}"
MISLEAD_NS="${MISLEAD_NS:-mtls1}"

# Pin netshoot to reduce image-pull variance in shared lab environments.
# You can override: NETSHOOT_IMAGE=nicolaka/netshoot:latest bash reset.sh
NETSHOOT_IMAGE="${NETSHOOT_IMAGE:-nicolaka/netshoot:v0.13}"

echo "== Reset Q15 to vulnerable/broken baseline =="

# Ensure Istio exists (CRDs + istio-system namespace). Reset assumes labsetup already installed it.
kubectl get ns istio-system >/dev/null 2>&1 || {
  echo "[ERROR] istio-system missing. Run ./labsetup.sh first (it installs Istio)." >&2
  exit 2
}

require_istio_webhook_ready() {
  # Best-effort: ensure istiod is serving before the candidate enables injection.
  kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null || true
  local eps
  eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  if [ -z "$eps" ]; then
    kubectl -n istio-system rollout restart deploy/istiod >/dev/null || true
    kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null || true
  fi
}

# Ensure namespaces exist
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}" >/dev/null
kubectl get ns "${DECOY_NS}" >/dev/null 2>&1 || kubectl create ns "${DECOY_NS}" >/dev/null
kubectl get ns "${MISLEAD_NS}" >/dev/null 2>&1 || kubectl create ns "${MISLEAD_NS}" >/dev/null

# Remove injection labels from target ns; keep on decoys
kubectl label ns "${NS}" istio-injection- --overwrite >/dev/null 2>&1 || true
kubectl label ns "${NS}" istio.io/rev- --overwrite >/dev/null 2>&1 || true
kubectl label ns "${DECOY_NS}" istio-injection=enabled --overwrite >/dev/null 2>&1 || true
kubectl label ns "${MISLEAD_NS}" istio-injection=enabled --overwrite >/dev/null 2>&1 || true

# Recreate workloads
kubectl -n "${NS}" delete deploy,tcp-echo svc tcp-echo --ignore-not-found >/dev/null 2>&1 || true
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

# Restore PERMISSIVE policy in target ns (must be changed to STRICT by candidate)
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

# Restore decoy STRICT policy in istio-system
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

kubectl -n "${NS}" rollout status deploy/tcp-echo --timeout=180s >/dev/null
kubectl -n "${NS}" rollout status deploy/tcp-client --timeout=180s >/dev/null

# Reduce likelihood of injector webhook timeouts when the candidate enables injection
require_istio_webhook_ready

echo "Reset complete."
echo "Run: ./question.sh"
