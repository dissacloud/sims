
#!/usr/bin/env bash

Q07 Solution Notes (reference)

1) Edit kube-apiserver manifest:
   /etc/kubernetes/manifests/kube-apiserver.yaml

   Add flags:
   - --audit-policy-file=/etc/kubernetes/logpolicy/audit-policy.yaml
   - --audit-log-path=/var/log/kubernetes/audit-logs.txt
   - --audit-log-maxbackup=2
   - --audit-log-maxage=10

   Add volumeMounts:
   - mountPath: /etc/kubernetes/logpolicy
     name: audit-policy
     readOnly: true
   - mountPath: /var/log/kubernetes
     name: audit-log
     readOnly: false

   Add volumes:
   - name: audit-policy
     hostPath:
       path: /etc/kubernetes/logpolicy
       type: DirectoryOrCreate
   - name: audit-log
     hostPath:
       path: /var/log/kubernetes
       type: DirectoryOrCreate

2) Extend /etc/kubernetes/logpolicy/audit-policy.yaml rules with ordering (specific before catch-all):

- level: None
  verbs: ["watch"]
- level: None
  nonResourceURLs: ["/healthz*", "/readyz*", "/livez*"]

# deployments in webapps at RequestResponse
- level: RequestResponse
  resources:
  - group: "apps"
    resources: ["deployments"]
  namespaces: ["webapps"]

# namespaces at RequestResponse
- level: RequestResponse
  resources:
  - group: ""
    resources: ["namespaces"]

# configmaps/secrets at Metadata
- level: Metadata
  resources:
  - group: ""
    resources: ["configmaps", "secrets"]

# catch-all at Metadata (MUST be last)
- level: Metadata

3) Generate events, then check /var/log/kubernetes/audit-logs.txt


chmod +x Q07v2_SolutionNotes.bash
