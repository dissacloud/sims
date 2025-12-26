#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up CIS Benchmark remediation lab (Q01 v2) — WORKER NODE"
echo

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"
REPORT="/root/kube-bench-report-q01.txt"

ts="$(date +%Y%m%d%H%M%S)"
backup_dir="/root/cis-q01v2-node-backups-${ts}"
mkdir -p "${backup_dir}"

echo "📦 Backing up kubelet config to: ${backup_dir}"
if [[ -f "${KUBELET_CONFIG}" ]]; then
  cp -a "${KUBELET_CONFIG}" "${backup_dir}/config.yaml"
else
  echo "WARN: ${KUBELET_CONFIG} not found."
fi

echo
echo "🧩 Introducing intentional kubelet CIS violations (worker)..."

if [[ -f "${KUBELET_CONFIG}" ]]; then
  perl -0777 -i -pe '
    if ($_ !~ /^authentication:\n/m) {
      $_ .= "\nauthentication:\n  anonymous:\n    enabled: true\n  webhook:\n    enabled: false\n";
    }
    if ($_ =~ /^authentication:\n(?:.*\n)*?  anonymous:\n(?:.*\n)*?    enabled:\s*(true|false)\s*$/m) {
      s/^(\s*anonymous:\n(?:.*\n)*?\s*enabled:\s*)(true|false)\s*$/${1}true/m;
    } else {
      s/^(authentication:\n)/$1  anonymous:\n    enabled: true\n/m;
    }
    if ($_ =~ /^authentication:\n(?:.*\n)*?  webhook:\n(?:.*\n)*?    enabled:\s*(true|false)\s*$/m) {
      s/^(\s*webhook:\n(?:.*\n)*?\s*enabled:\s*)(true|false)\s*$/${1}false/m;
    } else {
      s/^(authentication:\n)/$1  webhook:\n    enabled: false\n/m;
    }
    if ($_ !~ /^authorization:\n/m) {
      $_ .= "\nauthorization:\n  mode: AlwaysAllow\n";
    }
    if ($_ =~ /^authorization:\n(?:.*\n)*?  mode:\s*\S+\s*$/m) {
      s/^(\s*mode:\s*)\S+\s*$/${1}AlwaysAllow/m;
    } else {
      s/^(authorization:\n)/$1  mode: AlwaysAllow\n/m;
    }
  ' "${KUBELET_CONFIG}"

  echo "✅ Injected kubelet CIS violations into ${KUBELET_CONFIG}"
else
  echo "WARN: ${KUBELET_CONFIG} not found."
fi

echo
echo "🔁 Restarting kubelet to apply misconfigurations..."
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart kubelet

echo
echo "✅ WORKER NODE lab setup complete."
echo "If you want a local copy of the report:"
echo "  sudo cat ${REPORT}  (from controlplane), or copy it here."
