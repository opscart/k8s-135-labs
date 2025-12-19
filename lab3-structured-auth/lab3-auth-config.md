# Lab 3: Structured Authentication Configuration (GA)

## Overview

Structured Authentication Configuration is a **GA feature** in Kubernetes 1.35 that moves authentication configuration from command-line flags to structured YAML files. This enables better validation, centralized configuration, and potentially dynamic updates.

**Feature Status:**
- GA in Kubernetes 1.35 ✅
- API: `apiserver.config.k8s.io/v1beta1`

---

## Why This Matters

### Traditional Approach (Command-Line Flags)

```bash
kube-apiserver \
  --oidc-issuer-url=https://accounts.google.com \
  --oidc-client-id=my-client-id \
  --oidc-username-claim=email \
  --oidc-groups-claim=groups
```

**Problems:**
- ❌ Long, complex command lines
- ❌ Difficult to validate before restart
- ❌ Hard to manage multiple auth providers
- ❌ No schema validation

---

### New Approach (Structured Configuration)

```yaml
apiVersion: apiserver.config.k8s.io/v1beta1
kind: AuthenticationConfiguration
jwt:
  - issuer:
      url: https://accounts.google.com
      audiences:
        - my-kubernetes-cluster
    claimMappings:
      username:
        claim: email
        prefix: "google:"
      groups:
        claim: groups
        prefix: "google:"
```

**Benefits:**
- ✅ Clear, structured format
- ✅ Schema validation
- ✅ Easy to manage multiple providers
- ✅ Better error messages
- ✅ Version controlled configuration

---

## ⚠️ Important Warning

**This lab modifies the Kubernetes API server configuration**, which can break your cluster if done incorrectly. 

**Risk Level:** Medium

**Mitigation:**
- We're using minikube (easy to reset)
- We create backups before modifying
- Worst case: `minikube delete && minikube start`

**Not recommended for:**
- Production clusters (without proper testing)
- Managed Kubernetes services (may be restricted)

---

## Prerequisites

```bash
# Verify minikube is running
minikube status

# Verify K8s version
kubectl version --short
```

---

## Exercise 1: Configure JWT Authentication

### Step 1: Create Authentication Configuration

```bash
# Create auth config file
cat > /tmp/auth-config.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1beta1
kind: AuthenticationConfiguration
jwt:
  - issuer:
      url: https://token.actions.githubusercontent.com
      audiences:
        - kubernetes-test
    claimMappings:
      username:
        claim: sub
        prefix: "github:"
EOF

# Verify the file
cat /tmp/auth-config.yaml
```

**What this configures:**
- **Issuer:** GitHub Actions token endpoint
- **Audience:** `kubernetes-test` (cluster identifier)
- **Username mapping:** Extract from `sub` claim, prefix with `github:`

---

### Step 2: Copy Config to Minikube

```bash
# Copy config file into minikube VM
minikube cp /tmp/auth-config.yaml /tmp/auth-config.yaml

# Verify it's there
minikube ssh "cat /tmp/auth-config.yaml"
```

---

### Step 3: Backup Current API Server Config

```bash
# SSH into minikube
minikube ssh

# Create backup
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.backup

# Verify backup
ls -la /tmp/kube-apiserver.yaml.backup

# Exit minikube
exit
```

**This backup is critical!** We'll use it to rollback if needed.

---

### Step 4: Modify API Server Configuration

**Method 1: Using sed (Automated)**

```bash
minikube ssh

# Add authentication-config flag
sudo sed -i '/^    - kube-apiserver$/a\    - --authentication-config=/tmp/auth-config.yaml' \
  /etc/kubernetes/manifests/kube-apiserver.yaml

# Verify the change
sudo grep authentication-config /etc/kubernetes/manifests/kube-apiserver.yaml

exit
```

---

**Method 2: Manual Edit (Recommended for Understanding)**

```bash
minikube ssh

# Edit the manifest
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

**Add this line** under the `command:` section (after `- kube-apiserver`):

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --authentication-config=/tmp/auth-config.yaml  # ADD THIS LINE
    - --advertise-address=192.168.49.2
    # ... rest of flags
```

**Save and exit** (`:wq` in vi)

```bash
exit
```

---

### Step 5: Watch API Server Restart

The API server will automatically restart when the manifest changes:

```bash
# Watch API server pod
kubectl get pods -n kube-system -w | grep kube-apiserver
```

**Expected behavior:**
```
kube-apiserver-minikube   0/1   Pending   0   0s
kube-apiserver-minikube   0/1   Running   0   5s
kube-apiserver-minikube   1/1   Running   0   58s  ← SUCCESS!
```

