# Lab 3: Structured Authentication Configuration (GA)

## Overview
Configure API server authentication dynamically using config files instead of command-line flags.

**Feature Status**: GA in v1.35 ✅

## Quick Example

```yaml
# auth-config.yaml
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

## Testing on Minikube

```bash
# Create auth config
mkdir -p ~/k8s-135-labs/lab3-structured-auth
cd ~/k8s-135-labs/lab3-structured-auth

cat > auth-config.yaml <<EOF
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

# Copy to minikube
minikube cp auth-config.yaml minikube:/tmp/auth-config.yaml

# Update API server (requires restart)
echo "Note: This requires modifying /etc/kubernetes/manifests/kube-apiserver.yaml"
echo "Add: --authentication-config=/tmp/auth-config.yaml"
```

**Key Benefit**: Update auth config without restarting API server!
