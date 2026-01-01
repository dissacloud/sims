#!/usr/bin/env bash
set -euo pipefail

WORKER="${WORKER:-node01}"

echo "== Reference solution (Q14) on ${WORKER} =="

ssh -o StrictHostKeyChecking=no "${WORKER}" "sudo bash -s" <<'EOS'
set -euo pipefail

echo "[1/6] Remove ONLY developer from docker group"
sudo gpasswd -d developer docker || true

echo "[2/6] Configure Docker to use only unix socket + group root"
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "hosts": ["unix:///var/run/docker.sock"],
  "group": "root"
}
JSON

echo "[3/6] Ensure systemd unit has no -H tcp:// flags via override"
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/override.conf >/dev/null <<'INI'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
INI

echo "[4/6] Restart docker"
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "[5/6] Validate docker.sock group root"
ls -l /var/run/docker.sock

echo "[6/6] Validate no TCP listeners"
ss -lntp | grep -E ':2375|dockerd.*LISTEN' && { echo "ERROR: TCP listener still present" >&2; exit 1; } || echo "OK: No Docker TCP listeners"
EOS

echo
echo "== Cluster health check (control-plane) =="
kubectl get nodes -o wide
