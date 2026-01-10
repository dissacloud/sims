\# Misbehaving Pod reading /dev/mem



A security alert indicates that a Pod belonging to the `ollama` application is reading `/dev/mem`.



Requirements:

1\. Identify the misbehaving Pod.

2\. Identify the Deployment that manages it.

3\. Scale the identified Deployment to \*\*zero replicas\*\* to contain the issue.



Constraints:

\- Do not modify any Deployment configuration except scaling down replicas.

\- Ensure Docker Engine is running (validate with `docker info`).

\- The cluster may use containerd; Docker may not list Kubernetes containers. Use Kubernetes resources to identify the Pod/Deployment.



Deliverable:

\- `deployment/ollama` in namespace `ai` must be scaled to 0 replicas.

