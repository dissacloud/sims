\# CKS Q14 Simulation (Docker hardening on worker)



This sim reproduces a CKS-style task:

\- Remove user `developer` from `docker` group only

\- Configure Docker so `/var/run/docker.sock` is group-owned by `root`

\- Ensure Docker does not listen on any TCP port

\- Confirm Kubernetes cluster is healthy



\## Quick start (from control-plane)

```bash

chmod +x \*.sh



\# 1) Break it (lab setup)

./labsetup.sh



\# 2) Read the question

cat questions.md



\# 3) Solve it yourself (manual), or run the reference solution

./solution.sh



\# 4) Grade your work

./grader.sh



\# 5) Reset to vulnerable state for another attempt

./reset.sh



