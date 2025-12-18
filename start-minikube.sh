#!/bin/bash
echo "Starting Kubernetes 1.35 cluster..."

minikube start \
  --kubernetes-version=v1.35.0 \
  --cpus=4 \
  --memory=8192 \
  --disk-size=40g \
  --driver=docker \
  --feature-gates=InPlacePodVerticalScaling=true,WorkloadAwareScheduling=true,NodeDeclaredFeatures=true

echo ""
echo "Cluster started! Verifying..."
kubectl cluster-info
kubectl get nodes
kubectl version --short

echo ""
echo "Ready for labs!"
