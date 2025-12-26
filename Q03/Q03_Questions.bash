# Question 3 — Integrate Container Image Scanner (ImagePolicyWebhook)

## Context
You must fully integrate a container image scanner into the kubeadm-provisioned cluster.

An incomplete configuration is located at:
- `/etc/kubernetes/bouncer/`

A functional image scanner is available via HTTPS at:
- `https://smooth-yak.local/review`

A (simulated) kube-bench report is available at:
- `/root/kube-bench-report-q03.txt`

## Task
1. Re-configure the API server to enable the admission configuration you were provided.
   - Ensure the API server is configured to support the provided `AdmissionConfiguration`.
2. Reconfigure the ImagePolicyWebhook configuration to **deny images on backend failure**.
3. Complete the backend configuration to point to the scanner endpoint:
   - `https://smooth-yak.local/review`
4. Test the configuration by deploying the test resource:
   - `~/vulnerable.yaml`
   - This resource uses an image that should be **denied**.
   - You may delete and re-create as often as needed.

## Notes
- API server runs as a kubeadm static pod:
  - `/etc/kubernetes/manifests/kube-apiserver.yaml`
- ImagePolicyWebhook AdmissionConfiguration:
  - `/etc/kubernetes/bouncer/admission-configuration.yaml`
- Webhook kubeconfig (backend connection details):
  - `/etc/kubernetes/bouncer/imagepolicywebhook.kubeconfig`
- Scanner access logs may be available at:
  - `/var/log/nginx/access_log`
