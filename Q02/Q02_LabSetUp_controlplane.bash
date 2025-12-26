#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up API Server hardening lab (Q02 v1) — CONTROLPLANE (kubeadm)"
echo

APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
INSECURE_KUBECONFIG="/root/.kube/config"
REPORT="/root/kube-bench-report-q02.txt"

ts="$(date +%Y%m%d%H%M%S)"
backup_dir="/root/cis-q02-backups-${ts}"
mkdir -p "${backup_dir}"

echo "📦 Backing up files to: ${backup_dir}"
for f in "${APISERVER_MANIFEST}" "${INSECURE_KUBECONFIG}"; do
  if [[ -f "$f" ]]; then
    cp -a "$f" "${backup_dir}/$(basename "$f")"
  fi
done

echo
echo "🧩 Introducing intentional insecure API server configuration..."

if [[ ! -f "${APISERVER_MANIFEST}" ]]; then
  echo "ERROR: ${APISERVER_MANIFEST} not found. This lab expects kubeadm static pods."
  exit 1
fi

# 1) kube-apiserver flags:
# - allow anonymous auth (bad)
# - AlwaysAllow authorization (bad)
# - remove/avoid NodeRestriction admission controller (bad)
#
# We do this by editing the manifest args.
# Supports both `--flag=value` and `--flag value` patterns.

# anonymous-auth -> true
if grep -qE -- '--anonymous-auth(=| )' "${APISERVER_MANIFEST}"; then
  sed -i -E 's/--anonymous-auth(=| )[^ ]+/--anonymous-auth=true/g' "${APISERVER_MANIFEST}"
else
  # insert after first - -- line in args
  awk '
    BEGIN{done=0}
    {print}
    (!done && $0 ~ /^ *- --/){
      print "    - --anonymous-auth=true"
      done=1
    }
  ' "${APISERVER_MANIFEST}" > "${APISERVER_MANIFEST}.tmp" && mv "${APISERVER_MANIFEST}.tmp" "${APISERVER_MANIFEST}"
fi

# authorization-mode -> AlwaysAllow
if grep -qE -- '--authorization-mode(=| )' "${APISERVER_MANIFEST}"; then
  sed -i -E 's/--authorization-mode(=| )[^ ]+/--authorization-mode=AlwaysAllow/g' "${APISERVER_MANIFEST}"
else
  awk '
    BEGIN{done=0}
    {print}
    (!done && $0 ~ /^ *- --/){
      print "    - --authorization-mode=AlwaysAllow"
      done=1
    }
  ' "${APISERVER_MANIFEST}" > "${APISERVER_MANIFEST}.tmp" && mv "${APISERVER_MANIFEST}.tmp" "${APISERVER_MANIFEST}"
fi

# enable-admission-plugins -> remove NodeRestriction if present
if grep -qE -- '--enable-admission-plugins(=| )' "${APISERVER_MANIFEST}"; then
  # Remove NodeRestriction from comma list
  sed -i -E 's/(--enable-admission-plugins(=| )[^"\n ]*)NodeRestriction,?/\1/g' "${APISERVER_MANIFEST}"
  sed -i -E 's/(--enable-admission-plugins(=| )[^"\n ]*),NodeRestriction/\1/g' "${APISERVER_MANIFEST}"
else
  # Add a minimal list WITHOUT NodeRestriction
  awk '
    BEGIN{done=0}
    {print}
    (!done && $0 ~ /^ *- --/){
      print "    - --enable-admission-plugins=NamespaceLifecycle,ServiceAccount,DefaultStorageClass,ResourceQuota"
      done=1
    }
  ' "${APISERVER_MANIFEST}" > "${APISERVER_MANIFEST}.tmp" && mv "${APISERVER_MANIFEST}.tmp" "${APISERVER_MANIFEST}"
fi

echo "✅ Insecure kube-apiserver flags applied in ${APISERVER_MANIFEST}"

echo
echo "🧩 Creating an overly-permissive ClusterRoleBinding for system:anonymous..."
# Apply using admin kubeconfig to ensure it succeeds regardless of current kubectl config
cat <<'EOF' | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system-anonymous
subjects:
- kind: User
  name: system:anonymous
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo
echo "🧩 Switching kubectl to an unauthenticated kubeconfig (so kubectl will break after you secure the API server)..."
mkdir -p /root/.kube

# Build a kubeconfig that presents NO credentials (anonymous user)
# and skips TLS verification for simplicity in lab.
server="$(awk '/server:/{print $2; exit}' "${ADMIN_KUBECONFIG}")"
cat > "${INSECURE_KUBECONFIG}" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: insecure
  cluster:
    server: ${server}
    insecure-skip-tls-verify: true
users:
- name: anonymous
  user: {}
contexts:
- name: anonymous@insecure
  context:
    cluster: insecure
    user: anonymous
current-context: anonymous@insecure
EOF

chmod 600 "${INSECURE_KUBECONFIG}"
echo "✅ Wrote unauthenticated kubeconfig to ${INSECURE_KUBECONFIG}"

echo
echo "📝 Generating simulated kube-bench report at: ${REPORT}"
cat <<'EOF' > "${REPORT}"
# kube-bench (SIMULATED) — CIS Kubernetes Benchmark (API Server focus)
# NOTE: This file represents what a CIS scan would flag before remediation.

[INFO] 1 Control Plane Security Configuration
[INFO] 1.2 API Server

[FAIL] 1.2.1 Ensure that the --anonymous-auth argument is set to false
       * Reason: kube-apiserver --anonymous-auth=true
       * Remediation: Set --anonymous-auth=false in /etc/kubernetes/manifests/kube-apiserver.yaml

[FAIL] 1.2.2 Ensure that the --authorization-mode argument is not set to AlwaysAllow
       * Reason: kube-apiserver --authorization-mode=AlwaysAllow
       * Remediation: Set --authorization-mode=Node,RBAC in kube-apiserver manifest

[FAIL] 1.2.8 Ensure that the admission control plugin NodeRestriction is set
       * Reason: NodeRestriction not enabled
       * Remediation: Ensure --enable-admission-plugins includes NodeRestriction

[FAIL] RBAC Ensure system:anonymous is not bound to cluster-admin
       * Reason: ClusterRoleBinding system-anonymous grants cluster-admin to system:anonymous
       * Remediation: Delete ClusterRoleBinding system-anonymous

== Summary ==
4 checks FAIL
EOF

echo
echo "🔁 kube-apiserver is a static pod; kubelet will restart it automatically after manifest changes."
echo "   (Give it a few seconds if you observe transient API downtime.)"
echo
echo "✅ Q02 lab setup complete."
echo
echo "Candidate instructions:"
echo "1) Read: sudo cat ${REPORT}"
echo "2) Secure API server:"
echo "   - forbid anonymous auth"
echo "   - set authorization-mode=Node,RBAC"
echo "   - enable admission plugin NodeRestriction"
echo "3) Remove ClusterRoleBinding system-anonymous"
echo
echo "Important: kubectl is currently configured to use anonymous access (${INSECURE_KUBECONFIG})."
echo "After you secure the API server, kubectl with this config will stop working."
echo "Use admin kubeconfig to regain access:"
echo "  export KUBECONFIG=${ADMIN_KUBECONFIG}"
