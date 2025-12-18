# Lab 1: In-Place Pod Resource Resize (GA)

## Overview

In-Place Pod Resource Resize allows you to change CPU and memory allocations for running pods without restarting them. This feature graduated to GA (General Availability) in Kubernetes 1.35.

**Feature Status:**
- Alpha: v1.27
- Beta: v1.33
- GA: v1.35 ✅

**Use Cases:**
- Java/JVM applications with high startup costs
- Workloads with variable resource needs
- Vertical scaling without downtime

---

## Prerequisites

```bash
# Verify feature is available
kubectl api-resources | grep resize

# Check node has sufficient resources
kubectl describe node minikube | grep -A 5 "Allocated resources"
```

---

## Exercise 1: Basic CPU Resize (No Restart)

### Step 1: Create Test Pod

```bash
# Create pod with resize policy
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-resize-demo
  labels:
    app: resize-test
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    resizePolicy:
    - resourceName: cpu
      restartPolicy: NotRequired      # CPU changes without restart
    - resourceName: memory
      restartPolicy: RestartContainer  # Memory changes require restart
    resources:
      requests:
        cpu: "500m"
        memory: "256Mi"
      limits:
        cpu: "1000m"
        memory: "512Mi"
    command:
    - /bin/sh
    - -c
    - |
      echo "Pod started at: \$(date)"
      echo "Initial CPU request: 500m"
      echo "Container will run indefinitely..."
      
      # Keep container running
      while true; do
        sleep 3600
      done
EOF
```

### Step 2: Verify Pod is Running

```bash
# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/nginx-resize-demo --timeout=60s

# Check initial resources
kubectl get pod nginx-resize-demo -o yaml | grep -A 10 "resources:"

# Check container restart count (should be 0)
kubectl get pod nginx-resize-demo -o jsonpath='{.status.containerStatuses[0].restartCount}'
```

### Step 3: Resize CPU (Without Restart)

```bash
# Increase CPU to 1 core
kubectl patch pod nginx-resize-demo \
  --subresource=resize \
  --type='json' \
  -p='[
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/requests/cpu",
      "value": "1000m"
    },
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/limits/cpu",
      "value": "2000m"
    }
  ]'
```

### Step 4: Verify Resize (No Restart)

```bash
# Check resize status
kubectl get pod nginx-resize-demo -o jsonpath='{.status.resize}' && echo

# Expected: InProgress, then blank (completed)

# Verify container did NOT restart
kubectl get pod nginx-resize-demo -o jsonpath='{.status.containerStatuses[0].restartCount}'
# Should still be 0

# Check allocated resources
kubectl get pod nginx-resize-demo -o jsonpath='{.status.containerStatuses[0].allocatedResources}' | jq

# Expected output:
# {
#   "cpu": "1",
#   "memory": "256Mi"
# }

# Verify start time hasn't changed (no restart)
kubectl get pod nginx-resize-demo -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}'
```

**✅ Success Criteria:**
- Resize completed without pod restart
- restartCount = 0
- allocatedResources shows new CPU value
- startedAt timestamp unchanged

---

## Exercise 2: Memory Resize (With Restart)

### Step 1: Resize Memory

```bash
# Increase memory (requires restart)
kubectl patch pod nginx-resize-demo \
  --subresource=resize \
  --type='json' \
  -p='[
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/requests/memory",
      "value": "512Mi"
    },
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/limits/memory",
      "value": "1Gi"
    }
  ]'
```

### Step 2: Verify Container Restarted

```bash
# Check restart count (should now be 1)
kubectl get pod nginx-resize-demo -o jsonpath='{.status.containerStatuses[0].restartCount}'

# Check new startedAt time (will be recent)
kubectl get pod nginx-resize-demo -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}'

# Verify new memory allocation
kubectl get pod nginx-resize-demo -o jsonpath='{.status.containerStatuses[0].allocatedResources}' | jq
```

**✅ Success Criteria:**
- restartCount = 1
- New startedAt timestamp
- Memory updated to 512Mi

---

## Exercise 3: Resize Status Monitoring

### Create a Pod with Insufficient Resources

```bash
# Create pod on a constrained node
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: resize-status-test
spec:
  containers:
  - name: app
    image: nginx:1.25
    resizePolicy:
    - resourceName: cpu
      restartPolicy: NotRequired
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "200m"
        memory: "256Mi"
EOF

# Wait for pod to start
kubectl wait --for=condition=Ready pod/resize-status-test --timeout=60s

# Try to resize beyond node capacity
kubectl patch pod resize-status-test \
  --subresource=resize \
  --type='json' \
  -p='[
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/requests/cpu",
      "value": "100"
    }
  ]'

# Check resize status
kubectl get pod resize-status-test -o jsonpath='{.status.resize}' && echo
# Expected: Deferred or Infeasible

# Get detailed status
kubectl get pod resize-status-test -o yaml | grep -A 20 "conditions:"
```

**Resize Status Values:**

| Status | Meaning | Action |
|--------|---------|--------|
| `Proposed` | Request acknowledged | Wait |
| `InProgress` | Kubelet applying changes | Wait |
| `Deferred` | Insufficient resources now | Will retry automatically |
| `Infeasible` | Cannot be satisfied | Reduce request or add nodes |

---

## Exercise 4: Production Simulation

