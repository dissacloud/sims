#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up ImagePolicyWebhook image-scanner integration lab (Q03 v1) — CONTROLPLANE"

APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
BOUNCER_DIR="/etc/kubernetes/bouncer"
ADMISSION_CFG="${BOUNCER_DIR}/admission-configuration.yaml"
WEBHOOK_KUBECONFIG="${BOUNCER_DIR}/imagepolicywebhook.kubeconfig"
VULN_MANIFEST="${HOME}/vulnerable.yaml"
REPORT="/root/kube-bench-report-q03.txt"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"

ts="$(date +%Y%m%d%H%M%S)"
backup_dir="/root/cis-q03-backups-${ts}"
mkdir -p "${backup_dir}"

echo "📦 Backing up existing files to: ${backup_dir}"
for f in "${APISERVER_MANIFEST}" "${ADMISSION_CFG}" "${WEBHOOK_KUBECONFIG}" "${VULN_MANIFEST}"; do
  if [[ -f "$f" ]]; then
    cp -a "$f" "${backup_dir}/$(basename "$f")"
  fi
done

echo
echo "🧩 Creating incomplete bouncer configuration in ${BOUNCER_DIR} ..."
mkdir -p "${BOUNCER_DIR}"
chmod 700 "${BOUNCER_DIR}"

# Incomplete AdmissionConfiguration for ImagePolicyWebhook
cat > "${ADMISSION_CFG}" <<'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  configuration:
    apiVersion: apiserver.config.k8s.io/v1
    kind: ImagePolicyWebhookConfiguration
    # INTENTIONALLY WRONG for the lab:
    # - defaultAllow should be false (deny by default)
    # - failurePolicy should be Fail (deny on backend failure)
    defaultAllow: true
    failurePolicy: Ignore
    imagePolicy:
      kubeConfigFile: /etc/kubernetes/bouncer/imagepolicywebhook.kubeconfig
      allowTTL: 50
      denyTTL: 50
      retryBackoff: 500
EOF

# Incomplete kubeconfig pointing to WRONG endpoint
cat > "${WEBHOOK_KUBECONFIG}" <<'EOF'
apiVersion: v1
kind: Config
clusters:
- name: image-scanner
  cluster:
    # INTENTIONALLY WRONG endpoint for the lab. Candidate must fix to:
    # https://smooth-yak.local/review
    server: https://CHANGE-ME.local/review
    insecure-skip-tls-verify: true
users:
- name: apiserver
  user: {}
contexts:
- name: apiserver@image-scanner
  context:
    cluster: image-scanner
    user: apiserver
current-context: apiserver@image-scanner
EOF
chmod 600 "${ADMISSION_CFG}" "${WEBHOOK_KUBECONFIG}"

echo "✅ Wrote:"
echo "  - ${ADMISSION_CFG}"
echo "  - ${WEBHOOK_KUBECONFIG}"

echo
echo "🧩 Writing test resource (should be denied when webhook is correctly configured): ${VULN_MANIFEST}"
cat > "${VULN_MANIFEST}" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vulnerable
  labels:
    app: vulnerable
spec:
  containers:
  - name: vulnerable
    # Image expected to be denied by the scanner policy in this lab
    image: vulnerable/bad:1.0
    command: ["/bin/sh","-c","sleep 3600"]
EOF

echo
echo "🧩 Breaking kube-apiserver admission setup (so candidate must fix it)..."
if [[ ! -f "${APISERVER_MANIFEST}" ]]; then
  echo "ERROR: ${APISERVER_MANIFEST} not found. This lab expects kubeadm static pods."
  exit 1
fi

# Remove admission-control-config-file if present
sed -i -E '/--admission-control-config-file(=| )/d' "${APISERVER_MANIFEST}"
# Remove ImagePolicyWebhook from enable-admission-plugins list if present
if grep -qE -- '--enable-admission-plugins(=| )' "${APISERVER_MANIFEST}"; then
  # remove token from comma list
  sed -i -E 's/(--enable-admission-plugins(=| )[^"\n ]*)ImagePolicyWebhook,?/\1/g' "${APISERVER_MANIFEST}"
  sed -i -E 's/(--enable-admission-plugins(=| )[^"\n ]*),ImagePolicyWebhook/\1/g' "${APISERVER_MANIFEST}"
fi

echo "✅ kube-apiserver manifest modified to NOT use AdmissionConfiguration and NOT enable ImagePolicyWebhook (initially broken)."

echo
echo "📝 Generating simulated kube-bench report at: ${REPORT}"
cat > "${REPORT}" <<'EOF'
# kube-bench (SIMULATED) — Admission control / ImagePolicyWebhook integration
# NOTE: This report represents pre-remediation findings for the lab.

[INFO] 1 Control Plane Security Configuration
[INFO] 1.2 API Server

[FAIL] APISERVER Ensure ImagePolicyWebhook admission plugin is enabled
       * Reason: kube-apiserver --enable-admission-plugins does not include ImagePolicyWebhook
       * Remediation: Add ImagePolicyWebhook to --enable-admission-plugins in /etc/kubernetes/manifests/kube-apiserver.yaml

[FAIL] APISERVER Ensure AdmissionConfiguration is configured
       * Reason: kube-apiserver missing --admission-control-config-file
       * Remediation: Set --admission-control-config-file=/etc/kubernetes/bouncer/admission-configuration.yaml

[FAIL] ImagePolicyWebhook Ensure deny on backend failure
       * Reason: failurePolicy=Ignore
       * Remediation: Set failurePolicy: Fail

[FAIL] ImagePolicyWebhook Ensure scanner endpoint configured
       * Reason: kubeconfig server is not https://smooth-yak.local/review
       * Remediation: Set clusters[].cluster.server=https://smooth-yak.local/review in imagepolicywebhook.kubeconfig

== Summary ==
4 checks FAIL
EOF

echo
echo "🔁 kube-apiserver is a static pod; kubelet will restart it automatically after manifest edits."
echo "⏳ Waiting for API server to become ready..."
for i in $(seq 1 30); do
  if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw=/readyz >/dev/null 2>&1; then
    echo "✅ API server is ready."
    break
  fi
  sleep 2
done

echo
echo "✅ Q03 lab setup complete."
echo "Candidate should:"
echo "1) Read: sudo cat ${REPORT}"
echo "2) Fix kube-apiserver to:"
echo "   - enable admission plugins required (include ImagePolicyWebhook)"
echo "   - use --admission-control-config-file=${ADMISSION_CFG}"
echo "3) Fix AdmissionConfiguration:"
echo "   - failurePolicy: Fail"
echo "   - defaultAllow: false"
echo "4) Fix backend kubeconfig server to: https://smooth-yak.local/review"
echo "5) Test: kubectl apply -f ${VULN_MANIFEST}  (should be denied)"
echo
echo "Scanner access log hint: /var/log/nginx/access_log (on scanner host, if available)"
