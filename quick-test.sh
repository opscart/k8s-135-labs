#!/bin/bash
echo "Running quick verification tests..."
echo ""

echo "=== Cluster Info ==="
kubectl cluster-info
echo ""

echo "=== Node Status ==="
kubectl get nodes -o wide
echo ""

echo "=== Kubernetes Version ==="
kubectl version --short
echo ""

echo "=== Node Declared Features ==="
kubectl get node minikube -o jsonpath='{.status.declaredFeatures}' | jq '.' 2>/dev/null || echo "Feature not available yet"
echo ""

echo "Quick test complete!"
