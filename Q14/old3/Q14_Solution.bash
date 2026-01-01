#!/usr/bin/env bash
# Q14 Solution (instructions only)
set -euo pipefail

WORKER="${WORKER:-node01}"   # in this lab, cks000037 maps to this worker hostname
NS="${NS:-default}"

cat <<EOF
== Q14 Solution — Secure Docker on worker (cks000037) ==

Assumptions:
- You run kubectl from the control-plane node.
- The worker node hostname is: ${WORKER}

----------------------------------------
Step 0 — Verify cluster health baseline
----------------------------------------
kubectl get nodes -o wide

----------------------------------------
Step 1 — SSH to the worker and remove 'developer' from docker group
----------------------------------------
ssh ${WORKER}

# On the worker:
id developer || true
getent group docker || true

# Remove ONLY developer from docker group:
sudo gpasswd -d developer docker

# Verify:
id developer | tr ' ' '\n' | grep -q docker && echo "STILL IN docker (bad)" || echo "developer removed (ok)"
getent group docker

----------------------------------------
Step 2 — Ensure dockerd socket group is 'root' and NO TCP listeners
----------------------------------------
# On the worker, inspect how dockerd is configured:
sudo systemctl cat docker | sed -n '1,200p'
sudo test -f /etc/docker/daemon.json && sudo cat /etc/docker/daemon.json || true
sudo test -f /etc/systemd/system/docker.service.d/override.conf && sudo cat /etc/systemd/system/docker.service.d/override.conf || true

# Fix approach (preferred in exam/labs):
# - Ensure daemon.json DOES NOT define tcp:// hosts
# - Ensure daemon.json sets dockerd group to root
#
# Example daemon.json (safe baseline):
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "group": "root"
}
JSON

# Remove any systemd override that adds -H tcp://... (if present)
if sudo test -f /etc/systemd/system/docker.service.d/override.conf; then
  sudo rm -f /etc/systemd/system/docker.service.d/override.conf
  sudo rmdir --ignore-fail-on-non-empty /etc/systemd/system/docker.service.d 2>/dev/null || true
fi

# Reload + restart docker:
sudo systemctl daemon-reload
sudo systemctl restart docker

----------------------------------------
Step 3 — Validate requirements on the worker
----------------------------------------
# 3.1 docker.sock group is root
stat -c '%n %U:%G %a' /var/run/docker.sock

# 3.2 Docker is not listening on TCP (no 2375/2376, and no dockerd LISTEN on 0.0.0.0:*):
sudo ss -lntp | egrep -i '(:2375|:2376|dockerd)' || true
sudo ps -ef | grep -E '[d]ockerd' || true

# Exit worker
exit

----------------------------------------
Step 4 — Confirm cluster is healthy from control-plane
----------------------------------------
kubectl get nodes
kubectl -n kube-system get pods -o wide

EOF
