# Quick verification
After running setup, confirm the skew:
  kubectl get nodes -o wide

If it still shows the same version:
1) SSH to the worker and run:
     sudo KUBELET_TAG=v1.33.3 bash /tmp/Q11v5_LabSetUp_worker.bash
2) Then check:
     kubelet --version
     systemctl status kubelet --no-pager
