#!/usr/bin/env bash
# Q14 Lab Setup (worker) — intentionally misconfigure Docker security posture.
# Creates:
# - user 'developer' (if missing)
# - adds 'developer' to docker group
# - sets /etc/docker/daemon.json to listen on TCP 2375 and set socket group to docker
# - restarts docker, so /var/run/docker.sock group becomes docker
#
set -euo pipefail
trap '' PIPE

STATE_FILE="/root/.q14_state"
BACKUP_DIR="/root/cis-q14-backups-$(date +%Y%m%d%H%M%S)"
mkdir -p "${BACKUP_DIR}"

echo "== Q14 Lab Setup (worker) =="
echo "Date: $(date -Is)"
echo "Node: $(hostname)"
echo "Backup dir: ${BACKUP_DIR}"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need systemctl
need id
need getent
need ss

if ! command -v docker >/dev/null 2>&1; then
  echo "WARN: 'docker' CLI not found; proceeding anyway (dockerd may still exist)."
fi

CREATED_USER="0"
if id developer >/dev/null 2>&1; then
  echo "[0] User 'developer' exists."
else
  echo "[0] Creating user 'developer'..."
  useradd -m -s /bin/bash developer
  CREATED_USER="1"
fi

ORIG_DOCKER_GROUP="$(getent group docker | cut -d: -f4 || true)"

DAEMON_JSON="/etc/docker/daemon.json"
if [[ -f "${DAEMON_JSON}" ]]; then
  cp -a "${DAEMON_JSON}" "${BACKUP_DIR}/daemon.json.original"
  DAEMON_JSON_BACKED_UP="1"
else
  DAEMON_JSON_BACKED_UP="0"
fi

DROPIN_DIR="/etc/systemd/system/docker.service.d"
DROPIN_BACKED_UP="0"
if [[ -d "${DROPIN_DIR}" ]]; then
  tar -czf "${BACKUP_DIR}/docker.service.d.tgz" -C /etc/systemd/system docker.service.d
  DROPIN_BACKED_UP="1"
fi

SOCK_LINE="$(ls -l /var/run/docker.sock 2>/dev/null || true)"

cat > "${STATE_FILE}" <<EOF
BACKUP_DIR=${BACKUP_DIR}
CREATED_USER=${CREATED_USER}
ORIG_DOCKER_GROUP=${ORIG_DOCKER_GROUP}
DAEMON_JSON_BACKED_UP=${DAEMON_JSON_BACKED_UP}
DROPIN_BACKED_UP=${DROPIN_BACKED_UP}
SOCK_LINE=${SOCK_LINE}
EOF
chmod 600 "${STATE_FILE}"

echo "[1] Adding 'developer' to docker group (intentional insecure state)..."
usermod -aG docker developer
echo "[1.1] docker group now:"
getent group docker || true
echo "[1.2] developer identity:"
id developer || true

echo "[2] Ensuring Docker daemon listens on TCP 2375 and socket group is docker..."
mkdir -p /etc/docker
cat > "${DAEMON_JSON}" <<'JSON'
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"],
  "group": "docker"
}
JSON

echo "[3] Restarting docker..."
systemctl daemon-reload || true
systemctl restart docker

echo
echo "[4] Current docker.sock ownership:"
ls -l /var/run/docker.sock || true

echo
echo "[5] Current dockerd listeners (expect to see :2375 in lab setup):"
ss -lntp 2>/dev/null | grep -E '(:2375\b|dockerd)' || true

echo
echo "✅ Q14 worker misconfiguration applied."
echo "State recorded in ${STATE_FILE}"
