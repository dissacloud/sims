#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
== Q13 Solution (instructions) ==

Goal:
Make the Deployment in namespace 'confidential' compliant with the restricted Pod Security Standard,
then confirm pods are Running/Ready.

1) Inspect why pods are failing:
   kubectl -n confidential get rs,pods
   kubectl -n confidential describe rs -l app=nginx-unprivileged
   kubectl -n confidential get events --sort-by=.lastTimestamp | tail -n 30

2) Edit the manifest:
   vi ~/nginx-unprivileged.yaml

   Replace the non-compliant securityContext with a restricted-compliant one, for example:

   spec:
     template:
       spec:
         securityContext:
           runAsNonRoot: true
           seccompProfile:
             type: RuntimeDefault
         containers:
         - name: nginx
           image: nginx:1.25-alpine
           securityContext:
             allowPrivilegeEscalation: false
             readOnlyRootFilesystem: true
             runAsUser: 10001
             runAsGroup: 10001
             capabilities:
               drop: ["ALL"]

   IMPORTANT:
   - Remove privileged:true
   - Do NOT add hostPath/hostNetwork
   - Keep the Deployment name/namespace the same

3) Apply and wait for rollout:
   kubectl apply -f ~/nginx-unprivileged.yaml
   kubectl -n confidential rollout status deploy/nginx-unprivileged --timeout=180s

4) Verify final state:
   kubectl -n confidential get pods -l app=nginx-unprivileged -o wide
   kubectl -n confidential describe pod -l app=nginx-unprivileged | egrep -i 'seccomp|runAs|capabil|privilege|escalation|readonly' || true

5) Run the strict grader:
   bash Q13_Grader_Strict.bash

EOF
