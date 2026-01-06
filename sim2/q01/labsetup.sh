#!/usr/bin/env bash
set -euo pipefail

NODE="${NODE:-node01}"

echo "== Q1 Lab Setup (CIS Benchmark Violations) =="
echo "Target node: ${NODE}"

ssh -o StrictHostKeyChecking=no "${NODE}" "sudo bash -s" <<'EOS'
set -euo pipefail

echo "[1] Ensure kubelet config exists"
KCFG="/var/lib/kubelet/config.yaml"
[ -f "$KCFG" ] || {
  echo "kubelet config missing at $KCFG" >&2
  exit 1
}

echo "[2] Introduce CIS violations in kubelet config"
# TRAP: anonymous auth enabled, AlwaysAllow authz
cat > "$KCFG" <<'YAML'
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration

authentication:
  anonymous:
    enabled: true
  webhook:
    enabled: false

authorization:
  mode: AlwaysAllow
YAML

echo "[3] Restart kubelet to apply insecure settings"
systemctl daemon-reload
systemctl restart kubelet

echo "[4] Introduce CIS violation in etcd static pod"
ETCD_MANIFEST="/etc/kubernetes/manifests/etcd.yaml"

# Backup once
[ -f "${ETCD_MANIFEST}.bak" ] || cp "$ETCD_MANIFEST" "${ETCD_MANIFEST}.bak"

# Force client-cert-auth=false
sed -i 's/--client-cert-auth=true/--client-cert-auth=false/g' "$ETCD_MANIFEST"
grep -q -- '--client-cert-auth' "$ETCD_MANIFEST" || \
  sed -i '/command:/a\    - --client-cert-auth=false' "$ETCD_MANIFEST"

echo "[5] Done. kubelet and etcd now violate CIS."
EOS

echo
echo "Lab setup complete."
echo "Run: ./question.sh"
