# Lab 2: Gang Scheduling for AI/ML Workloads (Alpha)

## Overview

Gang Scheduling ensures that a group of pods (a "gang") are scheduled together as a unit - all pods in the group start at the same time, or none of them start. This prevents resource deadlocks in distributed workloads.

**Feature Status:**
- Alpha in Kubernetes 1.35 ✅
- Requires external scheduler-plugins

**Use Cases:**
- Distributed AI/ML training (PyTorch, TensorFlow)
- Apache Spark jobs
- MPI applications
- Any workload requiring multiple coordinated pods

---

## The Problem Gang Scheduling Solves

### Without Gang Scheduling:
```
Training Job: Needs 8 GPU pods (1 master + 7 workers)
Cluster: Only 5 GPUs available

Result:
├─ 5 worker pods scheduled → consume all GPUs
├─ Master + 2 workers pending
├─ Training cannot start
├─ Resources wasted indefinitely
└─ Other jobs blocked
```

### With Gang Scheduling:
```
Training Job: Needs 8 GPU pods
Cluster: Only 5 GPUs available

Result:
├─ All 8 pods remain pending
├─ No resources wasted
├─ Smaller jobs can run
└─ Once 8 GPUs available → all pods scheduled together
```

---

## Setup Challenges & Reality Check

### What We Discovered

During testing, we found that Kubernetes 1.35's **native Workload API** (Alpha) requires:
- Feature gate `WorkloadAwareScheduling=true`
- Custom scheduler configuration
- Kubelet modifications that caused instability

**Solution:** Use **scheduler-plugins** project - the mature, production-tested implementation that works with the default Kubernetes scheduler.

---

## Prerequisites

### Automated Setup (Recommended)

```bash
cd ~/k8s-135-labs/lab2-gang-scheduling
./setup-gang-scheduling.sh
```

**What this installs:**
1. scheduler-plugins controller
2. PodGroup CRD
3. Verifies installation

**Time:** ~2 minutes

---

### Manual Setup (Alternative)

If you prefer manual installation:

```bash
# Step 1: Install scheduler-plugins controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/scheduler-plugins/master/manifests/install/all-in-one.yaml

# Step 2: Install PodGroup CRD
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/scheduler-plugins/master/manifests/coscheduling/crd.yaml

# Step 3: Verify installation
kubectl get crd podgroups.scheduling.x-k8s.io
kubectl get pods -n scheduler-plugins
```

---

## Exercise 1: Basic Gang Scheduling

### Step 1: Create PodGroup

```bash
kubectl apply -f - <<EOF
apiVersion: scheduling.x-k8s.io/v1alpha1
kind: PodGroup
metadata:
  name: training-gang
  namespace: default
spec:
  scheduleTimeoutSeconds: 300
  minMember: 3
EOF
```

**Verify PodGroup created:**
```bash
kubectl get podgroup training-gang
```

**Expected output:**
```
NAME            PHASE     MINMEMBER   RUNNING   SUCCEEDED   FAILED   AGE
training-gang   Pending   3                                          0s
```

---

### Step 2: Create 3 Pods in the Gang

```bash
for i in {1..3}; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: training-worker-$i
  labels:
    scheduling.x-k8s.io/pod-group: training-gang
spec:
  containers:
  - name: worker
    image: nginx:1.25
    resources:
      requests:
        cpu: "200m"
        memory: "128Mi"
    command: ["sleep", "3600"]
EOF
done
```

**Key points:**
- Label `scheduling.x-k8s.io/pod-group: training-gang` associates pods with PodGroup
- **No `schedulerName` needed** - works with default scheduler!
- All pods must have the same label value

---

### Step 3: Watch Gang Scheduling in Action

```bash
# Watch pods schedule together
kubectl get pods -l scheduling.x-k8s.io/pod-group=training-gang -w
```

**Expected behavior:**
```
NAME                READY   STATUS    RESTARTS   AGE
training-worker-1   1/1     Running   0          6s
training-worker-2   1/1     Running   0          6s
training-worker-3   1/1     Running   0          6s
```

✅ **All pods go Running within seconds of each other!**

---

### Step 4: Verify PodGroup Status

```bash
kubectl get podgroup training-gang -o yaml | grep -A 10 "status:"
```

**Expected output:**
```yaml
status:
  phase: Running
  running: 3
  scheduleStartTime: "2025-12-19T18:54:07Z"
  scheduled: 3
```

---

