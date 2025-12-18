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