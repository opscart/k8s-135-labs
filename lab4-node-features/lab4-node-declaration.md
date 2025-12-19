# Lab 4: Node Declared Features (Alpha)

## Overview

Node Declared Features is an **Alpha feature** in Kubernetes 1.35 that allows nodes to automatically advertise which features they support. This enables intelligent pod scheduling based on node capabilities, especially useful during cluster upgrades with mixed versions.

**Feature Status:**
- Alpha in Kubernetes 1.35 ✅
- Requires feature gate: `NodeDeclaredFeatures=true`

---

### The Setup
I enabled the Alpha feature gate in kubelet config:
```yaml
featureGates:
  NodeDeclaredFeatures: true
```

### The Result
The node immediately started advertising its capabilities:
```json
{
  "declaredFeatures": [
    "GuaranteedQoSPodCPUResize"
  ]
}
```

### The Connection
Notice the declared feature? It's the same capability we tested in Lab 1! 
The node is automatically advertising that it supports Guaranteed QoS pod 
CPU resizing without restarts.

### Why This Matters
During cluster upgrades with mixed K8s versions, this enables intelligent 
scheduling - newer pods only land on nodes that support their features.


### The Problem: Mixed-Version Clusters

During rolling upgrades, you may have nodes running different Kubernetes versions:

```
Cluster During Upgrade:
├─ node-1 (K8s 1.34) → No in-place pod resize
├─ node-2 (K8s 1.34) → No in-place pod resize
├─ node-3 (K8s 1.35) → HAS in-place pod resize ✅
└─ node-4 (K8s 1.35) → HAS in-place pod resize ✅
```

**Without Node Declared Features:**
- Scheduler doesn't know which nodes support which features
- Pods using new features might land on old nodes → **Fail**
- Requires manual node labeling

**With Node Declared Features:**
- Nodes automatically declare: `"I support GuaranteedQoSPodCPUResize"`
- Scheduler can route pods to compatible nodes
- Zero manual configuration needed

---

## Real-World Use Cases

### 1. Safe Rolling Upgrades
```yaml
# Pod only schedules on nodes supporting the feature
apiVersion: v1
kind: Pod
metadata:
  name: modern-app
spec:
  # Future: Could use node affinity based on declared features
  containers:
  - name: app
    image: myapp:latest
    resources:
      requests:
        cpu: "500m"
```

### 2. Feature Detection
```bash
# See what features each node supports
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
FEATURES:.status.declaredFeatures
```

### 3. Gradual Feature Rollout
- Deploy new feature to subset of nodes
- Let nodes declare capability
- Scheduler automatically routes compatible workloads

---

## Prerequisites

```bash
# Verify minikube is running
minikube status

# Check Kubernetes version
kubectl version --short
```

---

## Exercise 1: Enable Node Declared Features

### Step 1: Check Current Status

```bash
# Check if feature is currently enabled
kubectl get --raw /metrics | grep NodeDeclaredFeatures
```

**Expected output (before enabling):**
```
kubernetes_feature_enabled{name="NodeDeclaredFeatures",stage="ALPHA"} 0
```

---

### Step 2: Backup Kubelet Configuration

```bash
minikube ssh

# Create backup
sudo cp /var/lib/kubelet/config.yaml /tmp/kubelet-config.yaml.backup

# Verify backup
ls -la /tmp/kubelet-config.yaml.backup

exit
```

---

### Step 3: View Current Configuration

```bash
minikube ssh

# Check current kubelet config
sudo cat /var/lib/kubelet/config.yaml | head -20
```

**Current config (no feature gates):**
```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 0s
    enabled: true
```

---

### Step 4: Add Feature Gate

```bash
# Still in minikube SSH
sudo vi /var/lib/kubelet/config.yaml
```

**Add these lines at the top** (after `apiVersion:`):

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
featureGates:
  NodeDeclaredFeatures: true
authentication:
  anonymous:
    enabled: false
```

**Save and exit** (`:wq` in vi)

**Verify the change:**
```bash
sudo cat /var/lib/kubelet/config.yaml | grep -A 3 featureGates
```

**Expected output:**
```yaml
featureGates:
  NodeDeclaredFeatures: true
