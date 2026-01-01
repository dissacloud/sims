#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
== Question 14 ==

Task:
Perform the following tasks to secure the cluster node cks000037.

Requirements:
1) Remove user 'developer' from the 'docker' group.
   - Do not remove any other user from any other group.

2) Reconfigure and restart the Docker daemon so that:
   - The Docker socket file /var/run/docker.sock is owned by group 'root'.
   - Docker does NOT listen on any TCP port (TCP must be disabled).

3) After completing your work:
   - Ensure the Kubernetes cluster is healthy.
   - All nodes must be Ready.

Constraints:
- Do not uninstall Docker.
- Do not stop Kubernetes permanently.
- Only make the minimum required changes.

You may need to inspect:
- /etc/group
- /etc/docker/daemon.json
- systemd unit overrides
- systemctl status docker

EOF