Press `Ctrl+C` when it shows `1/1 Running`.

---

### Step 6: Verify Configuration is Active

```bash
# Check if API server is healthy
kubectl get nodes

# Verify authentication-config flag is present
minikube ssh "sudo ps aux | grep authentication-config"
```

**Expected output:**
```
root  7328  ... kube-apiserver ... --authentication-config=/tmp/auth-config.yaml ...
```

✅ **The flag is present in the running process!**

---

### Step 7: Check API Server Logs

```bash
# Check logs for authentication configuration
kubectl logs -n kube-system kube-apiserver-minikube | grep -i authentication
```

**Expected output:**
```
Adding GroupVersion authentication.k8s.io v1 to ResourceManager
```

---

### Step 8: Verify Authentication API

```bash
# Check authentication API is available
kubectl api-versions | grep authentication
```

**Expected output:**
```
authentication.k8s.io/v1
```

---

## Exercise 2: Add Multiple Authentication Providers

Let's configure multiple JWT issuers (e.g., GitHub + Google):

### Step 1: Create Multi-Provider Config

```bash
cat > /tmp/auth-config-multi.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1beta1
kind: AuthenticationConfiguration
jwt:
  - issuer:
      url: https://token.actions.githubusercontent.com
      audiences:
        - kubernetes-test
    claimMappings:
      username:
        claim: sub
        prefix: "github:"
      groups:
        claim: groups
        prefix: "github:"
  
  - issuer:
      url: https://accounts.google.com
      audiences:
        - my-k8s-cluster
    claimMappings:
      username:
        claim: email
        prefix: "google:"
      groups:
        claim: groups
        prefix: "google:"
EOF

# Copy to minikube
minikube cp /tmp/auth-config-multi.yaml /tmp/auth-config.yaml

# Verify
minikube ssh "cat /tmp/auth-config.yaml"
```

---

### Step 2: Wait for API Server to Reload

The API server should automatically detect the config file change:

```bash
# Watch for restart (if needed)
kubectl get pods -n kube-system -w | grep kube-apiserver
```

**Note:** Some Kubernetes versions support dynamic reload, others require pod restart.

---

### Step 3: Verify Multiple Providers

```bash
# Check logs for both providers
kubectl logs -n kube-system kube-apiserver-minikube | grep -E "github|google"
```

---

## Exercise 3: Compare Before and After

Let's see what actually changed:

```bash
minikube ssh

echo "=== BEFORE (Original Config) ==="
sudo grep -A 3 "command:" /tmp/kube-apiserver.yaml.backup | head -15

echo ""
echo "=== AFTER (Modified Config) ==="
sudo grep -A 3 "command:" /etc/kubernetes/manifests/kube-apiserver.yaml | head -15

exit
```

**Key difference:** Added `--authentication-config=/tmp/auth-config.yaml`

---

## Rollback Instructions

### If API Server Fails to Start

```bash
# Method 1: Restore from backup
minikube ssh
sudo cp /tmp/kube-apiserver.yaml.backup /etc/kubernetes/manifests/kube-apiserver.yaml
exit

# Wait for API server to restart
kubectl get nodes
```

---

### If Cluster is Completely Broken

```bash
# Nuclear option: Delete and recreate
minikube delete
minikube start --kubernetes-version=v1.35.0 --cpus=2 --memory=4096

# Verify cluster is healthy
kubectl get nodes
```

---

## Configuration Examples

### Example 1: OIDC with Azure AD

```yaml
apiVersion: apiserver.config.k8s.io/v1beta1
kind: AuthenticationConfiguration
jwt:
  - issuer:
      url: https://login.microsoftonline.com/{tenant-id}/v2.0
      audiences:
        - {client-id}
    claimMappings:
      username:
        claim: preferred_username
        prefix: "azuread:"
      groups:
        claim: groups
        prefix: "azuread:"
    userValidationRules:
      - expression: "claims.iss == 'https://login.microsoftonline.com/{tenant-id}/v2.0'"
        message: "Token must be issued by Azure AD"
```

---

### Example 2: Multiple Audiences

```yaml
apiVersion: apiserver.config.k8s.io/v1beta1
kind: AuthenticationConfiguration
jwt:
  - issuer:
      url: https://accounts.google.com
      audiences:
        - production-cluster
        - staging-cluster
        - dev-cluster
    claimMappings:
      username:
        claim: email
```

---

### Example 3: Custom Claim Validation

