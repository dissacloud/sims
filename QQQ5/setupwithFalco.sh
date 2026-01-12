#!/usr/bin/env bash
set -euo pipefail

# Namespace + workloads (same as Sim A)
kubectl get ns ollama >/dev/null 2>&1 || kubectl create ns ollama

kubectl -n ollama apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama-api
  labels: {app: ollama-api}
spec:
  replicas: 1
  selector: {matchLabels: {app: ollama-api}}
  template:
    metadata: {labels: {app: ollama-api}}
    spec:
      containers:
      - name: api
        image: nginx:1.25-alpine
        ports: [{containerPort: 80}]
YAML

kubectl -n ollama apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama-memory-scraper
  labels: {app: ollama-memory-scraper}
spec:
  replicas: 1
  selector: {matchLabels: {app: ollama-memory-scraper}}
  template:
    metadata: {labels: {app: ollama-memory-scraper}}
    spec:
      containers:
      - name: scraper
        image: alpine:3.19
        securityContext:
          privileged: true
        command: ["/bin/sh","-c"]
        args:
          - |
            echo "[scraper] attempting /dev/mem reads";
            while true; do
              dd if=/dev/mem of=/dev/null bs=1 count=1 2>/dev/null || true
              sleep 2
            done
        volumeMounts:
        - name: devmem
          mountPath: /dev/mem
          readOnly: true
      volumes:
      - name: devmem
        hostPath:
          path: /dev/mem
          type: CharDevice
YAML

# Install Falco
if ! command -v helm >/dev/null 2>&1; then
  echo "Helm not found. Install it in your base scenario or use a Helm-enabled Killercoda environment."
  exit 1
fi

kubectl get ns falco >/dev/null 2>&1 || kubectl create ns falco
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true

helm upgrade --install falco falcosecurity/falco -n falco \
  --set falco.jsonOutput=false \
  --set falco.logSyslog=false \
  --set driver.kind=ebpf \
  --set tty=true

# Add custom rule for /dev/mem open/read
kubectl -n falco apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-custom-rules
data:
  custom-rules.yaml: |
    - rule: Read from /dev/mem
      desc: Detect attempts to open /dev/mem for reading
      condition: (evt.type in (open,openat,openat2) and fd.name=/dev/mem and evt.is_open_read=true)
      output: "SECURITY: /dev/mem read attempt (file=%fd.name proc=%proc.name user=%user.name container=%container.name k8s.ns=%k8s.ns.name k8s.pod=%k8s.pod.name)"
      priority: CRITICAL
YAML

# Patch Falco DaemonSet to mount rules.d
kubectl -n falco patch ds falco --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"custom-rules","configMap":{"name":"falco-custom-rules"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"custom-rules","mountPath":"/etc/falco/rules.d","readOnly":true}}
]'

kubectl -n falco rollout status ds/falco --timeout=300s
kubectl -n ollama rollout status deploy/ollama-api --timeout=120s
kubectl -n ollama rollout status deploy/ollama-memory-scraper --timeout=120s

echo "Setup complete. Now use Falco to identify the offending pod and scale ONLY its Deployment to 0."
