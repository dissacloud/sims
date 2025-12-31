#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
== Q13 Solution (restricted PSA compliant + RO rootfs) ==

Goal:
Make the Deployment in namespace 'confidential' compliant with PodSecurity 'restricted'
AND ensure nginx starts successfully with:
  readOnlyRootFilesystem: true
  writable volumes for:
    - /tmp
    - /var/cache/nginx

Steps:

1) Open the manifest:
   vi ~/nginx-unprivileged.yaml

2) Fix Pod/Container security to satisfy restricted PSA.
   You should end up with these minimums:

   Pod spec:
     securityContext:
       runAsNonRoot: true
       seccompProfile:
         type: RuntimeDefault

   Container securityContext:
     allowPrivilegeEscalation: false
     capabilities:
       drop: ["ALL"]
     runAsUser: 101
     runAsGroup: 101
     readOnlyRootFilesystem: true

   And REMOVE any of these if present:
     privileged: true
     capabilities.add (e.g., NET_ADMIN)
     runAsNonRoot: false

3) Because readOnlyRootFilesystem is true, add emptyDir volumes + mounts:
   - /tmp
   - /var/cache/nginx

   Example patch (final desired shape):

   spec:
     securityContext:
       runAsNonRoot: true
       seccompProfile:
         type: RuntimeDefault
     volumes:
     - name: tmp
       emptyDir: {}
     - name: cache
       emptyDir: {}
     containers:
     - name: nginx
       image: nginxinc/nginx-unprivileged:1.25-alpine
       ports:
       - containerPort: 8080
       securityContext:
         runAsUser: 101
         runAsGroup: 101
         allowPrivilegeEscalation: false
         readOnlyRootFilesystem: true
         capabilities:
           drop:
           - ALL
       volumeMounts:
       - name: tmp
         mountPath: /tmp
       - name: cache
         mountPath: /var/cache/nginx

4) Apply and verify:
   kubectl -n confidential apply -f ~/nginx-unprivileged.yaml
   kubectl -n confidential rollout status deploy/nginx-unprivileged --timeout=180s
   kubectl -n confidential get pods -l app=nginx-unprivileged -o wide

5) If it still fails:
   - PSA block will appear in ReplicaSet events:
       kubectl -n confidential describe rs -l app=nginx-unprivileged | sed -n '/Events:/,$p'
   - Runtime crash will appear in logs:
       kubectl -n confidential logs -l app=nginx-unprivileged --tail=120

Expected end state:
- PodSecurity no longer blocks Pod creation
- Pod reaches Running
- nginx binds to 8080 successfully with RO root filesystem (thanks to /tmp and /var/cache/nginx volumes)

EOF
