#!/usr/bin/env bash
# Q14 Cleanup (worker) — restore pre-setup state using /root/.q14_state if present.
set -euo pipefail
trap '' PIPE

STATE_FILE="/root/.q14_state"

echo "== Q14 Cleanup (worker) =="
echo "Date: $(date -Is)"
echo "Node: $(hostname)"
echo

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "WARN: ${STATE_FILE} not found. Performing safe partial cleanup only."
  if id developer >/dev/null 2>&1; then
    gpasswd -d developer docker >/dev/null 2>&1 || true
  fi
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'JSON'
{
  "hosts": ["unix:///var/run/docker.sock"],
  "group": "root"
}
JSON
  systemctl daemon-reload || true
  systemctl restart docker || true
  ls -l /var/run/docker.sock || true
  exit 0
fi

# shellcheck disable=SC1090
source "${STATE_FILE}"

echo "Backup dir: ${BACKUP_DIR:-<unknown>}"
echo

DAEMON_JSON="/etc/docker/daemon.json"

echo "[1] Restoring daemon.json..."
if [[ "${DAEMON_JSON_BACKED_UP:-0}" == "1" && -f "${BACKUP_DIR}/daemon.json.original" ]]; then
  cp -a "${BACKUP_DIR}/daemon.json.original" "${DAEMON_JSON}"
  echo "✅ Restored original daemon.json"
else
  mkdir -p /etc/docker
  cat > "${DAEMON_JSON}" <<'JSON'
{
  "hosts": ["unix:///var/run/docker.sock"],
  "group": "root"
}
JSON
  echo "✅ Set safe default daemon.json (unix socket only, group=root)"
fi

echo "[2] Restoring docker.service.d drop-ins (if any)..."
if [[ "${DROPIN_BACKED_UP:-0}" == "1" && -f "${BACKUP_DIR}/docker.service.d.tgz" ]]; then
  rm -rf /etc/systemd/system/docker.service.d
  tar -xzf "${BACKUP_DIR}/docker.service.d.tgz" -C /etc/systemd/system
  echo "✅ Restored docker.service.d"
else
  echo "No drop-ins to restore."
fi

echo "[3] Restoring docker group membership..."
if id developer >/dev/null 2>&1; then
  gpasswd -d developer docker >/dev/null 2>&1 || true
  if [[ ",${ORIG_DOCKER_GROUP}," == *",developer,"* ]]; then
    usermod -aG docker developer
  fi
fi

if [[ "${CREATED_USER:-0}" == "1" ]]; then
  echo "[3.1] Removing lab-created user 'developer'..."
  userdel -r developer >/dev/null 2>&1 || true
fi

echo "[4] Restarting docker..."
systemctl daemon-reload || true
systemctl restart docker || true

echo
echo "[5] Current docker.sock ownership:"
ls -l /var/run/docker.sock || true

echo
echo "[6] Current dockerd listeners (should NOT show :2375):"
ss -lntp 2>/dev/null | grep -E '(:2375\b|dockerd)' || true

echo
echo "✅ Cleanup completed."