```yaml
apiVersion: apiserver.config.k8s.io/v1beta1
kind: AuthenticationConfiguration
jwt:
  - issuer:
      url: https://your-idp.com
      audiences:
        - kubernetes
    claimMappings:
      username:
        claim: email
        prefix: "sso:"
    userValidationRules:
      - expression: "claims.email_verified == true"
        message: "Email must be verified"
      - expression: "claims.email.endsWith('@company.com')"
        message: "Only company.com emails allowed"
```

---

## Cleanup

```bash
# Restore original configuration
minikube ssh
sudo cp /tmp/kube-apiserver.yaml.backup /etc/kubernetes/manifests/kube-apiserver.yaml
exit

# Wait for API server to restart
kubectl get pods -n kube-system -w | grep kube-apiserver

# Verify cluster is healthy
kubectl get nodes

# Remove config files
minikube ssh "sudo rm /tmp/auth-config.yaml /tmp/kube-apiserver.yaml.backup"
```

---

## Production Recommendations

### 1. Testing Strategy

✅ **Test in dev/staging first**
- Verify all authentication providers work
- Test user and group mappings
- Validate claim expressions
- Test rollback procedures

❌ **Don't test in production**

---

### 2. Configuration Management

```yaml
# Store in version control
git add auth-config.yaml
git commit -m "Add OIDC authentication for Google"

# Use ConfigMaps in production (K8s 1.36+)
kubectl create configmap api-auth-config \
  --from-file=auth-config.yaml \
  -n kube-system
```

---

### 3. Monitoring

Monitor API server logs for authentication errors:

```bash
# Watch for auth failures
kubectl logs -n kube-system -f kube-apiserver-{pod} | grep -i "authentication\|jwt"
```

---

### 4. High Availability

For HA clusters:
- Update one API server at a time
- Verify health before proceeding to next
- Keep old pods running during rollout
- Have rollback plan ready

---

## Troubleshooting

### Issue: API Server Won't Start

**Symptoms:**
```
kube-apiserver-minikube   0/1   CrashLoopBackOff
```

**Check logs:**
```bash
kubectl logs -n kube-system kube-apiserver-minikube --previous
```

**Common causes:**
- Invalid YAML syntax in auth-config.yaml
- File path doesn't exist
- Permission issues

**Solution:**
```bash
# Restore backup
minikube ssh
sudo cp /tmp/kube-apiserver.yaml.backup /etc/kubernetes/manifests/kube-apiserver.yaml
exit
```

---

### Issue: Authentication Config Not Loading

**Check if file exists:**
```bash
minikube ssh "ls -la /tmp/auth-config.yaml"
```

**Verify flag is set:**
```bash
minikube ssh "sudo ps aux | grep authentication-config"
```

**Restart API server manually:**
```bash
minikube ssh
sudo touch /etc/kubernetes/manifests/kube-apiserver.yaml
exit
```

---

### Issue: JWT Token Validation Failing

**Check issuer URL is accessible:**
```bash
curl -I https://token.actions.githubusercontent.com/.well-known/openid-configuration
```

**Verify audience matches:**
- Token audience must match one in `audiences` list
- Case-sensitive matching

---

## Key Takeaways

✅ **Structured configuration is GA** - production-ready in K8s 1.35  
✅ **Better than command-line flags** - easier to manage and validate  
✅ **Supports multiple providers** - GitHub, Google, Azure AD, custom OIDC  
✅ **API server restart required** - changes take effect after pod restart  
✅ **Backwards compatible** - old flags still work  

---

## What We Learned

### Technical Insights
1. Configuration uses `apiserver.config.k8s.io/v1beta1` API
2. API server automatically restarts when manifest changes
3. Authentication API (`authentication.k8s.io/v1`) becomes available
4. Works alongside traditional authentication methods

### Practical Experience
1. Modifying API server config is safe with proper backups
2. Minikube makes it easy to test risky changes
3. API server restart takes ~60 seconds
4. Rollback is straightforward with backup

---

## Next Steps

- **Lab 4**: Node Declared Features (Alpha)
- **Article**: Write up findings from all labs

---

## References

- [KEP-3331: Structured Authentication Configuration](https://github.com/kubernetes/enhancements/tree/master/keps/sig-auth/3331-structured-authentication-configuration)
- [Kubernetes Authentication Documentation](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)
- [API Server Configuration Reference](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/)

---

**Lab Duration**: 15-20 minutes  
**Difficulty**: Intermediate  
**Risk Level**: Medium (requires API server modification)  
**Production Readiness**: GA - ready for production use

---

**Tested on:** Kubernetes 1.35.0, Minikube, Azure VM (2 vCPU, 8GB RAM)  
**Date:** December 19, 2025