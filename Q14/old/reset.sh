#!/usr/bin/env bash
set -euo pipefail

WORKER="${WORKER:-node01}"

echo "== Reset Q14: restore vulnerable baseline on ${WORKER} =="

ssh -o StrictHostKeyChecking=no "${WORKER}" "sudo bash -s" <<'EOS'
set -euo pipefail

# Ensure developer exists
id developer >/dev/null 2>&1 || sudo useradd -m -s /bin/bash developer

# Ensure Docker installed/running
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
fi

# Ensure docker group exists
getent group docker >/dev/null 2>&1 || sudo groupadd docker

# Put developer back into docker group
sudo usermod -aG docker developer

# Remove override so daemon.json controls listeners
sudo rm -f /etc/systemd/system/docker.service.d/override.conf
sudo rmdir /etc/systemd/system/docker.service.d 2>/dev/null || true

# Vulnerable daemon.json
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"],
  "group": "docker"
}
JSON

sudo systemctl daemon-reload
sudo systemctl restart docker

echo "[INFO] Reset state:"
echo "- developer groups: $(id -nG developer)"
echo "- docker.sock: $(ls -l /var/run/docker.sock || true)"
echo "- listeners:"
sudo ss -lntp | grep -E ':2375|dockerd' || true
EOS

echo "== Reset complete =="
