# Solution: Misbehaving Pod Reading /dev/mem (CKS / Playground with containerd)

## Objective

Identify the `ollama` Pod that is reading `/dev/mem`, determine the owning Deployment, and scale that Deployment to **0 replicas**. Do not change any other configuration.

> Environment note: In CKS/Playground the Kubernetes runtime is typically \*\*containerd\*\*, so `docker ps` may show nothing. Use `crictl` for runtime inspection.

---

## Step 1 — Confirm the `ollama` Pod exists and is misbehaving

List pods:

```bash
kubectl -n ai get pods -o wide
```

Confirm the behaviour from logs (you should see repeated “reading /dev/mem” output in this lab):

```bash
kubectl -n ai logs -l app=ollama --tail=30
```

or



```bash
kubectl -n ai logs -l <the pods under the namespace> --tail=30
```

&nbsp;



Capture the Pod name:

```bash
POD=$(kubectl -n ai get pod -l app=ollama -o jsonpath='{.items\[0].metadata.name}')
echo "POD=$POD"
```

---

## Step 2 — Validate at runtime with `crictl` (containerd)

List running containers and locate `ollama`:

```bash
crictl ps | grep -i ollama
```

Capture the container ID (first column of the matching line):

```bash
CID=$(crictl ps | awk 'tolower($0) ~ /ollama/ {print $1; exit}')
echo "CID=$CID"
```

Inspect the container for evidence of the `/dev/mem` mount:

```bash
crictl inspect "$CID" | grep -nE '(/dev/mem|/opt/lab/devmem|mounts)' | head -n 80
```

Optional: prove `/dev/mem` exists inside the container:

```bash
crictl exec -it "$CID" sh -lc 'ls -l /dev/mem; head -c 16 /dev/mem 2>/dev/null | hexdump -C'
```

---

## Step 3 — Identify the owning Deployment (Pod → ReplicaSet → Deployment)

Get the ReplicaSet that owns the Pod:

```bash
RS=$(kubectl -n ai get pod "$POD" -o jsonpath='{.metadata.ownerReferences\[0].name}')
echo "RS=$RS"
```

Get the Deployment that owns the ReplicaSet:

```bash
DEP=$(kubectl -n ai get rs "$RS" -o jsonpath='{.metadata.ownerReferences\[0].name}')
echo "DEP=$DEP"
```

Expected: `DEP=ollama`

---

## Step 4 — Contain the issue by scaling the Deployment to zero

This is the only permitted change:

```bash
kubectl -n ai scale deployment "$DEP" --replicas=0
```

---

## Step 5 — Verify containment (grader-aligned)

Deployment replicas are 0:

```bash
kubectl -n ai get deploy "$DEP" -o jsonpath='{.spec.replicas}{"\\n"}'
```

No `ollama` pods remain:

```bash
kubectl -n ai get pods -l app=ollama
```

If the lab includes a baseline deployment (e.g., `helper`), confirm it remains unchanged:

```bash
kubectl -n ai get deploy helper -o jsonpath='{.spec.replicas}{"\\n"}'
```

---

## Expected End State

* `deployment/ollama` in namespace `ai` has `spec.replicas: 0`
* No Pods with label `app=ollama` are running
* No other Deployments were modified
* Runtime inspection performed using `crictl` (containerd)
