#!/usr/bin/env bash
set -euo pipefail

kubectl get ns ollama >/dev/null 2>&1 || kubectl create ns ollama

# Benign workload
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

# Misbehaving workload: attempts to open/read /dev/mem repeatedly
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
            echo "[scraper] starting";
            while true; do
              # The open attempt is the signal; reads may fail depending on kernel settings.
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

kubectl -n ollama rollout status deploy/ollama-api --timeout=120s
kubectl -n ollama rollout status deploy/ollama-memory-scraper --timeout=120s

echo
echo "SIM-Q05 setup complete."
echo "Now solve using node/runtime inspection (NO Falco)."


