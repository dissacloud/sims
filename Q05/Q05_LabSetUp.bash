#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up misbehaving pod containment lab (Q05 v1)"

NS="ollama"
REPORT="/root/kube-bench-report-q05.txt"
BACKUP_ROOT="/root"
ts="$(date +%Y%m%d%H%M%S)"
backup_dir="${BACKUP_ROOT}/cis-q05-backups-${ts}"
mkdir -p "${backup_dir}"

echo "📦 Creating namespace: ${NS}"
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}"

echo
echo "🧩 Deploying application pods for app=ollama (one is intentionally misbehaving)..."

# Benign deployment
cat <<'EOF' | kubectl -n "${NS}" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama-api
  labels:
    app: ollama
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
      component: api
  template:
    metadata:
      labels:
        app: ollama
        component: api
    spec:
      containers:
      - name: api
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
EOF

# Misbehaving deployment: mounts host /dev/mem and attempts to read from it (simulates direct system memory access)
cat <<'EOF' | kubectl -n "${NS}" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama-memory-scraper
  labels:
    app: ollama
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
      component: worker
  template:
    metadata:
      labels:
        app: ollama
        component: worker
    spec:
      containers:
      - name: scraper
        image: busybox:1.36
        securityContext:
          privileged: true
        command:
        - /bin/sh
        - -c
        - |
          echo "[Q05] starting memory scrape loop (simulated)";
          while true; do
            echo "[Q05] attempting read from /dev/mem at $(date -Iseconds)";
            # This may fail depending on kernel hardening; attempt is sufficient for the lab.
            dd if=/dev/mem bs=1 count=1 2>/tmp/mem.err >/tmp/mem.out || true;
            tail -n 1 /tmp/mem.err 2>/dev/null || true;
            sleep 5;
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
EOF

echo
echo "📦 Backing up deployed resources to: ${backup_dir}"
kubectl -n "${NS}" get deploy -o yaml > "${backup_dir}/deployments.yaml"
kubectl -n "${NS}" get pods -o yaml > "${backup_dir}/pods.yaml" || true

echo
echo "📝 Writing simulated findings report: ${REPORT}"
cat > "${REPORT}" <<'EOF'
# Q05 Findings (SIMULATED) — Runtime threat containment
# Context: One pod belonging to application 'ollama' is misbehaving and reading from /dev/mem.

[INFO] Workload inventory
- Namespace: ollama
- Application label: app=ollama

[FAIL] RUNTIME Pod is accessing /dev/mem (direct system memory access)
       * Expected action:
         1) Identify the misbehaving Pod accessing /dev/mem
         2) Identify the Deployment managing it
         3) Scale that Deployment to 0 replicas
       * Constraints:
         - Do NOT modify the Deployment except scaling it down
         - Do NOT modify any other Deployments
         - Do NOT delete any Deployments

== Summary ==
1 task outstanding
EOF

echo
echo "⏳ Waiting for pods to be Ready..."
kubectl -n "${NS}" rollout status deploy/ollama-api --timeout=120s >/dev/null 2>&1 || true
kubectl -n "${NS}" rollout status deploy/ollama-memory-scraper --timeout=120s >/dev/null 2>&1 || true

echo
echo "✅ Q05 lab setup complete."
echo "Hints:"
echo "  - Read report: sudo cat ${REPORT}"
echo "  - List pods: kubectl -n ${NS} get pods -o wide"
echo "  - Check pod spec for /dev/mem mounts"
echo "  - Use docker if needed: docker ps / docker logs"
