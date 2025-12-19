#!/bin/bash

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Cleanup function
cleanup() {
    echo "=========================================="
    echo "  Cleaning Up Gang Scheduling"
    echo "=========================================="
    echo ""
    
    print_status "Deleting all PodGroups..."
    kubectl delete podgroup --all --all-namespaces 2>/dev/null || true
    
    print_status "Deleting all gang pods..."
    kubectl delete pod -l scheduling.x-k8s.io/pod-group 2>/dev/null || true
    
    print_status "Removing scheduler-plugins namespace..."
    kubectl delete namespace scheduler-plugins 2>/dev/null || true
    
    print_status "Removing PodGroup CRD..."
    kubectl delete crd podgroups.scheduling.x-k8s.io 2>/dev/null || true
    
    print_status "Removing RBAC resources..."
    kubectl delete clusterrole system:kube-scheduler:plugins 2>/dev/null || true
    kubectl delete clusterrolebinding system:kube-scheduler:plugins 2>/dev/null || true
    kubectl delete clusterrole scheduler-plugins-controller 2>/dev/null || true
    kubectl delete clusterrolebinding scheduler-plugins-controller 2>/dev/null || true
    
    echo ""
    echo "=========================================="
    print_status "Cleanup Complete!"
    echo "=========================================="
    echo ""
}

# Check for cleanup flag
if [ "$1" == "cleanup" ] || [ "$1" == "--cleanup" ] || [ "$1" == "clean" ]; then
    cleanup
    exit 0
fi

echo "=========================================="
echo "  Gang Scheduling Setup Script"
echo "=========================================="
echo ""
echo "Usage:"
echo "  ./setup-gang-scheduling.sh           # Install"
echo "  ./setup-gang-scheduling.sh cleanup   # Remove everything"
echo ""

# Step 1: Install scheduler-plugins controller
print_status "Installing scheduler-plugins controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/scheduler-plugins/master/manifests/install/all-in-one.yaml

sleep 5

# Step 2: Wait for controller to be ready
print_status "Waiting for controller deployment..."
kubectl wait --for=condition=available deployment/scheduler-plugins-controller -n scheduler-plugins --timeout=60s 2>/dev/null

if [ $? -ne 0 ]; then
    print_warning "Deployment not fully ready, checking pod status..."
    POD_STATUS=$(kubectl get pods -n scheduler-plugins -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    
    if [ "$POD_STATUS" == "Running" ]; then
        print_status "Controller pod is running"
    else
        print_warning "Controller status: $POD_STATUS"
        echo ""
        kubectl get pods -n scheduler-plugins
        echo ""
        print_warning "Note: Gang scheduling may still work even if controller has issues"
    fi
fi

# Step 3: Install PodGroup CRD
print_status "Installing PodGroup CRD..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/scheduler-plugins/master/manifests/coscheduling/crd.yaml

sleep 2

# Step 4: Verify CRD is installed
print_status "Verifying PodGroup CRD..."
kubectl get crd podgroups.scheduling.x-k8s.io >/dev/null 2>&1

if [ $? -eq 0 ]; then
    print_status "PodGroup CRD installed successfully!"
else
    print_error "PodGroup CRD installation failed"
    exit 1
fi

# Step 5: Verify controller is running
echo ""
print_status "Checking controller status..."
kubectl get pods -n scheduler-plugins

echo ""
echo "=========================================="
print_status "Setup Complete!"
echo "=========================================="
echo ""
echo "Gang scheduling is now ready to use!"
echo ""
echo "Next steps:"
echo "  1. Create a PodGroup with minMember"
echo "  2. Create pods with label: scheduling.x-k8s.io/pod-group=<name>"
echo "  3. Watch pods schedule together as a gang"
echo ""
echo "Example:"
echo "  kubectl apply -f - <<EOF"
echo "  apiVersion: scheduling.x-k8s.io/v1alpha1"
echo "  kind: PodGroup"
echo "  metadata:"
echo "    name: my-gang"
echo "  spec:"
echo "    minMember: 3"
echo "  EOF"
echo ""