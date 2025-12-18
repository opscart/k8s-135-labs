#!/bin/bash
echo "Cleaning up Kubernetes 1.35 lab environment..."

minikube stop
minikube delete --all --purge

echo "Cleanup complete!"