Simulate a Java application with high startup overhead:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: java-app-simulator
spec:
  containers:
  - name: app
    image: openjdk:17-slim
    resizePolicy:
    - resourceName: cpu
      restartPolicy: NotRequired
    - resourceName: memory
      restartPolicy: NotRequired
    resources:
      requests:
        cpu: "2000m"      # High for startup
        memory: "2Gi"
      limits:
        cpu: "2000m"
        memory: "2Gi"
    command:
    - /bin/sh
    - -c
    - |
      echo "=== Application Startup Phase ==="
      echo "Simulating JVM warmup, class loading, cache initialization..."
      
      # Simulate high CPU startup (30 seconds)
      timeout 30s sh -c 'while true; do :; done' &
      STARTUP_PID=\$!
      
      echo "Startup PID: \$STARTUP_PID"
      sleep 30
      
      echo ""
      echo "=== Startup Complete ==="
      echo "Application now in steady-state (low CPU usage)"
      echo "Ready for CPU scale-down to 500m"
      
      # Create marker file
      touch /tmp/ready-for-resize
      
      # Steady-state mode
      while true; do
        echo "Steady-state: \$(date)"
        sleep 60
      done
EOF

# Wait for startup phase to complete (30 seconds)
echo "Waiting for startup phase..."
sleep 35

# Scale down after startup
kubectl patch pod java-app-simulator \
  --subresource=resize \
  --type='json' \
  -p='[
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/requests/cpu",
      "value": "500m"
    },
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/limits/cpu",
      "value": "500m"
    },
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/requests/memory",
      "value": "512Mi"
    },
    {
      "op": "replace",
      "path": "/spec/containers/0/resources/limits/memory",
      "value": "512Mi"
    }
  ]'

echo ""
echo "CPU scaled down from 2000m to 500m"
echo "Memory scaled down from 2Gi to 512Mi"
echo ""

# Verify no restart occurred
kubectl get pod java-app-simulator -o jsonpath='{.status.containerStatuses[0].restartCount}'
```

---

## Exercise 5: Automated Resize Script

Create a script to automatically resize pods after warmup:

```bash
cat > auto-resize.sh <<'SCRIPT'
#!/bin/bash
# Automatic resize script for pods after startup

NAMESPACE="${1:-default}"
LABEL="${2:-resize-enabled=true}"
STARTUP_DURATION=120  # 2 minutes
TARGET_CPU="500m"
TARGET_MEMORY="512Mi"

echo "Monitoring pods with label: $LABEL"

while true; do
  # Find running pods with label
  PODS=$(kubectl get pods -n $NAMESPACE -l $LABEL \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.startTime}{"\n"}{end}')
  
  while IFS= read -r line; do
    POD=$(echo $line | awk '{print $1}')
    START_TIME=$(echo $line | awk '{print $2}')
    
    if [ -z "$POD" ]; then
      continue
    fi
    
    # Calculate pod age
    START_EPOCH=$(date -d "$START_TIME" +%s)
    NOW_EPOCH=$(date +%s)
    AGE=$((NOW_EPOCH - START_EPOCH))
    
    # Check if pod is old enough and hasn't been resized
    if [ $AGE -gt $STARTUP_DURATION ]; then
      CURRENT_CPU=$(kubectl get pod $POD -n $NAMESPACE \
        -o jsonpath='{.status.containerStatuses[0].allocatedResources.cpu}')
      
      if [ "$CURRENT_CPU" != "500m" ]; then
        echo "Resizing $POD (age: ${AGE}s)"
        
        kubectl patch pod $POD -n $NAMESPACE \
          --subresource=resize \
          --type='json' \
          -p="[
            {\"op\":\"replace\",\"path\":\"/spec/containers/0/resources/requests/cpu\",\"value\":\"$TARGET_CPU\"},
            {\"op\":\"replace\",\"path\":\"/spec/containers/0/resources/requests/memory\",\"value\":\"$TARGET_MEMORY\"}
          ]" 2>&1 | grep -v "the server doesn't have a resource type"
        
        if [ $? -eq 0 ]; then
          echo "✓ $POD resized successfully"
        fi
      fi
    fi
  done <<< "$PODS"
  
  sleep 30
done
SCRIPT

chmod +x auto-resize.sh

# Test the script
# ./auto-resize.sh default resize-enabled=true
```

---

## Cleanup

```bash
# Delete all test pods
kubectl delete pod nginx-resize-demo resize-status-test java-app-simulator

# Verify cleanup
kubectl get pods
```

---

## Key Takeaways

✅ **CPU changes**: No restart required (when `restartPolicy: NotRequired`)  
✅ **Memory changes**: May require restart depending on policy  
✅ **Status monitoring**: Check `.status.resize` field  
✅ **Restart count**: Verify via `.status.containerStatuses[0].restartCount`  
✅ **Production use**: Ideal for Java apps, stateful workloads  

---

## Common Issues

### Issue 1: "the server doesn't have a resource type 'resize'"
**Solution**: Feature not enabled. Check feature gates:
```bash
kubectl get --raw /metrics | grep InPlacePod
```

### Issue 2: Resize stuck in "Deferred"
**Solution**: Node doesn't have capacity. Check node resources:
```bash
kubectl describe node minikube | grep -A 5 "Allocated resources"
```

### Issue 3: Pod restarts unexpectedly
**Solution**: Check `restartPolicy` in pod spec. CPU should be `NotRequired`.

---

## Next Steps

- **Lab 2**: Gang Scheduling for AI/ML workloads
- **Lab 3**: Structured Authentication Configuration
- **Lab 4**: Node Declared Features

---

**Lab Duration**: 15-20 minutes  
**Difficulty**: Beginner to Intermediate