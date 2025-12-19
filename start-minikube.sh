#!/bin/bash
echo "Starting Kubernetes 1.35 cluster..."

minikube start \
  --kubernetes-version=v1.35.0 \
  --cpus=2 \
  --memory=4096 \
  --driver=docker \
  --container-runtime=containerd \
  --extra-config=kubelet.cgroup-driver=systemd

echo ""
echo "Cluster started! Verifying..."
kubectl cluster-info
kubectl get nodes
kubectl version --short

echo ""
echo "Ready for labs!"
