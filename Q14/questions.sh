#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
CKS Simulation — Question 14 (Forced fd:// Path)

Task:
- On the worker node (cks000037; typically node01), remove user 'developer' from the 'docker' group.
- Do not remove any other user from any other group.
- Reconfigure and restart the Docker daemon so that /var/run/docker.sock is owned by the group 'root'.
- Reconfigure and restart the Docker daemon so that it does NOT listen on any TCP port.
- Ensure the Kubernetes cluster remains healthy.

Important notes:
- This environment intentionally uses systemd socket activation (fd://).
- You must verify how Docker starts using:  systemctl cat docker
- Intentional traps exist:
  1) Editing /etc/docker/daemon.decoy.json does nothing.
  2) Adding "hosts" to /etc/docker/daemon.json while fd:// is in ExecStart will break Docker.
  3) Another user ('ops') is in the docker group; removing them will fail grading.

When done:
- Run: ./grader.sh
EOF
