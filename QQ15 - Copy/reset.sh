#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-mtls}"
DECOY_NS="${DECOY_NS:-mtls-decoy}"
MISLEAD_NS="${MISLEAD_NS:-mtls1}"
NETSHOOT_IMAGE="${NETSHOOT_IMAGE:-nicolaka/netshoot:v0.13}"

fail(){ echo "[ERROR] $*" >&2; exit 2; }

echo "== Reset Q15 to vulnerable/broken baseline =="

kubectl get ns istio-system >/dev/null 2>&1 || fail "istio-system missing. Run ./labsetup.sh first."

# Ensure istiod is healthy to avoid fail-closed webhook blocking Pod creation later
kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null || true
eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
if [ -z "$eps" ]; then
  echo "[WARN] istiod has no endpoints; restarting istiod..."
  kubectl -n istio-system rollout restart deploy/istiod >/dev/null
  kubectl -n istio-system rollout status deploy/istiod --timeout=240s >/dev/null
fi
eps="$(kubectl -n istio-system get endpoints istiod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
[ -n "$eps" ] || fail "istiod still has no endpoints; injection can fail closed."

# Ensure namespaces exist
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}" >/dev/null
kubectl get ns "${DECOY_NS}" >/dev/null 2>&1 || kubectl create ns "${DECOY_NS}" >/dev/null
kubectl get ns "${MISLEAD_NS}" >/dev/null 2>&1 || kubectl create ns "${MISLEAD_NS}" >/dev/null

# Target namespace starts WITHOUT injection
kubectl label ns "${NS}" istio-injection- --overwrite >/dev/null 2>&1 || true
kubectl label ns "${NS}" istio.io/rev- --overwrite >/dev/null 2>&1 || true

# Decoys have injection ENABLED (revision-based) and must NOT have istio-injection set
kubectl label ns "${DECOY_NS}" istio.io/rev=default --overwrite >/dev/null 2>&1 || true
kubectl label ns "${DECOY_NS}" istio-injection- --overwrite >/dev/null 2>&1 || true
kubectl label ns "${MISLEAD_NS}" istio.io/rev=default --overwrite >/dev/null 2>&1 || true
kubectl label ns "${MISLEAD_NS}" istio-injection- --overwrite >/dev/null 2>&1 || true

# Recreate workloads in target namespace
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

# Restore PERMISSIVE policy in target ns (candidate must change to STRICT)
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

echo "Reset complete."
echo "Run: ./question.sh"
