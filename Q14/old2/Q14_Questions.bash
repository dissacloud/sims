#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
== Question 14 ==

Task:
Perform the following tasks to secure the cluster node cks000037:

1) Remove user 'developer' from the 'docker' group.
   - Do not remove any other user from any other group.

2) Reconfigure and restart the Docker daemon so that the socket file:
      /var/run/docker.sock
   is owned by group 'root'.

3) Reconfigure and restart the Docker daemon so that it does NOT listen on any TCP port.

4) After completing your work, ensure the Kubernetes cluster is healthy.

Notes:
- This is a node-level hardening task. Expect to SSH to the worker node.
- Validation should include: group membership, docker.sock ownership, dockerd listen sockets, and node readiness.

EOF
