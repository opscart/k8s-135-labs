# Azure VM Setup Guide for Kubernetes 1.35 Testing

## Quick Start (Azure CLI)

### 1. Create Resource Group
```bash
# Set variables
RESOURCE_GROUP="k8s-135-lab-rg"
LOCATION="eastus"
VM_NAME="k8s-135-lab-vm"
VM_SIZE="Standard_D2s_v3"  # 2 vCPU, 8GB RAM

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
```

### 2. Create VM
```bash
# Create Ubuntu 24.04 VM
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --image Ubuntu2404 \
  --size $VM_SIZE \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --os-disk-size-gb 40

# Open ports (if needed for testing)
az vm open-port \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --port 22 \
  --priority 1000
```

### 3. Get VM Public IP
```bash
# Get public IP
VM_IP=$(az vm show \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --show-details \
  --query publicIps \
  --output tsv)

echo "VM Public IP: $VM_IP"
```

### 4. SSH to VM
```bash
# SSH using auto-generated key
ssh azureuser@$VM_IP
```

### 5. Run Setup Script
```bash
# On the VM, download setup script
curl -O https://raw.githubusercontent.com/opscart/k8s-135-labs/main/setup-k8s-135-azure.sh

# Make it executable
chmod +x setup-k8s-135-azure.sh

# Run setup (takes 10-15 minutes)
./setup-k8s-135-azure.sh

# IMPORTANT: Log out and back in after setup completes
exit

# SSH back in
ssh azureuser@$VM_IP

# Start Kubernetes cluster
cd ~/k8s-135-labs
./start-minikube.sh

# Verify everything works
./quick-test.sh
```

---

## Alternative: Azure Portal Method

### Step 1: Create VM via Portal
1. Go to Azure Portal: https://portal.azure.com
2. Click "Create a resource" → "Ubuntu Server 24.04 LTS"
3. Configure:
   - **Resource Group**: Create new "k8s-135-lab-rg"
   - **VM Name**: k8s-135-lab-vm
   - **Region**: East US (or closest to you)
   - **Size**: Standard_D2s_v3 (2 vCPU, 8GB RAM)
   - **Authentication**: SSH public key
   - **Disk**: 40GB Standard SSD
4. Review + Create
5. Download SSH key when prompted

### Step 2: Connect
1. Get public IP from VM overview page
2. SSH: `ssh -i <downloaded-key> azureuser@<public-ip>`
3. Follow "Run Setup Script" steps above

---

## Cost Estimation

### VM Pricing (Pay-as-you-go)
| VM Size | vCPU | RAM | Cost/Hour | Cost/Day (8hrs) |
|---------|------|-----|-----------|-----------------|
| Standard_B2s | 2 | 4GB | $0.0416 | $0.33 |
| Standard_D2s_v3 | 2 | 8GB | $0.096 | $0.77 |
| Standard_D4s_v3 | 4 | 16GB | $0.192 | $1.54 |

**Recommendation**: Use **Standard_D2s_v3** for optimal performance.

**Estimated Total Cost**: $1-2 for complete testing session (2-3 hours)

---

## Cleanup After Testing

### Delete Everything
```bash
# Delete entire resource group (removes VM, disk, IP, everything)
az group delete \
  --name $RESOURCE_GROUP \
  --yes \
  --no-wait

# Verify deletion (after a few minutes)
az group list --output table
```

---

## Alternative: Use Azure Cloud Shell

If you have Azure Cloud Shell enabled, you can test some features there:

```bash
# In Azure Cloud Shell
# Install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start with docker driver
minikube start --driver=docker --kubernetes-version=v1.35.0
```

---

## Troubleshooting

### Issue: Docker permission denied
**Solution**: Log out and back in after setup
```bash
exit
ssh azureuser@$VM_IP
```

### Issue: minikube won't start
**Check Docker**:
```bash
sudo systemctl status docker
docker ps  # Should work without sudo after re-login
```

### Issue: Not enough resources
**Increase VM size**:
```bash
az vm deallocate --resource-group $RESOURCE_GROUP --name $VM_NAME
az vm resize --resource-group $RESOURCE_GROUP --name $VM_NAME --size Standard_D4s_v3
az vm start --resource-group $RESOURCE_GROUP --name $VM_NAME
```

### Issue: Kubernetes version not available
**Wait for release**: K8s 1.35.0 releases on December 17, 2025. If not available yet:
```bash
# Use 1.34 temporarily for some features
minikube start --kubernetes-version=v1.34.0
```

---

## Pre-Flight Checklist

Before starting:
- [ ] Azure subscription active
- [ ] Azure CLI installed (or use Portal)
- [ ] SSH key generated
- [ ] Budget set (recommend $5 limit)
- [ ] Kubernetes 1.35.0 released (Dec 17, 2025)

After setup:
- [ ] VM created successfully
- [ ] Can SSH to VM
- [ ] Setup script completed
- [ ] Logged out and back in
- [ ] minikube started successfully
- [ ] kubectl working
- [ ] Quick test passed

---

## Quick Reference Commands

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# View all pods
kubectl get pods --all-namespaces

# Check feature gates
kubectl get --raw /metrics | grep feature_enabled

# View node features
kubectl get node minikube -o jsonpath='{.status.declaredFeatures}' | jq

# Stop cluster (saves state)
minikube stop

# Start cluster again
minikube start

# Delete cluster
minikube delete
```

---

## Support

If you encounter issues:
1. Check `~/k8s-135-labs/setup.log` for setup errors
2. Run `./quick-test.sh` to diagnose issues
3. Check minikube logs: `minikube logs`
4. Verify Docker: `docker ps`

---

**Total Setup Time**: 15-20 minutes  
**Testing Time**: 2-3 hours  
**Total Cost**: ~$1-2 USD
