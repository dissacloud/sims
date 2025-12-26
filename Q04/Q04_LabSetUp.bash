#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up Dockerfile + Deployment hardening lab (Q04 v1)"

LAB_HOME="${HOME}/subtle-bee"
BUILD_DIR="${LAB_HOME}/build"
DOCKERFILE="${BUILD_DIR}/Dockerfile"
DEPLOYMENT="${LAB_HOME}/deployment.yaml"
REPORT="/root/kube-bench-report-q04.txt"

ts="$(date +%Y%m%d%H%M%S)"
backup_dir="/root/cis-q04-backups-${ts}"
mkdir -p "${backup_dir}"

echo "📦 Creating lab directories..."
mkdir -p "${BUILD_DIR}"

echo "🧩 Writing intentionally insecure Dockerfile to: ${DOCKERFILE}"
cat > "${DOCKERFILE}" <<'EOF'
FROM ubuntu:latest
USER root
RUN apt get install -y lsof=4.72 wget=1.17.1 nginx=4.2
ENV ENVIRONMENT=testing
USER root
CMD ["nginx -d"]
EOF

echo "🧩 Writing intentionally insecure Deployment manifest to: ${DEPLOYMENT}"
cat > "${DEPLOYMENT}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka
  labels:
    app: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  strategy: {}
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka
        volumeMounts:
        - name: kafka-vol
          mountPath: /var/lib/kafka
        securityContext:
          runAsUser: 65535
          privileged: true
          readOnlyRootFilesystem: false
          capabilities:
            add:
            - NET_ADMIN
            drop:
            - ALL
      volumes:
      - name: kafka-vol
        emptyDir: {}
EOF

echo
echo "📦 Backing up lab files to: ${backup_dir}"
cp -a "${DOCKERFILE}" "${backup_dir}/Dockerfile"
cp -a "${DEPLOYMENT}" "${backup_dir}/deployment.yaml"

echo
echo "📝 Generating simulated finding report: ${REPORT}"
cat > "${REPORT}" <<'EOF'
# Q04 Findings (SIMULATED) — Dockerfile + Kubernetes manifest best practices
# DO NOT build images as part of this question.

[INFO] Dockerfile review
[FAIL] Dockerfile runtime user runs as root
       * Reason: Dockerfile includes USER root as the effective runtime user
       * Remediation: Change the final USER instruction to an unprivileged user (use UID 65535 / nobody)

[INFO] Kubernetes manifest review
[FAIL] Container is privileged
       * Reason: securityContext.privileged=true
       * Remediation: Set securityContext.privileged=false

== Summary ==
2 checks FAIL
EOF

echo
echo "✅ Q04 lab setup complete."
echo "Files:"
echo "  - ${DOCKERFILE}"
echo "  - ${DEPLOYMENT}"
echo "  - ${REPORT}"
echo
echo "Reminder:"
echo "  - Do NOT build the Dockerfile."