## Exercise 2: Test Gang Failure (All-or-Nothing)

Now let's prove that gang scheduling prevents partial scheduling by creating a gang that's too large for our cluster.

### Step 1: Create Large Gang

```bash
kubectl apply -f - <<EOF
apiVersion: scheduling.x-k8s.io/v1alpha1
kind: PodGroup
metadata:
  name: large-training-gang
spec:
  scheduleTimeoutSeconds: 120
  minMember: 5
EOF
```

---

### Step 2: Create 5 Pods with High CPU

```bash
for i in {1..5}; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: large-training-$i
  labels:
    scheduling.x-k8s.io/pod-group: large-training-gang
spec:
  containers:
  - name: worker
    image: nginx:1.25
    resources:
      requests:
        cpu: "600m"  # 5 x 600m = 3000m total (exceeds 2 vCPU VM)
        memory: "256Mi"
    command: ["sleep", "3600"]
EOF
done
```

---

### Step 3: Observe All-or-Nothing Behavior

```bash
# Check pod status
kubectl get pods -l scheduling.x-k8s.io/pod-group=large-training-gang
```

**Expected output:**
```
NAME               READY   STATUS    RESTARTS   AGE
large-training-1   0/1     Pending   0          15s
large-training-2   0/1     Pending   0          15s
large-training-3   0/1     Pending   0          14s
large-training-4   0/1     Pending   0          14s
large-training-5   0/1     Pending   0          14s
```

✅ **ALL pods stay Pending - no partial scheduling!**

---

### Step 4: Check Why Pods Are Pending

```bash
kubectl describe pod large-training-1 | grep -A 5 Events
```

**Expected output:**
```
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  60s   default-scheduler  0/1 nodes are available: 1 Insufficient cpu
```

**This is perfect gang behavior!** The scheduler sees:
- Gang needs 5 pods minimum
- Resources insufficient for all 5
- Therefore: Schedule NONE (prevents resource waste)

---

## Exercise 3: Compare With vs Without Gang Scheduling

### Without Gang Scheduling (Regular Pods)

```bash
# Create regular pods (no gang)
for i in {1..5}; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: regular-worker-$i
spec:
  containers:
  - name: worker
    image: nginx:1.25
    resources:
      requests:
        cpu: "600m"
        memory: "256Mi"
    command: ["sleep", "3600"]
EOF
done

# Check status
kubectl get pods -l app!=training
```

**Expected behavior:**
```
NAME               READY   STATUS    RESTARTS   AGE
regular-worker-1   1/1     Running   0          10s
regular-worker-2   1/1     Running   0          10s
regular-worker-3   0/1     Pending   0          10s  ← Partial scheduling!
regular-worker-4   0/1     Pending   0          10s
regular-worker-5   0/1     Pending   0          10s
```

❌ **2-3 pods Running, rest Pending = wasted resources!**

---

## Key Observations

