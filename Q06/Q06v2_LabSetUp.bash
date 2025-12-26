#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up container immutability hardening lab (Q06 v2 — clean-running workload)"

NS="lamp"
DEPLOY="lamp-deployment"
WORKDIR="${HOME}/finer-sunbeam"
MANIFEST="${WORKDIR}/lamp-deployment.yaml"
REPORT="/root/kube-bench-report-q06.txt"

ts="$(date +%Y%m%d%H%M%S)"
backup_dir="/root/cis-q06-backups-${ts}"
mkdir -p "${backup_dir}"

echo "📦 Creating namespace: ${NS}"
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}"

echo "📦 Creating workdir: ${WORKDIR}"
mkdir -p "${WORKDIR}"

echo
echo "🧩 Writing intentionally non-compliant deployment manifest to: ${MANIFEST}"
cat > "${MANIFEST}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lamp-deployment
  namespace: lamp
  labels:
    app: lamp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lamp
  template:
    metadata:
      labels:
        app: lamp
    spec:
      containers:
      - name: web
        # Workload chosen to run cleanly with readOnlyRootFilesystem=true and non-root user.
        image: hashicorp/http-echo:0.2.3
        args:
        - "-listen=:8080"
        - "-text=lamp ok"
        ports:
        - containerPort: 8080
        # INTENTIONALLY NON-COMPLIANT for the lab:
        # - runAsUser: 20000
        # - readOnlyRootFilesystem: true
        # - allowPrivilegeEscalation: false
        securityContext:
          runAsUser: 0
          readOnlyRootFilesystem: false
          allowPrivilegeEscalation: true
EOF

echo
echo "📦 Applying deployment to cluster..."
kubectl apply -f "${MANIFEST}"

echo
echo "📦 Backing up current deployed resource and manifest to: ${backup_dir}"
cp -a "${MANIFEST}" "${backup_dir}/lamp-deployment.yaml"
kubectl -n "${NS}" get deploy "${DEPLOY}" -o yaml > "${backup_dir}/deployed.yaml"

echo
echo "📝 Writing simulated findings report: ${REPORT}"
cat > "${REPORT}" <<'EOF'
# Q06 Findings (SIMULATED) — Container immutability / securityContext hardening

[INFO] Workload: lamp/lamp-deployment

[FAIL] Container is not running as required UID
       * Expected: runAsUser: 20000

[FAIL] Container root filesystem is not read-only
       * Expected: readOnlyRootFilesystem: true

[FAIL] Privilege escalation is not forbidden
       * Expected: allowPrivilegeEscalation: false

== Summary ==
3 checks FAIL
EOF

echo
echo "⏳ Waiting for rollout..."
kubectl -n "${NS}" rollout status deploy/"${DEPLOY}" --timeout=120s

echo
echo "✅ Q06 v2 lab setup complete."
echo "Files:"
echo "  - Manifest: ${MANIFEST}"
echo "  - Report:   ${REPORT}"
echo
echo "Task: Modify the existing Deployment ${NS}/${DEPLOY} to meet the securityContext requirements."
