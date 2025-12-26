# Question 4 — Solution Notes

## 0) Review findings
```bash
sudo cat /root/kube-bench-report-q04.txt
```

## 1) Dockerfile — fix exactly one instruction
File:
```bash
vi ~/subtle-bee/build/Dockerfile
```

The prominent issue is that the final runtime user is root.

Modify **only the final** `USER root` to UID 65535:

```dockerfile
USER 65535
```

Do not add/remove instructions. Do not build the image.

## 2) Deployment manifest — fix exactly one field
File:
```bash
vi ~/subtle-bee/deployment.yaml
```

The prominent issue is:

```yaml
privileged: true
```

Modify only that field:

```yaml
privileged: false
```

Do not add/remove fields.
