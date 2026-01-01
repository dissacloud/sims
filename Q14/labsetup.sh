#!/usr/bin/env bash
set -euo pipefail

WORKER="${WORKER:-node01}"

echo "== Q14 Lab Setup (forces fd:// path + traps) on ${WORKER} =="

ssh -o StrictHostKeyChecking=no "${WORKER}" "sudo bash -s" <<'EOS'
set -euo pipefail

echo "[1/10] Ensure baseline users/groups exist"
id developer >/dev/null 2>&1 || useradd -m -s /bin/bash developer
id ops >/dev/null 2>&1 || useradd -m -s /bin/bash ops

getent group docker >/dev/null 2>&1 || groupadd docker

# TRAP: another user (ops) is also in docker group; removing them should fail grading
usermod -aG docker developer
usermod -aG docker ops

echo "[2/10] Install Docker if missing (Ubuntu repo docker.io)"
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y docker.io
fi
systemctl enable --now docker

echo "[3/10] Create a decoy config file (TRAP: editing this does nothing)"
mkdir -p /etc/docker
cat >/etc/docker/daemon.decoy.json <<'JSON'
{
  "hosts": ["tcp://0.0.0.0:2375"],
  "group": "docker"
}
JSON
chmod 0644 /etc/docker/daemon.decoy.json

echo "[4/10] Create the real daemon.json (NO hosts; group docker)"
# Real file must not define 'hosts' to keep docker running with fd://
cat >/etc/docker/daemon.json <<'JSON'
{
  "group": "docker"
}
JSON
chmod 0644 /etc/docker/daemon.json

echo "[5/10] Force docker ExecStart to include fd:// + insecure TCP via systemd override"
mkdir -p /etc/systemd/system/docker.service.d

# We explicitly include -H fd:// (to force the fd:// decision gate)
# And we intentionally include -H tcp://0.0.0.0:2375 to create the insecure exposure to remove.
cat >/etc/systemd/system/docker.service.d/10-cks-q14-tcp.conf <<'INI'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375 --containerd=/run/containerd/containerd.sock
INI
chmod 0644 /etc/systemd/system/docker.service.d/10-cks-q14-tcp.conf

echo "[6/10] Ensure docker.socket is enabled (used by fd://)"
systemctl enable --now docker.socket

echo "[7/10] Restart Docker to apply override"
systemctl daemon-reload
systemctl restart docker

echo "[8/10] Show forced decision gate (fd:// present)"
systemctl cat docker | sed -n '1,140p' | grep -E 'ExecStart|fd://|tcp://|docker\.service\.d' || true

echo "[9/10] Show current vulnerable state"
echo "developer groups: $(id -nG developer)"
echo "ops groups:       $(id -nG ops)"
echo "daemon.json:"
cat /etc/docker/daemon.json
echo "docker.sock:"
ls -l /var/run/docker.sock || true
echo "listeners (expect :2375 open):"
ss -lntp | grep -E ':2375|dockerd' || true

echo "[10/10] Done"
EOS

echo
echo "Lab setup complete."
echo "Run: ./question.sh"
