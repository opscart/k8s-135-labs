# Lab 2: Gang Scheduling for AI/ML Workloads (Alpha)

## Overview

Gang Scheduling ensures that a group of pods (a "gang") are scheduled together as a unit - all pods in the group start at the same time, or none of them start. This prevents resource deadlocks in distributed workloads.

**Feature Status:**
- Alpha: v1.35 ✅
- Beta: TBD (likely v1.36)
- GA: TBD

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
├─ Resources wasted
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
└─ Once capacity available → all 8 pods scheduled together
```

---

## Prerequisites

```bash
# Verify feature gate is enabled
kubectl get --raw /metrics | grep WorkloadAwareScheduling || echo "Feature gate not found"

# Check if Workload API is available
kubectl api-resources | grep workload
```

---

## Exercise 1: Basic Gang Scheduling

### Step 1: Create Workload with MinCount

```bash
kubectl apply -f - <<EOF
apiVersion: scheduling.k8s.io/v1alpha1
kind: Workload
metadata:
  name: training-job-basic
  namespace: default
spec:
  podGroups:
  - name: "training-gang"
    policy:
      gang:
        minCount: 4              # Minimum 4 pods required
        timeout: 300             # 5 minutes timeout
EOF

# Verify workload created
kubectl get workload training-job-basic -o yaml
```

### Step 2: Create Master Pod

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: training-master
  labels:
    app: training
    role: master
spec:
  workloadRef:
    name: training-job-basic
    podGroup: training-gang
  containers:
  - name: master
    image: nginx:1.25
    command:
    - /bin/sh
    - -c
    - |
      echo "Master pod started: \$(date)"
      echo "Waiting for worker pods..."
      
      # Simulate waiting for workers
      REQUIRED_WORKERS=3
      
      while true; do
        # In real scenario, master would check for worker connections
        echo "Checking for \$REQUIRED_WORKERS workers..."
        sleep 10
        
        # Simulate workers being ready
        READY_WORKERS=\$(( RANDOM % 4 ))
        if [ \$READY_WORKERS -ge \$REQUIRED_WORKERS ]; then
          echo "All workers ready! Starting training..."
          break
        fi
      done
      
      echo "Training in progress..."
      sleep 3600
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
EOF
```

### Step 3: Create Worker Pods

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: training-worker-1
  labels:
    app: training
    role: worker
spec:
  workloadRef:
    name: training-job-basic
    podGroup: training-gang
  containers:
  - name: worker
    image: nginx:1.25
    command:
    - /bin/sh
    - -c
    - |
      echo "Worker 1 started: \$(date)"
      echo "Waiting for master..."
      sleep 3600
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
---
apiVersion: v1
kind: Pod
metadata:
  name: training-worker-2
  labels:
    app: training
    role: worker
spec:
  workloadRef:
    name: training-job-basic
    podGroup: training-gang
  containers:
  - name: worker
    image: nginx:1.25
    command:
    - /bin/sh
    - -c
    - |
      echo "Worker 2 started: \$(date)"
      sleep 3600
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
---
apiVersion: v1
kind: Pod
metadata:
  name: training-worker-3
  labels:
    app: training
    role: worker
spec:
  workloadRef:
    name: training-job-basic
    podGroup: training-gang
  containers:
  - name: worker
    image: nginx:1.25
    command:
    - /bin/sh
    - -c
    - |
      echo "Worker 3 started: \$(date)"
      sleep 3600
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
EOF
```

### Step 4: Monitor Gang Scheduling

```bash
# Watch pods - they should all schedule together or remain pending
watch -n 2 'kubectl get pods -l app=training'

# Check workload status
kubectl get workload training-job-basic -o yaml | grep -A 20 "status:"

# Expected conditions:
# - GangScheduled: True (when all pods scheduled)
# - PodGroupReady: True
```

**✅ Success Criteria:**
- All 4 pods go from Pending → Running simultaneously
- Workload status shows `GangScheduled: True`
- No partial scheduling (3 running, 1 pending)

---

## Exercise 2: Test Gang Scheduling Failure

Simulate insufficient cluster capacity:

### Step 1: Create Large Gang

```bash
kubectl apply -f - <<EOF
apiVersion: scheduling.k8s.io/v1alpha1
kind: Workload
metadata:
  name: large-training-job
spec:
  podGroups:
  - name: "large-gang"
    policy:
      gang:
        minCount: 10            # Requires 10 pods
        timeout: 120            # 2 minute timeout
EOF

# Create 10 pods with high resource requests
for i in {0..9}; do
kubectl apply -f - <<INNER_EOF
apiVersion: v1
kind: Pod
metadata:
  name: large-worker-$i
  labels:
    app: large-training
