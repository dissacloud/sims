#!/usr/bin/env bash
set -euo pipefail

echo "== Question 14 — Reference Solution =="
echo

cat <<'EOF'
STEP 1 — Remove user 'developer' from docker group
------------------------------------------------
On node cks000037:

  sudo getent group docker
  sudo gpasswd -d developer docker

Verify:
  getent group docker
(ensure 'developer' is no longer listed)

------------------------------------------------
STEP 2 — Ensure Docker socket group ownership is root
------------------------------------------------
Edit Docker daemon configuration:

  sudo mkdir -p /etc/docker
  sudo vi /etc/docker/daemon.json

Ensure it contains (or merges to):

{
  "hosts": ["unix:///var/run/docker.sock"],
  "group": "root"
}

IMPORTANT:
- Do NOT include any tcp:// entries.
- If daemon.json already exists, merge keys safely.

------------------------------------------------
STEP 3 — Ensure Docker is not listening on TCP
------------------------------------------------
Check for systemd overrides:

  sudo systemctl cat docker

If you see any '-H tcp://...' flags:
  sudo mkdir -p /etc/systemd/system/docker.service.d
  sudo vi /etc/systemd/system/docker.service.d/override.conf

Ensure ExecStart does NOT include tcp://.
Example clean ExecStart:

  ExecStart=
  ExecStart=/usr/bin/dockerd

Reload and restart Docker:

  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl restart docker

Verify:
  sudo ss -lntp | grep docker   # should show NOTHING
  docker info | grep -i tcp     # should show nothing

------------------------------------------------
STEP 4 — Verify Docker socket permissions
------------------------------------------------
  ls -l /var/run/docker.sock

Expected:
  srw-rw---- 1 root root ... /var/run/docker.sock

------------------------------------------------
STEP 5 — Verify Kubernetes health
------------------------------------------------
From control plane:

  kubectl get nodes

Expected:
  All nodes in Ready state

------------------------------------------------
END
------------------------------------------------
EOF
