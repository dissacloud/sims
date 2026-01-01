#!/usr/bin/env bash
set -euo pipefail

WORKER="${WORKER:-node01}"

echo "== Lab setup (Q14): install Docker on ${WORKER} and inject misconfigurations =="

ssh -o StrictHostKeyChecking=no "${WORKER}" "sudo bash -s" <<'EOS'
set -euo pipefail

echo "[0/7] OS info"
cat /etc/os-release | sed -n '1,10p'

echo "[1/7] Ensure user 'developer' exists"
id developer >/dev/null 2>&1 || sudo useradd -m -s /bin/bash developer

echo "[2/7] Install Docker if missing"
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not present. Installing docker.io from Ubuntu repos..."
  sudo apt-get update -y
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
else
  echo "Docker already installed."
  sudo systemctl enable --now docker || true
fi

echo "[3/7] Ensure group 'docker' exists"
getent group docker >/dev/null 2>&1 || sudo groupadd docker

echo "[4/7] Add developer to docker group (vulnerable baseline)"
sudo usermod -aG docker developer

echo "[5/7] Write vulnerable /etc/docker/daemon.json (tcp + group docker)"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"],
  "group": "docker"
}
JSON

echo "[6/7] Remove any systemd override (so daemon.json takes effect)"
sudo rm -f /etc/systemd/system/docker.service.d/override.conf
sudo rmdir /etc/systemd/system/docker.service.d 2>/dev/null || true

echo "[7/7] Restart docker"
sudo systemctl daemon-reload
sudo systemctl restart docker

echo
echo "[INFO] Current vulnerable state:"
echo "- developer groups: $(id -nG developer)"
echo "- docker.sock: $(ls -l /var/run/docker.sock || true)"
echo "- listeners:"
sudo ss -lntp | grep -E ':2375|dockerd' || true
EOS

echo
echo "== Lab setup complete =="
echo "Next: solve manually, then run ./grader.sh"
