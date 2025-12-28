# Q10 — ServiceAccount Token Hardening

Context:
A Deployment is improperly handling ServiceAccount tokens.

Tasks:
1. Disable automounting of API credentials on ServiceAccount stats-monitor-sa (namespace monitoring).
2. Modify Deployment stats-monitor to:
   - Inject a ServiceAccount token using a projected volume named 'token'
   - Mount the token at:
     /var/run/secrets/kubernetes.io/serviceaccount/token
   - Ensure the volume mount is read-only

Constraints:
- Do not delete resources
- Only modify existing ServiceAccount and Deployment