spec:
  workloadRef:
    name: large-training-job
    podGroup: large-gang
  containers:
  - name: worker
    image: nginx:1.25
    resources:
      requests:
        cpu: "2000m"          # 2 cores each = 20 cores total
        memory: "2Gi"
INNER_EOF
done
```

### Step 2: Observe Timeout Behavior

```bash
# Watch pods remain in Pending
kubectl get pods -l app=large-training -w

# After 2 minutes, check workload status
sleep 130

kubectl get workload large-training-job -o yaml | grep -A 10 "conditions:"

# Expected: SchedulingTimeout condition
```

**✅ Expected Behavior:**
- All pods remain Pending
- After timeout → pods may be deleted or requeued
- No partial scheduling occurs
- Resources not wasted

---

## Exercise 3: PyTorch Distributed Training Simulation

Simulate a realistic PyTorch training job:

```bash
kubectl apply -f - <<EOF
apiVersion: scheduling.k8s.io/v1alpha1
kind: Workload
metadata:
  name: pytorch-training
spec:
  podGroups:
  - name: "pytorch-gang"
    policy:
      gang:
        minCount: 4            # 1 master + 3 workers
        timeout: 600           # 10 minutes
---
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-master
  labels:
    app: pytorch
    role: master
spec:
  workloadRef:
    name: pytorch-training
    podGroup: pytorch-gang
  containers:
  - name: pytorch
    image: python:3.9-slim
    command:
    - /bin/sh
    - -c
    - |
      echo "======================================"
      echo "PyTorch Distributed Training Master"
      echo "======================================"
      echo ""
      echo "Master node started: \$(date)"
      echo "Rank: 0"
      echo "World size: 4"
      echo ""
      
      # Simulate distributed training setup
      echo "Initializing process group..."
      echo "Backend: nccl"
      echo "Init method: tcp://pytorch-master:29500"
      
      sleep 5
      echo ""
      echo "✓ Process group initialized"
      echo "✓ Workers connected"
      echo ""
      
      # Simulate training epochs
      for epoch in {1..5}; do
        echo "Epoch \$epoch/5"
        echo "  - Forward pass..."
        sleep 2
        echo "  - Backward pass..."
        sleep 2
        echo "  - Gradient sync across workers..."
        sleep 1
        echo "  - Optimizer step..."
        sleep 1
        echo "  ✓ Epoch \$epoch complete"
        echo ""
      done
      
      echo "Training complete!"
      sleep 3600
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
    env:
    - name: MASTER_ADDR
      value: "pytorch-master"
    - name: MASTER_PORT
      value: "29500"
    - name: WORLD_SIZE
      value: "4"
    - name: RANK
      value: "0"
---
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-worker-1
  labels:
    app: pytorch
    role: worker
spec:
  workloadRef:
    name: pytorch-training
    podGroup: pytorch-gang
  containers:
  - name: pytorch
    image: python:3.9-slim
    command:
    - /bin/sh
    - -c
    - |
      echo "Worker 1 started - Rank 1"
      echo "Connecting to master: pytorch-master:29500"
      
      # Simulate worker waiting for master
      sleep 10
      
      echo "✓ Connected to master"
      echo "Participating in training..."
      
      sleep 3600
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
    env:
    - name: MASTER_ADDR
      value: "pytorch-master"
    - name: MASTER_PORT
      value: "29500"
    - name: WORLD_SIZE
      value: "4"
    - name: RANK
      value: "1"
---
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-worker-2
  labels:
    app: pytorch
    role: worker
spec:
  workloadRef:
    name: pytorch-training
    podGroup: pytorch-gang
  containers:
  - name: pytorch
    image: python:3.9-slim
    command:
    - /bin/sh
    - -c
    - |
      echo "Worker 2 started - Rank 2"
      sleep 10
      echo "✓ Connected to master"
      sleep 3600
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
    env:
    - name: MASTER_ADDR
      value: "pytorch-master"
    - name: RANK
      value: "2"
---
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-worker-3
  labels:
    app: pytorch
    role: worker
spec:
  workloadRef:
    name: pytorch-training
    podGroup: pytorch-gang
  containers:
  - name: pytorch
    image: python:3.9-slim
    command:
    - /bin/sh
    - -c
    - |
      echo "Worker 3 started - Rank 3"
      sleep 10
      echo "✓ Connected to master"
      sleep 3600
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
    env:
    - name: MASTER_ADDR
      value: "pytorch-master"
    - name: RANK
      value: "3"
EOF

# Watch training logs
sleep 20
kubectl logs pytorch-master
```

**✅ Success Criteria:**
- All 4 pods start together
- Master logs show "Process group initialized"
- Training epochs progress
- No worker starts before master ready

---

## Exercise 4: Apache Spark Job with Gang Scheduling

```bash
kubectl apply -f - <<EOF
apiVersion: scheduling.k8s.io/v1alpha1
kind: Workload
metadata:
  name: spark-job