| Aspect | Without Gang | With Gang |
|--------|-------------|-----------|
| **Small gang (3 pods, enough resources)** | All schedule individually | All schedule together ✅ |
| **Large gang (5 pods, insufficient resources)** | Partial scheduling (2-3 Running) ❌ | All remain Pending ✅ |
| **Resource efficiency** | Wasted (partial gang can't work) | Efficient (resources available for other jobs) |
| **Deadlock prevention** | No protection | Protected ✅ |

---

## Real-World Example: PyTorch Distributed Training

Here's a realistic example for AI/ML workloads:

```bash
# Create PodGroup for PyTorch job
kubectl apply -f - <<EOF
apiVersion: scheduling.x-k8s.io/v1alpha1
kind: PodGroup
metadata:
  name: pytorch-training
spec:
  scheduleTimeoutSeconds: 600
  minMember: 4
EOF

# Create master pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-master
  labels:
    scheduling.x-k8s.io/pod-group: pytorch-training
    role: master
spec:
  containers:
  - name: pytorch
    image: python:3.9-slim
    command:
    - /bin/sh
    - -c
    - |
      echo "Master node started - Rank 0"
      echo "Waiting for 3 workers..."
      sleep 3600
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
    env:
    - name: MASTER_ADDR
      value: "pytorch-master"
    - name: WORLD_SIZE
      value: "4"
    - name: RANK
      value: "0"
EOF

# Create 3 worker pods
for i in {1..3}; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-worker-$i
  labels:
    scheduling.x-k8s.io/pod-group: pytorch-training
    role: worker
spec:
  containers:
  - name: pytorch
    image: python:3.9-slim
    command:
    - /bin/sh
    - -c
    - |
      echo "Worker $i started - Rank $i"
      sleep 3600
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
    env:
    - name: MASTER_ADDR
      value: "pytorch-master"
    - name: WORLD_SIZE
      value: "4"
    - name: RANK
      value: "$i"
EOF
done

# Watch all pods schedule together
kubectl get pods -l scheduling.x-k8s.io/pod-group=pytorch-training -w
```

---

## Cleanup

```bash
# Delete all PodGroups
kubectl delete podgroup training-gang large-training-gang pytorch-training

# Delete all gang pods
kubectl delete pod -l scheduling.x-k8s.io/pod-group=training-gang
kubectl delete pod -l scheduling.x-k8s.io/pod-group=large-training-gang
kubectl delete pod -l scheduling.x-k8s.io/pod-group=pytorch-training

# Delete regular pods (if created)
kubectl delete pod regular-worker-1 regular-worker-2 regular-worker-3 regular-worker-4 regular-worker-5

# Verify cleanup
kubectl get podgroup
kubectl get pods
```

---

## Troubleshooting

### Issue: PodGroup CRD not found

**Symptom:**
```
error: the server doesn't have a resource type "podgroup"
```

**Solution:**
```bash
# Install PodGroup CRD
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/scheduler-plugins/master/manifests/coscheduling/crd.yaml

# Verify
kubectl get crd podgroups.scheduling.x-k8s.io
```

---

### Issue: Controller pod crashing

**Symptom:**
```bash
kubectl get pods -n scheduler-plugins
# Shows Error or CrashLoopBackOff
```

**Solution:**
```bash
# Check logs
kubectl logs -n scheduler-plugins -l app=scheduler-plugins-controller

# Common issue: Missing ElasticQuota CRD (can be ignored)
# Controller will still work for PodGroups
```

---

### Issue: Pods not scheduling as gang

**Symptom:** Pods schedule individually instead of together

**Check:**
1. Label is correct: `scheduling.x-k8s.io/pod-group: <name>`
2. PodGroup exists: `kubectl get podgroup`
3. Controller is running: `kubectl get pods -n scheduler-plugins`

---

## Production Considerations

### Alpha Feature Warning

⚠️ **Gang Scheduling is Alpha in K8s 1.35**
- Not recommended for production yet
- API may change in future versions
- Test thoroughly before using with critical workloads

---

### Production Alternatives (Mature Solutions)

For production AI/ML workloads today, consider:

| Solution | Maturity | Use Case |
|----------|----------|----------|
| **Volcano Scheduler** | Production-ready | General batch workloads, AI/ML |
| **KAI Scheduler** (NVIDIA) | Production-ready | GPU workloads, elastic training |
| **Kubeflow** + scheduler-plugins | Production-ready | ML pipelines |
| **Apache YuniKorn** | Production-ready | Big data (Spark, Flink) |

---

### When to Use Gang Scheduling

✅ **Good use cases:**
- Distributed training (PyTorch, TensorFlow)
- Spark jobs with driver + executors
- MPI applications
- Any workload where partial execution is useless

❌ **Don't use for:**
- Simple stateless apps (use HPA instead)
- Independent pods that can work alone
- Workloads with flexible resource requirements

---

## Key Takeaways

✅ **Gang scheduling works with default K8s scheduler** + scheduler-plugins controller  
✅ **All-or-nothing behavior** prevents resource waste  
✅ **PodGroup API** is simpler than native Workload API  
✅ **Production-ready** alternatives exist (Volcano, KAI)  
✅ **Essential for AI/ML** distributed training  

---

## What We Learned

### Setup Challenges
1. Native `Workload` API requires feature gates that cause kubelet instability
2. Scheduler-plugins provides production-tested alternative
3. Works with default scheduler - no custom scheduler needed!

### Key Insight
The scheduler-plugins approach is actually **simpler and more reliable** than the Alpha Workload API. This is why production systems use it.

---

## Next Steps

- **Lab 3**: Structured Authentication Configuration (GA)
- **Lab 4**: Node Declared Features (Alpha)

---

**Lab Duration**: 30-45 minutes (including troubleshooting)  
**Difficulty**: Intermediate to Advanced  
**Production Readiness**: Use mature alternatives (Volcano/KAI) for production

---

**Tested on:** Kubernetes 1.35.0, Azure VM (2 vCPU, 8GB RAM)  
**Date:** December 19, 2025