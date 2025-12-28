#!/usr/bin/env bash
# Q11 — Worker Node Upgrade (kubeadm)
# Read-only helper that prints the exam task. No changes are made.

set -euo pipefail

cat <<'EOF'
Question 11 — Upgrade worker node to match control plane

Context:
The kubeadm provisioned cluster was recently upgraded, leaving one worker node on a slightly older version.

Task:
- Upgrade the cluster node compute-0 (worker) to match the version of the control plane node.
- Connect to the compute node using:
    ssh compute-0
- Do not modify any running workloads in the cluster.
- Do not forget to exit from the compute node once you have completed your tasks.

Exam-style expectations:
- Cordon + drain the worker (if needed), upgrade kubeadm/kubelet/kubectl, restart kubelet, then uncordon.
- Verify: kubectl get nodes shows matching versions and worker is Ready.

When finished:
- Run the strict grader on the control plane:
    bash Q11_Grader_Strict.bash
EOF
