#!/usr/bin/env bash
set -euo pipefail

NS="ai"
DEP_BAD="ollama"
DEP_GOOD="helper"
HOST_DEVMEM="/opt/lab/devmem"   # host file that will be mounted as /dev/mem inside container

log(){ echo "[labsetup] $*"; }

ensure_docker() {
  log "Ensuring Docker Engine is installed and running..."

  if ! command -v docker >/dev/null 2>&1; then
    log "Docker not found. Installing docker.io (Debian/Ubuntu)..."
    sudo apt-get update -y
    sudo apt-get install -y docker.io
  else
    log "Docker binary detected."
  fi

  # Start/enable (systemd-based environments)
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable docker >/dev/null 2>&1 || true
    sudo systemctl start docker >/dev/null 2>&1 || true
  else
    # Fallback start (non-systemd)
    sudo service docker start >/dev/null 2>&1 || true
  fi

  # Verify docker daemon responds
  if ! sudo docker info >/dev/null 2>&1; then
    log "ERROR: Docker daemon is not responding."
    log "Try: sudo systemctl status docker --no-pager  (or sudo service docker status)"
    exit 1
  fi

  log "Docker is running: $(sudo docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'ok')"
}

log "Step 0: Ensure Docker is running"
ensure_docker

log "Step 1: Create namespace: ${NS}"
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}"

log "Step 2: Create simulated host /dev/mem file at ${HOST_DEVMEM}"
sudo mkdir -p "$(dirname "${HOST_DEVMEM}")"
echo "SIMULATED_KERNEL_MEMORY_DO_NOT_READ" | sudo tee "${HOST_DEVMEM}" >/dev/null
sudo chmod 600 "${HOST_DEVMEM}"

log "Step 3: Create GOOD baseline deployment (${DEP_GOOD})"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEP_GOOD}
  namespace: ${NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DEP_GOOD}
  template:
    metadata:
      labels:
        app: ${DEP_GOOD}
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh","-lc","while true; do echo helper_ok; sleep 30; done"]
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
EOF

log "Step 4: Create MISBEHAVING deployment (${DEP_BAD}) that reads /dev/mem"
# It mounts a host file into container at /dev/mem and reads it in a loop.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEP_BAD}
  namespace: ${NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DEP_BAD}
  template:
    metadata:
      labels:
        app: ${DEP_BAD}
    spec:
      containers:
      - name: ${DEP_BAD}
        image: busybox:1.36
        command:
          - sh
          - -lc
          - |
            echo "[ollama] starting; simulating /dev/mem read loop";
            while true; do
              dd if=/dev/mem bs=32 count=1 2>/dev/null | hexdump -C | head -n 1 || true;
              sleep 2;
            done
        volumeMounts:
        - name: devmem
          mountPath: /dev/mem
          readOnly: true
        securityContext:
          privileged: true
      volumes:
      - name: devmem
        hostPath:
          path: ${HOST_DEVMEM}
          type: File
EOF

log "Step 5: Wait for pods"
kubectl -n "${NS}" rollout status deploy/"${DEP_GOOD}" --timeout=120s
kubectl -n "${NS}" rollout status deploy/"${DEP_BAD}" --timeout=120s

echo
log "Done."
echo "Check:"
echo "  kubectl -n ${NS} get pods -o wide"
echo "  kubectl -n ${NS} logs -l app=${DEP_BAD} --tail=10"
echo
echo "Docker validation:"
echo "  sudo docker info | head"
