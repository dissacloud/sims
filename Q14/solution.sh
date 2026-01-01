#!/usr/bin/env bash
# Instructions only (do not execute as a fix script)

cat <<'EOF'
REFERENCE SOLUTION (INSTRUCTIONS ONLY) — Q14 (fd:// decision path)

1) Identify the worker node and SSH into it.

2) Remove only user 'developer' from the 'docker' group.
   - Confirm 'ops' remains unchanged (do not remove other users from docker group).

3) Verify how Docker is started:
   - Inspect: systemctl cat docker
   - If ExecStart contains fd:// (it will in this sim), do NOT configure 'hosts' in /etc/docker/daemon.json.

4) Ensure Docker does not listen on TCP:
   - Because this sim injects TCP exposure via systemd ExecStart, you must remove the tcp:// listener there.
   - Update the systemd drop-in so ExecStart keeps '-H fd://' but removes any '-H tcp://...'.

5) Ensure docker.sock is group-owned by root:
   - Update /etc/docker/daemon.json to enforce: { "group": "root" }
   - Do not add 'hosts' to daemon.json.

6) Reload systemd and restart Docker.
   - Confirm docker starts successfully.

7) Validate outcomes on the worker:
   - developer is not in docker group
   - ops is still in docker group
   - /var/run/docker.sock group is root
   - no dockerd TCP listeners (no :2375)

8) Validate Kubernetes cluster health from the control-plane:
   - nodes are Ready

Then run: ./grader.sh
EOF
