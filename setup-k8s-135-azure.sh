#!/bin/bash
#############################################################################
# Kubernetes 1.35 Lab Setup Script for Azure VM
# Author: Shamsher Khan
# Date: December 17, 2025
# Purpose: Complete setup for testing K8s 1.35 features on fresh Azure VM
#############################################################################

set -e  # Exit on any error

echo "=========================================="
echo "Kubernetes 1.35 Lab Setup"
echo "=========================================="
echo ""

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    print_error "Please do not run as root. Run as regular user with sudo access."
    exit 1
fi

#############################################################################
# 1. System Update
#############################################################################
print_status "Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

#############################################################################
# 2. Install Dependencies
#############################################################################
print_status "Installing dependencies..."
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    jq \
    git \
    vim

#############################################################################
# 3. Install Docker
#############################################################################
print_status "Installing Docker..."

# Remove old versions if any
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update -qq
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
sudo usermod -aG docker $USER

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

print_status "Docker installed: $(docker --version)"

#############################################################################
# 4. Install kubectl
#############################################################################
print_status "Installing kubectl..."

# Download latest stable kubectl
curl -LO "https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl"

# Validate the binary (optional)
curl -LO "https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

# Install kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Clean up
rm kubectl kubectl.sha256

print_status "kubectl installed: $(kubectl version --client --short)"

#############################################################################
# 5. Install minikube
#############################################################################
print_status "Installing minikube..."

curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

print_status "minikube installed: $(minikube version --short)"

#############################################################################
# 6. Configure System for Kubernetes
#############################################################################
print_status "Configuring system for Kubernetes..."

# Disable swap (required for Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl params required by Kubernetes
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

print_status "System configured for Kubernetes"

#############################################################################
# 7. Verify cgroup v2
#############################################################################
print_status "Checking cgroup version..."

CGROUP_VERSION=$(stat -fc %T /sys/fs/cgroup/)

if [ "$CGROUP_VERSION" == "cgroup2fs" ]; then
    print_status "cgroup v2 detected: Ready for Kubernetes 1.35"
else
    print_warning "cgroup v1 detected: This may cause issues with K8s 1.35"
    print_warning "Consider upgrading to a newer OS version"
fi

#############################################################################
# 8. Create Lab Directory Structure
#############################################################################
print_status "Creating lab directory structure..."

mkdir -p ~/k8s-135-labs/{lab1-in-place-resize,lab2-gang-scheduling,lab3-structured-auth,lab4-node-features,lab5-misc}

cat > ~/k8s-135-labs/README.md <<'EOF'
# Kubernetes 1.35 Labs

This directory contains hands-on labs for testing Kubernetes 1.35 features.

## Labs:
- lab1-in-place-resize: In-Place Pod Resource Resize (GA)
- lab2-gang-scheduling: Gang Scheduling (Alpha)
- lab3-structured-auth: Structured Authentication Config (GA)
- lab4-node-features: Node Declared Features (Alpha)
- lab5-misc: Additional features and experiments

## Getting Started:
1. Start minikube: `./start-minikube.sh`
2. Run individual labs in each directory
3. Clean up: `./cleanup.sh`
EOF

#############################################################################
# 9. Create Minikube Start Script
#############################################################################
print_status "Creating minikube start script..."

cat > ~/k8s-135-labs/start-minikube.sh <<'EOF'
#!/bin/bash
# Start Kubernetes 1.35 cluster with all necessary feature gates

echo "Starting Kubernetes 1.35 cluster..."

minikube start \
  --kubernetes-version=v1.35.0 \
  --cpus=4 \
  --memory=8192 \
  --disk-size=40g \
  --driver=docker \
  --feature-gates=InPlacePodVerticalScaling=true,WorkloadAwareScheduling=true,NodeDeclaredFeatures=true,InPlacePodLevelResourcesVerticalScaling=true \
  --extra-config=apiserver.feature-gates=InPlacePodVerticalScaling=true,WorkloadAwareScheduling=true,NodeDeclaredFeatures=true \
  --extra-config=controller-manager.feature-gates=InPlacePodVerticalScaling=true,WorkloadAwareScheduling=true \
  --extra-config=scheduler.feature-gates=InPlacePodVerticalScaling=true,WorkloadAwareScheduling=true,NodeDeclaredFeatures=true

echo ""
echo "Cluster started! Verifying..."
kubectl cluster-info
kubectl get nodes
kubectl version

echo ""
echo "Feature gates enabled:"
echo "  - InPlacePodVerticalScaling (GA)"
echo "  - WorkloadAwareScheduling (Alpha - Gang Scheduling)"
echo "  - NodeDeclaredFeatures (Alpha)"
echo "  - InPlacePodLevelResourcesVerticalScaling (Alpha)"
echo ""
echo "Ready for labs!"
EOF

chmod +x ~/k8s-135-labs/start-minikube.sh

#############################################################################
# 10. Create Cleanup Script
#############################################################################
print_status "Creating cleanup script..."

cat > ~/k8s-135-labs/cleanup.sh <<'EOF'
#!/bin/bash
# Cleanup script for Kubernetes 1.35 labs

echo "Cleaning up Kubernetes 1.35 lab environment..."

# Stop and delete minikube cluster
minikube stop
minikube delete --all --purge

echo "Cleanup complete!"
echo ""
echo "To completely remove all installed software:"
echo "  sudo apt-get remove -y docker-ce docker-ce-cli containerd.io kubectl"
echo "  sudo rm -rf /usr/local/bin/minikube"
echo "  sudo rm -rf ~/.minikube"
EOF

chmod +x ~/k8s-135-labs/cleanup.sh

#############################################################################
# 11. Create Quick Test Script
#############################################################################
print_status "Creating quick test script..."

cat > ~/k8s-135-labs/quick-test.sh <<'EOF'
#!/bin/bash
# Quick test to verify Kubernetes 1.35 is working

echo "Running quick verification tests..."
echo ""

# Test 1: Cluster info
echo "=== Test 1: Cluster Info ==="
kubectl cluster-info
echo ""

# Test 2: Node status
echo "=== Test 2: Node Status ==="
kubectl get nodes -o wide
echo ""

# Test 3: Check Kubernetes version
echo "=== Test 3: Kubernetes Version ==="
kubectl version --short
echo ""

# Test 4: Check Node Declared Features (if available)
echo "=== Test 4: Node Declared Features ==="
kubectl get node minikube -o jsonpath='{.status.declaredFeatures}' | jq '.' || echo "Feature not available or not populated yet"
echo ""

# Test 5: Check feature gates
echo "=== Test 5: Feature Gates Status ==="
kubectl get --raw /metrics | grep feature_enabled | grep -E "(InPlacePod|Workload|NodeDeclared)" || echo "Metrics not available"
echo ""

echo "Quick test complete!"
EOF

chmod +x ~/k8s-135-labs/quick-test.sh

#############################################################################
# Final Instructions
#############################################################################
echo ""
echo "=========================================="
print_status "Setup Complete!"
echo "=========================================="
echo ""
print_warning "IMPORTANT: You must log out and log back in for docker group to take effect!"
echo ""
echo "After re-login, run:"
echo "  cd ~/k8s-135-labs"
echo "  ./start-minikube.sh"
echo ""
echo "Then run labs in each directory."
echo ""
echo "To cleanup everything:"
echo "  ./cleanup.sh"
echo ""
print_status "Lab directory: ~/k8s-135-labs"
print_status "Estimated setup time: 10-15 minutes"
echo ""

# Create a file to indicate setup is complete
touch ~/.k8s-135-setup-complete

echo "You can now log out and back in, then start testing!"