spec:
  podGroups:
  - name: "spark-gang"
    policy:
      gang:
        minCount: 5            # 1 driver + 4 executors
        timeout: 300
---
apiVersion: v1
kind: Pod
metadata:
  name: spark-driver
  labels:
    app: spark
    role: driver
spec:
  workloadRef:
    name: spark-job
    podGroup: spark-gang
  containers:
  - name: spark
    image: bitnami/spark:3.5
    command:
    - /bin/bash
    - -c
    - |
      echo "Spark Driver started"
      echo "Executors required: 4"
      echo "Waiting for executors to register..."
      
      # Simulate Spark driver waiting for executors
      sleep 15
      
      echo "All executors registered!"
      echo "Starting Spark job..."
      
      # Simulate job stages
      for stage in {1..3}; do
        echo "Stage \$stage: Processing..."
        sleep 10
      done
      
      echo "Spark job completed successfully!"
      sleep 3600
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
EOF

# Create executors using StatefulSet for stable identity
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: spark-executor
spec:
  serviceName: spark-executor
  replicas: 4
  selector:
    matchLabels:
      app: spark
      role: executor
  template:
    metadata:
      labels:
        app: spark
        role: executor
    spec:
      workloadRef:
        name: spark-job
        podGroup: spark-gang
      containers:
      - name: spark
        image: bitnami/spark:3.5
        command:
        - /bin/bash
        - -c
        - |
          echo "Executor \$(hostname) started"
          echo "Registering with driver..."
          sleep 5
          echo "✓ Registered"
          echo "Ready to process tasks"
          sleep 3600
        resources:
          requests:
            cpu: "1000m"
            memory: "2Gi"
EOF

# Monitor Spark job
sleep 20
kubectl logs spark-driver
```

---

## Monitoring and Debugging

### Check Workload Status

```bash
# List all workloads
kubectl get workloads

# Detailed workload info
kubectl describe workload pytorch-training

# Get workload YAML with status
kubectl get workload pytorch-training -o yaml
```

### Monitor Pod Scheduling

```bash
# Watch all pods in gang
kubectl get pods -l app=pytorch -w

# Check scheduler events
kubectl get events --sort-by='.lastTimestamp' | grep -i workload

# Check if pods are waiting for gang to be satisfied
kubectl describe pod pytorch-worker-1 | grep -A 5 "Events:"
```

### Debug Gang Scheduling Issues

```bash
# Check if feature gate is enabled
kubectl get --raw /metrics | grep WorkloadAwareScheduling

# Check scheduler logs (if accessible)
kubectl logs -n kube-system kube-scheduler-minikube | grep -i workload

# Verify workloadRef is set correctly
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.workloadRef}{"\n"}{end}'
```

---

## Cleanup

```bash
# Delete PyTorch training
kubectl delete workload pytorch-training
kubectl delete pod -l app=pytorch

# Delete Spark job
kubectl delete workload spark-job
kubectl delete pod spark-driver
kubectl delete statefulset spark-executor

# Delete basic training
kubectl delete workload training-job-basic large-training-job
kubectl delete pod -l app=training
kubectl delete pod -l app=large-training

# Verify cleanup
kubectl get workloads
kubectl get pods
```

---

## Key Takeaways

✅ **All-or-nothing**: Entire gang schedules together or not at all  
✅ **Prevents deadlock**: No partial scheduling that blocks resources  
✅ **Timeout support**: Automatic cleanup after timeout expires  
✅ **AI/ML critical**: Essential for distributed training workloads  
✅ **Alpha status**: Use in dev/test, not production yet  

---

## Common Issues

### Issue 1: Workload API not found
**Solution**: Feature gate not enabled. Check kube-scheduler config:
```bash
kubectl get pod -n kube-system kube-scheduler-minikube -o yaml | grep feature-gates
```

### Issue 2: Pods schedule individually (not as gang)
**Solution**: Verify `workloadRef` is set in pod spec:
```bash
kubectl get pod pytorch-master -o yaml | grep workloadRef -A 3
```

### Issue 3: Timeout too short
**Solution**: Increase timeout in Workload spec:
```yaml
policy:
  gang:
    minCount: 4
    timeout: 600  # 10 minutes instead of 5
```

---

## Production Considerations

⚠️ **Alpha Feature**: Not recommended for production yet  
⚠️ **Requires testing**: Test thoroughly before AI/ML workloads  
⚠️ **Alternative**: Use scheduler-plugins for production (mature)  
✅ **Future**: Will become essential for AI/ML in K8s  

---

## Next Steps

- **Lab 3**: Structured Authentication Configuration
- **Lab 4**: Node Declared Features
- **Lab 5**: Additional K8s 1.35 features

---

**Lab Duration**: 20-30 minutes  
**Difficulty**: Intermediate to Advanced