authentication:
```

---

### Step 5: Restart Kubelet

```bash
# Still in minikube SSH
sudo systemctl restart kubelet

# Wait a few seconds
sleep 5

# Check kubelet status
sudo systemctl status kubelet
```

**Expected output:**
```
● kubelet.service - kubelet: The Kubernetes Node Agent
   Active: active (running) since ...
```

**Check for errors:**
```bash
sudo journalctl -u kubelet -n 50 --no-pager | grep -i error
```

```bash
# Exit minikube
exit
```

---

### Step 6: Verify Feature is Enabled

```bash
# Check feature gate metric
kubectl get --raw /metrics | grep NodeDeclaredFeatures

# Check if node declares features
kubectl get node minikube -o jsonpath='{.status.declaredFeatures}' | jq
```

**Expected output:**
```json
[
  "GuaranteedQoSPodCPUResize"
]
```

✅ **Success!** The node is now declaring features!

---

### Step 7: View Declared Features in Detail

```bash
# Get all declared features
kubectl get node minikube -o jsonpath='{.status.declaredFeatures[*]}' | tr ' ' '\n'

# View full node status
kubectl get node minikube -o yaml | grep -B 5 -A 10 "declaredFeatures"
```

**Expected output:**
```yaml
  daemonEndpoints:
    kubeletEndpoint:
      Port: 10250
  declaredFeatures:
  - GuaranteedQoSPodCPUResize
  images:
```

---

## Exercise 2: Test Feature-Aware Scheduling

### Step 1: Create a Pod

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: feature-aware-pod
spec:
  containers:
  - name: app
    image: nginx:1.25
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
EOF
```

---

### Step 2: Verify Pod Scheduled

```bash
# Check pod status
kubectl get pod feature-aware-pod

# Check which node it's on
kubectl get pod feature-aware-pod -o jsonpath='{.spec.nodeName}'
```

**Expected output:**
```
NAME                READY   STATUS    RESTARTS   AGE
feature-aware-pod   1/1     Running   0          10s

minikube
```

---

### Step 3: View Pod Details

```bash
# Check pod events
kubectl describe pod feature-aware-pod | grep -A 5 Events

# Clean up
kubectl delete pod feature-aware-pod
```

---

## Exercise 3: Compare Before and After

### What Changed?

```bash
minikube ssh

echo "=== BEFORE (Backup) ==="
sudo cat /tmp/kubelet-config.yaml.backup | grep -A 3 "^apiVersion"

echo ""
echo "=== AFTER (Current) ==="
sudo cat /var/lib/kubelet/config.yaml | grep -A 3 "^apiVersion"

exit
```

**Output:**
```
=== BEFORE (Backup) ===
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false

=== AFTER (Current) ===
apiVersion: kubelet.config.k8s.io/v1beta1
featureGates:
  NodeDeclaredFeatures: true
authentication:
```

---

## Understanding Declared Features

### What is GuaranteedQoSPodCPUResize?

This feature (which our node declares) relates to **in-place pod resizing** for Guaranteed QoS pods (Lab 1!).

**Why it's declared:**
- K8s 1.35 supports in-place CPU resize for Guaranteed QoS pods
- Node advertises this capability
- Scheduler can route compatible pods here

**Connection to Lab 1:**
Remember when we resized pods without restart? This is the feature the node is advertising!

---

### Future Feature Examples

In mixed-version clusters, nodes might declare:

```json
[
  "GuaranteedQoSPodCPUResize",
  "SidecarContainers",
  "PodReadyToStartContainersCondition",
  "InPlacePodVerticalScaling"
]
```

---

## Rollback Instructions

### If Kubelet Fails to Start

```bash
# Restore backup
minikube ssh
sudo cp /tmp/kubelet-config.yaml.backup /var/lib/kubelet/config.yaml
sudo systemctl restart kubelet
exit

# Verify cluster is healthy
kubectl get nodes
```

---

### If Cluster is Broken

```bash
# Nuclear option
minikube delete
minikube start --kubernetes-version=v1.35.0 --cpus=2 --memory=4096

# Verify
kubectl get nodes
```

---

## Production Considerations

### Alpha Feature Warning

⚠️ **This is an Alpha feature in K8s 1.35**
- Not recommended for production yet
- API may change in future versions
- Test thoroughly in dev/staging

