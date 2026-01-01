#!/usr/bin/env bash
set -euo pipefail

WORKER="${WORKER:-node01}"

echo "== Reset: restore vulnerable baseline (fd:// + TCP via systemd; group docker) on ${WORKER} =="

ssh -o StrictHostKeyChecking=no "${WORKER}" "sudo bash -s" <<'EOS'
set -euo pipefail

# Ensure users/groups exist
id developer >/dev/null 2>&1 || useradd -m -s /bin/bash developer
id ops >/dev/null 2>&1 || useradd -m -s /bin/bash ops
getent group docker >/dev/null 2>&1 || groupadd docker

# Put both users back into docker group (trap preserved)
usermod -aG docker developer
usermod -aG docker ops

# Ensure docker installed/running
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y docker.io
fi
systemctl enable --now docker
systemctl enable --now docker.socket

# Restore real daemon.json (no hosts; group docker)
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'JSON'
{
  "group": "docker"
}
JSON
chmod 0644 /etc/docker/daemon.json

# Restore decoy (trap)
cat >/etc/docker/daemon.decoy.json <<'JSON'
{
  "hosts": ["tcp://0.0.0.0:2375"],
  "group": "docker"
}
JSON
chmod 0644 /etc/docker/daemon.decoy.json

# Restore systemd override that forces fd:// + TCP
mkdir -p /etc/systemd/system/docker.service.d
cat >/etc/systemd/system/docker.service.d/10-cks-q14-tcp.conf <<'INI'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375 --containerd=/run/containerd/containerd.sock
INI
chmod 0644 /etc/systemd/system/docker.service.d/10-cks-q14-tcp.conf

systemctl daemon-reload
systemctl restart docker

echo "[INFO] Reset state:"
echo "- developer groups: $(id -nG developer)"
echo "- ops groups:       $(id -nG ops)"
echo "- daemon.json:"
cat /etc/docker/daemon.json
echo "- docker ExecStart (should show fd:// and tcp://):"
systemctl cat docker | grep -E 'ExecStart|fd://|tcp://' || true
echo "- listeners (should show :2375):"
ss -lntp | grep -E ':2375|dockerd' || true
EOS

echo "Reset complete."
echo "Run: ./question.sh"
