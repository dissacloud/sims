#!/usr/bin/env bash
# Q14 STRICT Grader — verifies:
# - user 'developer' is NOT in docker group
# - /var/run/docker.sock group is root
# - dockerd is NOT listening on any TCP port (no :2375/:2376, and no dockerd LISTEN on INET)
# - Kubernetes cluster remains healthy (nodes Ready)
#
# Run from controlplane.
set -euo pipefail
trap '' PIPE

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER_NODE="${WORKER:-}"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need kubectl
need ssh

k(){ kubectl "$@"; }

echo "== Q14 STRICT Grader =="
echo "Date: $(date -Is)"
echo

if [[ -z "${WORKER_NODE}" ]]; then
  WORKER_NODE="$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}'     | awk '$2=="" {print $1}' | head -n1 || true)"
fi

if [[ -z "${WORKER_NODE}" ]]; then
  add_fail "Worker node identified" "Could not auto-detect non-control-plane node" "Set WORKER=<node> and re-run"
else
  add_pass "Worker node identified (${WORKER_NODE})"
fi

READY_CT="$(k get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')"
TOTAL_CT="$(k get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${TOTAL_CT}" -gt 0 && "${READY_CT}" == "${TOTAL_CT}" ]]; then
  add_pass "Kubernetes nodes Ready (${READY_CT}/${TOTAL_CT})"
else
  add_fail "Kubernetes nodes Ready" "Ready=${READY_CT} Total=${TOTAL_CT}" "kubectl describe node; ensure docker/kubelet not broken"
fi

if [[ -n "${WORKER_NODE}" ]]; then
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER_NODE}" "true" >/dev/null 2>&1; then
    add_pass "SSH connectivity to worker"
  else
    add_warn "SSH connectivity to worker" "Cannot SSH in BatchMode" "Run checks manually on worker"
  fi
fi

remote() {
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER_NODE}" "bash -lc '$*'"
}

if [[ -n "${WORKER_NODE}" ]]; then
  if remote "getent group docker | cut -d: -f4 | tr ',' '\n' | grep -qx developer"; then
    add_fail "developer removed from docker group" "developer is still a member of docker group" "sudo gpasswd -d developer docker"
  else
    add_pass "developer removed from docker group"
  fi

  SOCK_GRP="$(remote "stat -c '%G' /var/run/docker.sock 2>/dev/null || echo '<missing>'" || true)"
  if [[ "${SOCK_GRP}" == "root" ]]; then
    add_pass "docker.sock group is root"
  else
    add_fail "docker.sock group is root" "Found group='${SOCK_GRP}'" "Set Docker daemon group=root and restart docker; verify /var/run/docker.sock is root:root"
  fi

  if remote "ss -lntp 2>/dev/null | grep -E '(:2375\b|:2376\b)'" >/dev/null 2>&1; then
    add_fail "Docker not listening on TCP (:2375/:2376)" "Found TCP listener on 2375/2376" "Remove tcp hosts from Docker config (daemon.json/systemd), restart docker"
  else
    add_pass "No Docker TCP listener on :2375/:2376"
  fi

  if remote "ss -lntp 2>/dev/null | awk '/LISTEN/ && /dockerd/ {print}' | grep -q ."; then
    add_fail "dockerd has no TCP LISTEN sockets" "dockerd appears in ss -lntp LISTEN output" "Ensure dockerd hosts only unix:///var/run/docker.sock; restart docker"
  else
    add_pass "dockerd has no TCP LISTEN sockets"
  fi

  HOSTS_LINE="$(remote "sudo cat /etc/docker/daemon.json 2>/dev/null | tr -d '\n' | sed 's/[[:space:]]//g' || true" || true)"
  if [[ -n "${HOSTS_LINE}" ]]; then
    if echo "${HOSTS_LINE}" | grep -q 'tcp://'; then
      add_fail "daemon.json has no tcp:// host" "Found tcp:// in /etc/docker/daemon.json" "Edit /etc/docker/daemon.json to hosts: [\"unix:///var/run/docker.sock\"]"
    else
      add_pass "daemon.json has no tcp:// host"
    fi
  else
    add_warn "daemon.json inspected" "Could not read /etc/docker/daemon.json" "If using systemd ExecStart flags, ensure no -H tcp://... is set"
  fi
fi

echo
for r in "${results[@]}"; do
  echo "$r"
  echo
done

echo "== Summary =="
echo "${pass} PASS"
echo "${warn} WARN"
echo "${fail} FAIL"

[[ "${fail}" -eq 0 ]]
