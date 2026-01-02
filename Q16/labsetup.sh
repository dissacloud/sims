#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-clever-cactus}"
DEPLOY="${DEPLOY:-clever-cactus}"
SECRET="${SECRET:-clever-cactus}"

CERT_DIR="${CERT_DIR:-/home/candidate/clever-cactus}"
CERT_CRT="${CERT_CRT:-${CERT_DIR}/web k8s.local.crt}"
CERT_KEY="${CERT_KEY:-${CERT_DIR}/web k8s.local.key}"

echo "== Q16 Lab Setup (TLS Secret) =="
echo "Namespace:  ${NS}"
echo "Deployment: ${DEPLOY}"
echo "Secret:     ${SECRET}"
echo "Cert path:  ${CERT_CRT}"
echo "Key path:   ${CERT_KEY}"

# 1) Ensure namespace exists
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create ns "${NS}" >/dev/null

# 2) Create cert/key files (self-signed) at exact paths (including space)
sudo mkdir -p "${CERT_DIR}"
sudo chown -R "$(id -u):$(id -g)" "${CERT_DIR}"

# Generate a self-signed cert if missing
if [ ! -f "${CERT_CRT}" ] || [ ! -f "${CERT_KEY}" ]; then
  echo "[INFO] Generating self-signed cert/key at required paths..."
  openssl req -x509 -nodes -newkey rsa:2048 \
    -subj "/CN=web.k8s.local" \
    -keyout "${CERT_KEY}" \
    -out "${CERT_CRT}" \
    -days 365 >/dev/null 2>&1
fi

chmod 600 "${CERT_KEY}"
chmod 644 "${CERT_CRT}"

# TRAP 1: Create a decoy directory with similar files (wrong path)
sudo mkdir -p "${CERT_DIR}/decoy"
openssl req -x509 -nodes -newkey rsa:2048 \
  -subj "/CN=decoy.k8s.local" \
  -keyout "${CERT_DIR}/decoy/web.k8s.local.key" \
  -out "${CERT_DIR}/decoy/web.k8s.local.crt" \
  -days 365 >/dev/null 2>&1 || true

# 3) Create Deployment + Service.
# The Deployment is ALREADY configured to use the TLS Secret by name.
# Candidate MUST ONLY create the secret, not edit this deployment.

cat <<EOF | kubectl -n "${NS}" apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: ${DEPLOY}
  ports:
  - name: https
    port: 443
    targetPort: 8443
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOY}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DEPLOY}
  template:
    metadata:
      labels:
        app: ${DEPLOY}
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8443
        volumeMounts:
        - name: tls
          mountPath: /etc/tls
          readOnly: true
        - name: nginx-conf
          mountPath: /etc/nginx/conf.d
          readOnly: true
      volumes:
      - name: tls
        secret:
          secretName: ${SECRET}
          optional: false
      - name: nginx-conf
        configMap:
          name: nginx-tls-conf
EOF

# ConfigMap for nginx TLS listener
cat <<'EOF' | kubectl -n "${NS}" apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-tls-conf
data:
  default.conf: |
    server {
      listen 8443 ssl;
      server_name web.k8s.local;

      ssl_certificate     /etc/tls/tls.crt;
      ssl_certificate_key /etc/tls/tls.key;

      location / {
        return 200 "ok\n";
      }
    }
EOF

# TRAP 2: Create a decoy secret in the WRONG namespace (default)
kubectl -n default delete secret "${SECRET}" >/dev/null 2>&1 || true
kubectl -n default create secret generic "${SECRET}" --from-literal=trap=1 >/dev/null 2>&1 || true

# Ensure the real secret does NOT exist in target namespace (so question is required)
kubectl -n "${NS}" delete secret "${SECRET}" >/dev/null 2>&1 || true

echo "[INFO] Waiting for deployment rollout (it will NOT become Ready until secret is created)..."
set +e
kubectl -n "${NS}" rollout status deploy/"${DEPLOY}" --timeout=20s >/dev/null 2>&1
set -e

echo
echo "== Lab state summary =="
echo "- Target secret (should be missing):"
kubectl -n "${NS}" get secret "${SECRET}" >/dev/null 2>&1 && echo "UNEXPECTED: secret exists" || echo "OK: secret missing"
echo "- Pod status (expected not Ready due to missing secret):"
kubectl -n "${NS}" get pods -o wide
echo "- Required files:"
ls -l "${CERT_DIR}"
echo
echo "Run: ./question.sh"
