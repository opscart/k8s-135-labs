# Kubernetes 1.35 Labs - Hands-On Feature Testing

[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.35-326CE5?logo=kubernetes)](https://kubernetes.io/blog/2025/12/17/kubernetes-v1-35-release/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Complete hands-on labs for testing Kubernetes 1.35 features with real examples you can run.

**Released**: December 17, 2025  
**Author**: [Shamsher Khan](https://github.com/opscart)  
**Status**: ✅ All labs tested on K8s 1.35

---

## 🚀 Quick Start

### Azure VM Setup (Recommended)

```bash
# Create Azure VM
az vm create \
  --resource-group k8s-135-lab-rg \
  --name k8s-135-lab-vm \
  --image Ubuntu2404 \
  --size Standard_D2s_v3 \
  --admin-username azureuser \
  --generate-ssh-keys

# SSH to VM
ssh azureuser@<VM-IP>

# Run setup script
curl -O https://raw.githubusercontent.com/opscart/k8s-135-labs/main/setup-k8s-135-azure.sh
chmod +x setup-k8s-135-azure.sh
./setup-k8s-135-azure.sh

# Log out and back in (for docker group)
exit && ssh azureuser@<VM-IP>

# Start Kubernetes 1.35
cd ~/k8s-135-labs
./start-minikube.sh

# Verify
./quick-test.sh
```

**Cost**: ~$1-2 for complete testing session (2-3 hours)

---

## 📚 Labs Overview

| Lab | Feature | Status | Duration | Difficulty |
|-----|---------|--------|----------|------------|
| **Lab 1** | In-Place Pod Resize | GA ✅ | 20 min | Beginner |
| **Lab 2** | Gang Scheduling | Alpha 🔬 | 30 min | Advanced |
| **Lab 3** | Structured Auth | GA ✅ | 10 min | Intermediate |
| **Lab 4** | Node Features | Alpha 🔬 | 5 min | Beginner |

### Lab 1: In-Place Pod Resource Resize (GA)

Change CPU/memory without pod restarts.

**What you'll learn:**
- Resize CPU without container restart
- Handle memory resizes (requires restart)
- Monitor resize status
- Simulate production Java app patterns

**Key takeaway**: 60-70% resource savings for variable workloads.

### Lab 2: Gang Scheduling (Alpha)

All-or-nothing scheduling for distributed workloads.

**What you'll learn:**
- Create Workload API objects
- Schedule pod groups atomically
- Handle scheduling timeouts
- Simulate PyTorch/Spark jobs

**Key takeaway**: Prevents GPU waste in AI/ML clusters.

### Lab 3: Structured Authentication (GA)

Dynamic auth configuration without API server restarts.

**What you'll learn:**
- Replace command-line flags with config files
- Configure multiple identity providers
- Hot-reload auth changes

**Key takeaway**: Better multi-tenant cluster management.

### Lab 4: Node Declared Features (Alpha)

Nodes auto-advertise capabilities to scheduler.

**What you'll learn:**
- View node-declared features
- Schedule pods based on capabilities
- Handle version skew during upgrades

**Key takeaway**: Safer mixed-version cluster upgrades.

---

## 🛠️ Repository Structure

```
k8s-135-labs/
├── AZURE-SETUP-GUIDE.md
├── LICENSE
├── README.md
├── cleanup.sh
├── lab1-in-place-resize
│   ├── auto-resize.sh
│   └── lab1-resize.md
├── lab2-gang-scheduling
│   ├── lab2-gang-scheduling.md
│   └── setup-gang-scheduling.sh
├── lab3-structured-auth
│   ├── auth-config.yaml
│   └── lab3-auth-config.md
├── lab4-node-features
│   └── lab4-node-declaration.md
├── quick-test.sh
├── setup-k8s-135-azure.sh
└── start-minikube.sh
```
---

## 🎯 Key Features in K8s 1.35

### Production-Ready (GA)
- ✅ **In-Place Pod Resize** - Resize without restarts
- ✅ **Structured Authentication** - Config file-based auth
- ✅ **PreferSameNode Traffic** - Same-node routing

### Beta (Enabled by Default)
- ⏳ **Pod Certificates** - Auto cert lifecycle
- ⏳ **OCI Image Volumes** - Mount OCI artifacts
- ⏳ **cgroup v1 Removal** - ⚠️ Breaking change

### Alpha (Experimental)
- 🔬 **Gang Scheduling** - All-or-nothing scheduling
- 🔬 **Node Declared Features** - Auto-advertised capabilities
- 🔬 **Pod-Level Resize** - Aggregate pod resources

---

## 💻 System Requirements

### Azure VM (Recommended)
- **VM Size**: Standard_D2s_v3 (2 vCPU, 8GB RAM)
- **OS**: Ubuntu 24.04 LTS
- **Disk**: 40GB Standard SSD
- **Cost**: ~$0.10/hour

### Local Testing
- **Kubernetes**: 1.35.0
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 40GB free space
- **OS**: Linux (Ubuntu 22.04+ or equivalent)

---

## 📖 Prerequisites

- Basic Kubernetes knowledge
- `kubectl` experience
- SSH access (for Azure VM)
- Azure account (optional, for Azure setup)

---

## 🔧 Detailed Setup Instructions

### Option 1: Azure VM (Recommended for Clean Setup)

See [AZURE-SETUP-GUIDE.md](AZURE-SETUP-GUIDE.md) for complete instructions.

**Summary:**
1. Create Ubuntu 24.04 VM
2. Run setup script
3. Start Kubernetes 1.35
4. Run labs
5. Delete VM when done

### Option 2: Local Minikube

```bash
# Install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start with K8s 1.35
minikube start \
  --kubernetes-version=v1.35.0 \
  --cpus=4 \
  --memory=8192 \
  --feature-gates=InPlacePodVerticalScaling=true,WorkloadAwareScheduling=true,NodeDeclaredFeatures=true
```

### Option 3: kind

```bash
kind create cluster \
  --image kindest/node:v1.35.0 \
  --name k8s-135-test
```

---

## 🧪 Running the Labs

### Clone Repository

```bash
git clone https://github.com/opscart/k8s-135-labs.git
cd k8s-135-labs
```

### Run All Labs

```bash
# Lab 1: In-Place Resize (20 min)
cd lab1-in-place-resize
kubectl apply -f java-startup-demo.yaml
# Follow instructions in README.md

# Lab 2: Gang Scheduling (30 min)
cd ../lab2-gang-scheduling
kubectl apply -f basic-workload.yaml
# Follow instructions in README.md

# Lab 3: Structured Auth (10 min)
cd ../lab3-structured-auth
# Follow instructions in README.md

# Lab 4: Node Features (5 min)
cd ../lab4-node-features
kubectl get node minikube -o jsonpath='{.status.declaredFeatures}' | jq
```

---

## 🚨 Troubleshooting

### Issue: Not enough resources


**Solution**: Increase VM size
```bash
az vm resize 
\ --resource-group k8s-135-lab-rg \
  --name k8s-135-lab-vm \
  --size Standard_D4s_v3
  ```

### Issue: Docker permission denied

**Solution**: Log out and back in after setup
```bash
exit
ssh azureuser@<VM-IP>
```

### Issue: Not enough resources

**Solution**: Increase VM size
```bash
az vm resize \
  --resource-group k8s-135-lab-rg \
  --name k8s-135-lab-vm \
  --size Standard_D4s_v3
```

### Issue: "Pod QOS Class may not change as a result of resizing"

**Symptom:**
```bash
The Pod "qos-test" is invalid: spec: Invalid value: "Guaranteed": 
Pod QOS Class may not change as a result of resizing
```

**Cause:** Attempting to resize only `requests` when the pod has Guaranteed QoS (where requests = limits).

**Example of what fails:**
```bash
# Pod with Guaranteed QoS
resources:
  requests: { cpu: "500m", memory: "256Mi" }
  limits:   { cpu: "500m", memory: "256Mi" }  # Same as requests

# Trying to resize only requests
kubectl patch pod qos-test --subresource=resize --type='json' -p='[
  {"op":"replace","path":"/spec/containers/0/resources/requests/cpu","value":"250m"}
]'
# ❌ FAILS - would change QoS from Guaranteed to Burstable
```

**Solution:** Resize both `requests` AND `limits` together to maintain QoS class:
```bash
kubectl patch pod qos-test --subresource=resize --type='json' -p='[
  {"op":"replace","path":"/spec/containers/0/resources/requests/cpu","value":"250m"},
  {"op":"replace","path":"/spec/containers/0/resources/limits/cpu","value":"250m"}
]'
# ✅ WORKS - QoS stays Guaranteed
```

**Verification:**
```bash
# Check QoS class (should still be Guaranteed)
kubectl get pod qos-test -o jsonpath='{.status.qosClass}'

# Verify no restart occurred
kubectl get pod qos-test -o jsonpath='{.status.containerStatuses[0].restartCount}'
# Should be: 0
```

**Key Takeaway:** In-place resize cannot change a pod's QoS class. For Guaranteed QoS pods (requests = limits), both values must be resized proportionally.


### Issue: Feature gate not enabled

**Solution**: Verify minikube start command includes feature gates
```bash
minikube start \
  --feature-gates=InPlacePodVerticalScaling=true,WorkloadAwareScheduling=true
```

---

## 📝 Article

Full article with detailed explanations: [MAIN-ARTICLE.md](article/MAIN-ARTICLE.md)

**Topics covered:**
- In-depth feature explanations
- Production use cases
- Real-world examples
- Adoption strategy
- Breaking changes

---

## 🤝 Contributing

Found an issue? Have improvements? Contributions welcome!

1. Fork the repository
2. Create feature branch (`git checkout -b feature/improvement`)
3. Test your changes
4. Commit (`git commit -am 'Add improvement'`)
5. Push (`git push origin feature/improvement`)
6. Open Pull Request

---

## 📜 License

MIT License - see [LICENSE](LICENSE) file

---

## 👤 Author

**Shamsher Khan**  
Senior DevOps Engineer | IEEE Senior Member

- **GitHub**: [@opscart](https://github.com/opscart)
- **LinkedIn**: [Shamsher Khan](#)

**Other Projects:**
- [kosva](https://github.com/opscart/kosva) - Kubernetes Optimization Security Validator
- [k8s-cost-optimizer](https://github.com/opscart/k8s-cost-optimizer) - Kubernetes cost optimization tool

---

## 🌟 Acknowledgments

- Kubernetes SIG-Node for in-place resize
- Kubernetes SIG-Scheduling for gang scheduling
- Kubernetes SIG-Auth for structured auth
- Palark team for detailed alpha feature analysis
- Cloudsmith for comprehensive release coverage

---

## 📚 Additional Resources

- [Official K8s 1.35 Release Notes](https://kubernetes.io/blog/2025/12/17/kubernetes-v1-35-release/)
- [KEP Tracker](https://bit.ly/k8s-enhancements)
- [In-Place Resize KEP-1287](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/1287-in-place-update-pod-resources)
- [Gang Scheduling KEP-4671](https://github.com/kubernetes/enhancements/tree/master/keps/sig-scheduling/4671-gang-scheduling)

---

## ⚠️ Disclaimer

These labs are for **educational and testing purposes only**. Alpha features are experimental and not recommended for production use.

**Production Recommendations:**
- ✅ GA features: Safe for production
- ⏳ Beta features: Test thoroughly before production
- 🔬 Alpha features: Dev/test environments only

---

## 🎉 Star if Helpful!

If you found these labs useful:
- ⭐ Star this repository
- 🐦 Share on Twitter/LinkedIn
- 📝 Write about your experience
- 🤝 Contribute improvements

---

**Last Updated**: December 17, 2025  
**K8s Version**: 1.35.0  
**Status**: ✅ All labs tested and verified