---

### When to Enable

✅ **Good for:**
- Dev/test environments
- Learning about K8s 1.35 features
- Testing mixed-version upgrade scenarios

❌ **Not ready for:**
- Production clusters
- Critical workloads
- Managed Kubernetes (may not allow kubelet config changes)

---

### Future (Beta/GA)

When this feature reaches GA:
- Enabled by default
- Scheduler will use it automatically
- Node affinity rules based on features
- Better upgrade experiences

---

## Cleanup

```bash
# Restore original kubelet config
minikube ssh
sudo cp /tmp/kubelet-config.yaml.backup /var/lib/kubelet/config.yaml
sudo systemctl restart kubelet
exit

# Wait for kubelet to restart
sleep 10

# Verify cluster is healthy
kubectl get nodes

# Verify feature is disabled
kubectl get --raw /metrics | grep NodeDeclaredFeatures
# Should show: kubernetes_feature_enabled{name="NodeDeclaredFeatures",stage="ALPHA"} 0

# Clean up backup
minikube ssh "sudo rm /tmp/kubelet-config.yaml.backup"
```

---

## Troubleshooting

### Issue: Kubelet won't start

**Check logs:**
```bash
minikube ssh
sudo journalctl -u kubelet -n 100 --no-pager | grep -i error
```

**Common causes:**
- Invalid YAML syntax
- Typo in feature gate name
- Incompatible feature gate

**Solution:**
```bash
# Restore backup
sudo cp /tmp/kubelet-config.yaml.backup /var/lib/kubelet/config.yaml
sudo systemctl restart kubelet
```

---

### Issue: No features declared

**Check:**
1. Feature gate is enabled:
   ```bash
   minikube ssh "sudo cat /var/lib/kubelet/config.yaml | grep featureGates"
   ```

2. Kubelet restarted:
   ```bash
   minikube ssh "sudo systemctl status kubelet"
   ```

3. Node status updated:
   ```bash
   kubectl get node minikube -o yaml | grep declaredFeatures
   ```

---

### Issue: Metric shows 0

```bash
kubectl get --raw /metrics | grep NodeDeclaredFeatures
# kubernetes_feature_enabled{name="NodeDeclaredFeatures",stage="ALPHA"} 0
```

**Note:** The metric might show 0 even if the feature works. Check the node status instead:
```bash
kubectl get node minikube -o jsonpath='{.status.declaredFeatures}'
```

---

## Key Takeaways

✅ **Node Declared Features is Alpha** - working but experimental  
✅ **Requires feature gate** - must enable in kubelet config  
✅ **Automatic capability advertisement** - nodes declare what they support  
✅ **Useful for upgrades** - mixed-version cluster support  
✅ **GuaranteedQoSPodCPUResize declared** - relates to Lab 1 in-place resize  

---

## What We Learned

### Technical Insights
1. Feature gate enables node capability advertisement
2. Kubelet configuration changes require restart
3. Node status includes `declaredFeatures` array
4. First declared feature: `GuaranteedQoSPodCPUResize`

### Practical Experience
1. Modifying kubelet config is straightforward
2. Kubelet restart is quick (~5 seconds)
3. Cluster remains stable after change
4. Feature connects to other K8s 1.35 capabilities

---

## Connection to Other Labs

- **Lab 1 (In-Place Resize):** Node declares `GuaranteedQoSPodCPUResize` ✅
- **Lab 2 (Gang Scheduling):** Future: Nodes could declare scheduling capabilities
- **Lab 3 (Structured Auth):** Complementary API server evolution
- **Lab 4 (This lab):** Foundation for smart scheduling

---

## References

- [KEP-4568: Node Declared Features](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/4568-node-declared-features)
- [Feature Gates Documentation](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/)
- [Kubelet Configuration Reference](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/)

---

**Lab Duration**: 20-30 minutes  
**Difficulty**: Intermediate  
**Risk Level**: Medium (requires kubelet configuration)  
**Production Readiness**: Alpha - not ready for production

---

**Tested on:** Kubernetes 1.35.0, Minikube, Azure VM (2 vCPU, 8GB RAM)  
**Date:** December 19, 2025