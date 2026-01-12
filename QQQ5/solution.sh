#!/usr/bin/env bash
# SIM-Q05 Solution (instructions only) — Contain /dev/mem access
# Goal: Identify the pod configured to read /dev/mem and scale ONLY its owning Deployment to 0.
# Constraints: Do not delete Deployments. Do not modify any other Deployments. Only scale.

set -euo pipefail

NS="ollama"

cat <<'EOF'
== SIM-Q05 Solution — Contain /dev/mem access ==

Step 1 — Identify pods and the node they run on
---------------------------------------------
kubectl -n ollama get pods -o wide

Note the pod(s) and the NODE column. (In this sim, both run on node01.)

Step 2 — Attempt runtime attribution on the correct node (best effort)
----------------------------------------------------------------------
ssh node01

# Check for active /dev/mem file descriptors (may be empty if access is transient/blocked):
sudo lsof /dev/mem || true
sudo fuser -v /dev/mem || true
sudo find /proc/*/fd -lname '/dev/mem' 2>/dev/null | head || true

# If you obtain a PID that shows kubepods/containerd in /proc/<PID>/cgroup, you can map it to a container/pod.
# If you get only host services or no output, proceed to Step 3 (manifest evidence).

Step 3 — Confirm which pod is configured to access /dev/mem (authoritative fallback)
-----------------------------------------------------------------------------------
# Back on controlplane (or from any node with kubectl):
kubectl -n ollama get pods

# Inspect the suspected pod manifest for privileged + hostPath + /dev/mem mount + dd command:
kubectl -n ollama get pod <MEM_SCRAPER_POD> -o yaml | grep -nE 'dev/mem|hostPath|privileged'

You should see:
- privileged: true
- mountPath: /dev/mem
- hostPath: path: /dev/mem
- command referencing dd if=/dev/mem

This identifies the misbehaving pod.

Step 4 — Resolve owning Deployment
----------------------------------
# Pod -> ReplicaSet:
kubectl -n ollama get pod <MEM_SCRAPER_POD> \
  -o jsonpath='{.metadata.ownerReferences[0].kind} {.metadata.ownerReferences[0].name}{"\n"}'

# ReplicaSet -> Deployment:
kubectl -n ollama get rs <REPLICASET_NAME> \
  -o jsonpath='{.metadata.ownerReferences[0].name}{"\n"}'

Step 5 — Contain by scaling ONLY that Deployment to zero
--------------------------------------------------------
kubectl -n ollama scale deploy <DEPLOYMENT_NAME> --replicas=0

Step 6 — Verify constraints and completion
------------------------------------------
kubectl -n ollama get deploy
kubectl -n ollama get pods

Expected:
- The offending deployment replicas=0
- ollama-api remains running (replicas=1)
- No deployments deleted, no other deployments modified


