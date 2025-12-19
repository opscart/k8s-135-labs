#!/bin/bash
# Automatic resize script for pods after startup

echo "=========================================="
echo "   Kubernetes In-Place Resize Demo"
echo "=========================================="
echo ""

NAMESPACE="default"
LABEL="resize-enabled=true"
WAIT_TIME=20 #sec

echo "Waiting for pod with label: $LABEL..."
while true; do
  POD=$(kubectl get pods -n $NAMESPACE -l $LABEL -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD" ]; then
    break
  fi
  sleep 2
done

echo "Found pod: $POD"
echo ""

INITIAL_CPU=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.requests.cpu}')
INITIAL_MEM=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.requests.memory}')

echo "Initial Resources:"
echo "  CPU:    $INITIAL_CPU"
echo "  Memory: $INITIAL_MEM"
echo ""
echo "Target Resources:"
echo "  CPU:    500m"
echo "  Memory: 1Gi"
echo ""
echo "Waiting ${WAIT_TIME} seconds..."
echo ""

START=$(date +%s)
while true; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  
  if [ $ELAPSED -ge $WAIT_TIME ]; then
    echo ""
    echo "=========================================="
    echo "Scaling Up!"
    echo "=========================================="
    
    kubectl patch pod $POD -n $NAMESPACE --subresource=resize --type='json' \
      -p='[
        {"op":"replace","path":"/spec/containers/0/resources/requests/cpu","value":"500m"},
        {"op":"replace","path":"/spec/containers/0/resources/limits/cpu","value":"500m"},
        {"op":"replace","path":"/spec/containers/0/resources/requests/memory","value":"1Gi"},
        {"op":"replace","path":"/spec/containers/0/resources/limits/memory","value":"1Gi"}
      ]'
    
    sleep 3
    
    FINAL_CPU=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].allocatedResources.cpu}')
    FINAL_MEM=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].allocatedResources.memory}')
    RESTART_COUNT=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].restartCount}')
    
    echo ""
    echo "Resize Complete!"
    echo ""
    echo "CPU:    $INITIAL_CPU to $FINAL_CPU"
    echo "Memory: $INITIAL_MEM to $FINAL_MEM"
    echo "Restart Count: $RESTART_COUNT"
    echo ""
    
    exit 0
  fi
  
  echo "Elapsed: ${ELAPSED}s / ${WAIT_TIME}s"
  sleep 2
done