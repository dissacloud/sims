#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Cleaning up / resetting Dockerfile + Deployment lab (Q04)"

LAB_HOME="${HOME}/subtle-bee"
BUILD_DIR="${LAB_HOME}/build"
DOCKERFILE="${BUILD_DIR}/Dockerfile"
DEPLOYMENT="${LAB_HOME}/deployment.yaml"
BACKUP_ROOT="/root"

echo
echo "🔍 Locating most recent Q04 backup directory..."
backup_dir="$(ls -d ${BACKUP_ROOT}/cis-q04-backups-* 2>/dev/null | sort | tail -n 1 || true)"

if [[ -z "${backup_dir}" ]]; then
  echo "WARN: No cis-q04-backups-* directory found. Nothing to restore."
else
  echo "📦 Using backup directory: ${backup_dir}"
  mkdir -p "${BUILD_DIR}"

  [[ -f "${backup_dir}/Dockerfile" ]] && cp -a "${backup_dir}/Dockerfile" "${DOCKERFILE}"
  [[ -f "${backup_dir}/deployment.yaml" ]] && cp -a "${backup_dir}/deployment.yaml" "${DEPLOYMENT}"
fi

echo
echo "🧹 Removing simulated report..."
rm -f /root/kube-bench-report-q04.txt

echo "✅ Q04 cleanup complete."
echo "Validation:"
echo "  ls -la ${LAB_HOME} ${BUILD_DIR}"
