\# Solution (CKS / Playground Safe)



\## Step 0 — Verify Docker Engine is running (required)

```bash

sudo docker info >/dev/null \&\& echo "docker OK"

Note: Kubernetes may use containerd; Docker might not list Kubernetes containers. That is fine.



Step 1 — Identify the misbehaving Pod

List ollama pods:



bash

Copy code

kubectl -n ai get pods -l app=ollama -o wide

Confirm /dev/mem reads from logs:



bash

Copy code

kubectl -n ai logs -l app=ollama --tail=20

Capture the Pod name:



bash

Copy code

POD=$(kubectl -n ai get pod -l app=ollama -o jsonpath='{.items\[0].metadata.name}')

echo "$POD"

Step 2 — Identify the owning Deployment (Pod -> ReplicaSet -> Deployment)

Get ReplicaSet owner of the Pod:



bash

Copy code

RS=$(kubectl -n ai get pod "$POD" -o jsonpath='{.metadata.ownerReferences\[0].name}')

echo "$RS"

Get Deployment owner of that ReplicaSet:



bash

Copy code

DEP=$(kubectl -n ai get rs "$RS" -o jsonpath='{.metadata.ownerReferences\[0].name}')

echo "$DEP"

Expected: ollama



Step 3 — Contain by scaling the Deployment to zero (only allowed change)

bash

Copy code

kubectl -n ai scale deployment "$DEP" --replicas=0

Step 4 — Verify (matches grader)

Deployment replicas:



bash

Copy code

kubectl -n ai get deploy ollama -o jsonpath='{.spec.replicas}{"\\n"}'

No ollama pods:



bash

Copy code

kubectl -n ai get pods -l app=ollama

Baseline helper remains 1:



bash

Copy code

kubectl -n ai get deploy helper -o jsonpath='{.spec.replicas}{"\\n"}'

bash

Copy code



---



\## 4) `reset.bash`



```bash

\#!/usr/bin/env bash

set -euo pipefail



NS="ai"

DEP\_BAD="ollama"

DEP\_GOOD="helper"

HOST\_DEVMEM="/opt/lab/devmem"



echo "\[reset] Restoring lab baseline..."



kubectl get ns "${NS}" >/dev/null 2>\&1 || kubectl create ns "${NS}"



\# Restore host file

sudo mkdir -p "$(dirname "${HOST\_DEVMEM}")"

echo "SIMULATED\_KERNEL\_MEMORY\_DO\_NOT\_READ" | sudo tee "${HOST\_DEVMEM}" >/dev/null

sudo chmod 600 "${HOST\_DEVMEM}"



\# Restore replicas

kubectl -n "${NS}" scale deploy "${DEP\_GOOD}" --replicas=1 >/dev/null 2>\&1 || true

kubectl -n "${NS}" scale deploy "${DEP\_BAD}"  --replicas=1 >/dev/null 2>\&1 || true



kubectl -n "${NS}" rollout status deploy/"${DEP\_GOOD}" --timeout=120s || true

kubectl -n "${NS}" rollout status deploy/"${DEP\_BAD}"  --timeout=120s || true



echo "\[reset] Done."

kubectl -n "${NS}" get pods -o wide || true

