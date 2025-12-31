#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
== Q13 Solution (instructions) ==

Goal:
Make the Deployment in namespace 'confidential' compliant with PodSecurity 'restricted' and ensure Pods are Running.

1) Confirm why Pods aren't being created (PSA block)
   kubectl -n confidential get rs
   kubectl -n confidential describe rs -l app=nginx-unprivileged | sed -n '/Events:/,$p'

   You should see violations like:
   - allowPrivilegeEscalation must be false
   - capabilities must drop ALL (and no NET_ADMIN add)
   - runAsNonRoot must be true
   - seccompProfile must be RuntimeDefault/Localhost

2) Edit the manifest at ~/nginx-unprivileged.yaml
   vi ~/nginx-unprivileged.yaml

   Make these changes:

   Pod-level securityContext (recommended):
   spec.template.spec.securityContext:
     runAsNonRoot: true
     seccompProfile:
       type: RuntimeDefault

   Container-level securityContext:
     allowPrivilegeEscalation: false
     capabilities:
       drop: ["ALL"]
     runAsUser: 101
     runAsGroup: 101
     readOnlyRootFilesystem: true

   IMPORTANT for readOnlyRootFilesystem:
   Add emptyDir volumes + mounts to provide writable paths for nginx:
     /tmp
     /var/cache/nginx

   Example snippet (container):
     volumeMounts:
     - name: tmp
       mountPath: /tmp
     - name: nginx-cache
       mountPath: /var/cache/nginx

   Example snippet (pod spec):
     volumes:
     - name: tmp
       emptyDir: {}
     - name: nginx-cache
       emptyDir: {}

   Also ensure:
   - image remains: nginxinc/nginx-unprivileged:1.25-alpine
   - containerPort remains: 8080
   - Do NOT add privileged, hostNetwork, hostPID, hostPath, etc.

3) Apply changes
   kubectl -n confidential apply -f ~/nginx-unprivileged.yaml

4) Verify Pods are created and Running
   kubectl -n confidential get pods -l app=nginx-unprivileged -w

   If it still fails:
   - describe the pod:
     kubectl -n confidential describe pod <pod>
   - check logs:
     kubectl -n confidential logs <pod> -c nginx

   Common runtime failure if volumes/mounts missing with readOnlyRootFilesystem:
   - cannot write to /tmp or /var/cache/nginx

EOF
