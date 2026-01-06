#!/usr/bin/env bash
set -euo pipefail

NODE="${NODE:-node01}"

echo "== Reset Q1 to insecure CIS baseline =="

ssh -o StrictHostKeyChecking=no "${NODE}" "sudo bash -s" <<'EOS'
set -euo pipefail

# Restore kubelet insecure config
cat > /var/lib/kubelet/config.yaml <<'YAML'
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

systemctl daemon-reload
systemctl restart kubelet

# Restore etcd manifest
ETCD="/etc/kubernetes/manifests/etcd.yaml"
if [ -f "${ETCD}.bak" ]; then
  cp "${ETCD}.bak" "$ETCD"
else
  sed -i 's/--client-cert-auth=true/--client-cert-auth=false/g' "$ETCD"
fi
EOS

echo "Reset complete."
echo "Run: ./question.sh"
