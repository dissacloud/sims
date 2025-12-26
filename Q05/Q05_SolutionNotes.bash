# Question 5 — Solution Notes

## 0) Read the findings
```bash
sudo cat /root/kube-bench-report-q05.txt
```

## 1) Identify the misbehaving pod
List pods in namespace:
```bash
kubectl -n ollama get pods -o wide
```

Inspect pod specs for access to `/dev/mem` (look for hostPath /dev/mem or mountPath /dev/mem):
```bash
kubectl -n ollama get pod <POD> -o yaml | grep -n "/dev/mem" -n
```

Optional runtime check using docker (container name will vary):
```bash
docker ps | grep ollama
docker logs --tail=50 <container_id>
```

## 2) Identify the Deployment that owns the pod
Get owner chain:
```bash
kubectl -n ollama get pod <POD> -o jsonpath='{.metadata.ownerReferences[0].kind} {.metadata.ownerReferences[0].name}{"\n"}'
kubectl -n ollama get rs <REPLICASET> -o jsonpath='{.metadata.ownerReferences[0].kind} {.metadata.ownerReferences[0].name}{"\n"}'
```

## 3) Scale only the offending Deployment to 0
```bash
kubectl -n ollama scale deploy/<DEPLOYMENT_NAME> --replicas=0
```

Validate:
```bash
kubectl -n ollama get deploy
kubectl -n ollama get pods
```

Do not modify other deployments.
