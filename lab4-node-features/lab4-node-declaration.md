# Lab 4: Node Declared Features (Alpha)

## Overview
Nodes automatically advertise their supported Kubernetes features to the scheduler.

**Feature Status**: Alpha in v1.35 ✅

## Exercise: View Node Features

```bash
# Check if feature is available
kubectl get node minikube -o jsonpath='{.status.declaredFeatures}' | jq

# Expected output (example):
# {
#   "features": [
#     "InPlacePodVerticalScaling",
#     "SidecarContainers", 
#     "PodReadyToStartContainersCondition"
#   ]
# }
```

## Use Case: Schedule Pods Based on Node Features

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: feature-aware-pod
spec:
  containers:
  - name: app
    image: nginx:1.25
  # Schedule only on nodes supporting in-place resize
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node.kubernetes.io/declared-feature-InPlacePodVerticalScaling
            operator: Exists
```

## Why This Matters

**During Upgrades**: Mixed-version clusters (v1.34 and v1.35 nodes)
- v1.35 nodes declare new features
- v1.34 nodes don't
- Scheduler avoids scheduling incompatible pods

**Verification**:
```bash
# List all nodes with their declared features
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
VERSION:.status.nodeInfo.kubeletVersion,\
FEATURES:.status.declaredFeatures.features
```

---

**Lab 3 Duration**: 10 minutes  
**Lab 4 Duration**: 5 minutes