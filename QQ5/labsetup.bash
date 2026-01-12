#!/usr/bin/env bash
set -euo pipefail

NS="ai"
DEP_BAD="ollama"
DEP_GOOD="helper"
HOST_DEVMEM="/opt/lab/devmem"

log(){ echo "[labsetup] $*"; }

ensure_docker() {
  log "Ensuring Docker Engine is installed and running..."

  if ! command -v docker >/dev/null 2>&1; then
    log "Docker not found. Installing docker.io..."
    sudo apt-get update -y
    sudo apt-get install -y docker.io
  else
    log "Docker binary detected."
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable docker >/dev/null 2>&1 || true
    sudo systemctl start docker  >/dev/null 2>&1 || true
  else
    sudo service docker start >/dev/null 2>&1 || true
  fi

  sudo docker info >/dev/null 2>&1 || { log "ERROR: Docker daemon not responding"; exit 1; }
  log "Docker is running."
}

detect_k8s_runtime() {
  local runtime="unknown"
  if command -v crictl >/dev/null 2>&1; then
    runtime="$(crictl info 2>/dev/null | grep -E '"runtimeType"|runtimeType' -m1 || true)"
  fi
  log "Kubernetes runtime hint: ${runtime:-unknown} (docker may not show k8s containers if runtime != docker)"
}

ensure_devmem_on_node() {
  local node="$1"
  local path="$HOST_DEVMEM"
  local dir
  dir="$(dirname "$path")"

  local cmd="
set -euo pipefail
sudo mkdir -p '$dir'
# If path exists as directory, remove and recreate as file
if sudo test -d '$path'; then sudo rm -rf '$path'; fi
# Create file if missing
if ! sudo test -f '$path'; then echo 'SIMULATED_KERNEL_MEMORY_DO_NOT_READ' | sudo tee '$path' >/dev/null; fi
sudo chmod 600 '$path'
sudo test -f '$path'
"

  if [[ "$node" == "$(hostname)" ]]; then
    log "Ensuring ${path} is a file on local node (${node})"
    bash -lc "$cmd"
  else
    log "Ensuring ${path} is a file on remote node (${node})"
    ssh -o StrictHostKeyChecking=no "$node" "bash -lc $(printf %q "$cmd")"
  fi
}

ensure_devmem_on_all_nodes() {
  log "Ensuring simulated /dev/mem exists on ALL nodes (hostPath is node-local)"
  mapfile -t nodes < <(kubectl get nodes -o name | sed 's|node/||')
  for n in "${nodes[@]}"; do
    ensure_devmem_on_node "$n"
  done
}

log "Step 0: Ensure Docker is running"
ensure_docker
detect_k8s_runtime

log "Step 1: Create namespace ${NS}"
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}"

log "Step 1b: Allow privileged workloads in ${NS} (PSA compatibility)"
kubectl label ns "${NS}" pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label ns "${NS}" pod-security.kubernetes.io/audit=privileged --overwrite
kubectl label ns "${NS}" pod-security.kubernetes.io/warn=privileged --overwrite

log "Step 2: Create simulated host /dev/mem at ${HOST_DEVMEM} (all nodes)"
ensure_devmem_on_all_nodes

log "Step 3: Create baseline deployment ${DEP_GOOD}"
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

log "Step 4: Create misbehaving deployment ${DEP_BAD} (forced to controlplane)"
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
      nodeSelector:
        kubernetes.io/hostname: controlplane
      tolerations:
      - key: "node-role.kubernetes.io/control-plane"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: ${DEP_BAD}
        image: busybox:1.36
        command:
          - sh
          - -lc
          - |
            echo "[ollama] starting; simulating /dev/mem read loop";
            while true; do
              echo "[ollama] reading /dev/mem...";
              dd if=/dev/mem bs=16 count=1 2>/dev/null | hexdump -C | head -n 1 || true;
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

log "Step 5: Wait for rollouts"
kubectl -n "${NS}" rollout status deploy/"${DEP_GOOD}" --timeout=180s
kubectl -n "${NS}" rollout status deploy/"${DEP_BAD}" --timeout=180s

echo
log "Lab ready."
echo "Quick checks:"
echo "  sudo docker info | head -n 5"
echo "  kubectl -n ${NS} get pods -o wide"
echo "  kubectl -n ${NS} logs -l app=${DEP_BAD} --tail=10"
