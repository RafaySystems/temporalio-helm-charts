# Complete Temporal + Dex Deployment Guide

This guide provides step-by-step instructions for deploying a production-ready Temporal setup with Dex OIDC authentication.

## Prerequisites

- Kubernetes cluster (1.20+)
- kubectl configured
- Helm 3.x
- Ingress controller (nginx, istio, etc.)
- TLS certificates for your domain

## Quick Start

### 1. Deploy Dex First

```bash
# Apply Dex configuration
kubectl apply -f complete-temporal-dex-setup.yaml

# Wait for Dex to be ready
kubectl wait --for=condition=ready pod -l app=dex -n dex-system --timeout=300s
```

### 2. Deploy Temporal

```bash
# Deploy Temporal with Helm
helm install temporal ./charts/temporal -f complete-temporal-dex-setup.yaml -n temporal-system

# Wait for Temporal to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=temporal -n temporal-system --timeout=600s
```

### 3. Verify Deployment

```bash
# Check Dex
kubectl get pods -n dex-system
kubectl get svc -n dex-system

# Check Temporal
kubectl get pods -n temporal-system
kubectl get svc -n temporal-system

# Test endpoints
curl https://console.gaap.dev.rafay-edge.net/dex/keys
curl -I https://ops-console.gaap.dev.rafay-edge.net/temporal
```

## Configuration Details

### Dex Configuration

The Dex configuration includes:

- **Issuer**: `https://console.gaap.dev.rafay-edge.net/dex`
- **Storage**: Kubernetes (production-ready)
- **Clients**: Three OIDC clients for Temporal
- **Connectors**: Kubernetes service accounts
- **Static Users**: Admin user for testing

### Temporal Configuration

The Temporal configuration includes:

- **OIDC Integration**: Full OIDC authentication
- **Internal Services**: Bypass auth for internal communication
- **System Workflows**: Allow system workflows without auth
- **External Clients**: Require OIDC for external access
- **Path-based Routing**: Configured for `/temporal` path

## OIDC Clients

| Client ID | Purpose | Redirect URIs |
|-----------|---------|---------------|
| `temporal-client` | Temporal Server | `https://ops-console.gaap.dev.rafay-edge.net/temporal/auth/sso/callback` |
| `temporal-worker` | External Workers | `http://localhost:8080/callback` |
| `temporal-web-ui` | Web UI | `https://ops-console.gaap.dev.rafay-edge.net/temporal/auth/sso/callback` |

## Access Information

### URLs
- **Dex OIDC**: `https://console.gaap.dev.rafay-edge.net/dex`
- **Temporal Web UI**: `https://ops-console.gaap.dev.rafay-edge.net/temporal`
- **Temporal API**: `https://ops-console.gaap.dev.rafay-edge.net/temporal/api`

### Default Credentials
- **Email**: `admin@rafay-edge.net`
- **Password**: `admin123`

## Worker Configuration

### External Worker with OIDC

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-temporal-worker
  namespace: temporal-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-temporal-worker
  template:
    metadata:
      labels:
        app: my-temporal-worker
    spec:
      serviceAccountName: temporal-worker-sa
      containers:
      - name: worker
        image: your-worker-image:latest
        env:
        - name: TEMPORAL_HOST_PORT
          value: "temporal-frontend.temporal-system.svc.cluster.local:7233"
        - name: TEMPORAL_NAMESPACE
          value: "default"
        - name: TEMPORAL_TASK_QUEUE
          value: "my-task-queue"
        - name: TEMPORAL_OIDC_ISSUER
          value: "https://console.gaap.dev.rafay-edge.net/dex"
        - name: TEMPORAL_OIDC_AUDIENCE
          value: "temporal-worker"
        - name: TEMPORAL_OIDC_CLIENT_ID
          value: "temporal-worker"
        - name: TEMPORAL_OIDC_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: temporal-oidc-secret
              key: worker-secret
```

### Go Worker Example

```go
package main

import (
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/worker"
)

func main() {
    c, err := client.NewClient(client.Options{
        HostPort: "temporal-frontend.temporal-system.svc.cluster.local:7233",
        Identity: "my-worker",
        Headers: map[string]string{
            "Authorization": "Bearer " + getOIDCToken(),
        },
    })
    if err != nil {
        panic(err)
    }
    defer c.Close()

    w := worker.New(c, "my-task-queue", worker.Options{})
    // Register workflows and activities
    w.Run(worker.InterruptCh())
}

func getOIDCToken() string {
    // Implement OIDC token acquisition
    // Use the temporal-worker client credentials
    return "your-oidc-token"
}
```

## Security Considerations

### 1. Change Default Passwords
```bash
# Update Dex configuration with secure passwords
kubectl edit configmap dex-config -n dex-system
```

### 2. Configure TLS
```bash
# Create TLS secret for Dex
kubectl create secret tls dex-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem \
  -n dex-system
```

### 3. Network Policies
The configuration includes network policies that:
- Allow communication between Temporal and Dex
- Restrict external access
- Enable DNS resolution

### 4. RBAC
Proper RBAC is configured for:
- Dex service account
- Temporal service accounts
- Worker service accounts

## Monitoring

### Metrics
Temporal exposes metrics with OIDC tags:
- `temporal_oidc_jwks_refresh_total`
- `temporal_oidc_token_validation_total`
- `temporal_oidc_authentication_errors_total`

### Logs
```bash
# Dex logs
kubectl logs -f -l app=dex -n dex-system

# Temporal logs
kubectl logs -f -l app.kubernetes.io/name=temporal -n temporal-system
```

## Troubleshooting

### Common Issues

1. **Dex not accessible**
   ```bash
   # Check Dex pods
   kubectl get pods -n dex-system
   
   # Check Dex service
   kubectl get svc -n dex-system
   
   # Test internal access
   kubectl run test --image=curlimages/curl -i --rm --restart=Never -- \
     curl http://dex.dex-system.svc.cluster.local:5556/keys
   ```

2. **Temporal OIDC errors**
   ```bash
   # Check Temporal logs
   kubectl logs -l app.kubernetes.io/name=temporal -c temporal-server -n temporal-system | grep -i oidc
   
   # Verify JWKS endpoint
   curl https://console.gaap.dev.rafay-edge.net/dex/keys
   ```

3. **Worker authentication failures**
   ```bash
   # Check worker logs
   kubectl logs -l app=my-temporal-worker -n temporal-system
   
   # Verify OIDC token
   kubectl exec -it deployment/my-temporal-worker -n temporal-system -- \
     env | grep TEMPORAL_OIDC
   ```

### Debug Commands

```bash
# Check all resources
kubectl get all -n dex-system
kubectl get all -n temporal-system

# Check secrets
kubectl get secrets -n temporal-system

# Check service accounts
kubectl get serviceaccounts -n temporal-system

# Check network policies
kubectl get networkpolicies -n temporal-system
```

## Backup and Recovery

### Backup Dex Data
```bash
# Backup Dex configuration
kubectl get configmap dex-config -n dex-system -o yaml > dex-config-backup.yaml

# Backup Dex secrets
kubectl get secret dex-tls -n dex-system -o yaml > dex-tls-backup.yaml
```

### Backup Temporal Data
```bash
# Backup Temporal secrets
kubectl get secret temporal-oidc-secret -n temporal-system -o yaml > temporal-oidc-backup.yaml

# Backup Temporal configuration
helm get values temporal -n temporal-system > temporal-values-backup.yaml
```

## Scaling

### Scale Dex
```bash
kubectl scale deployment dex -n dex-system --replicas=3
```

### Scale Temporal
```bash
# Scale frontend
kubectl scale deployment temporal-frontend -n temporal-system --replicas=3

# Scale history
kubectl scale deployment temporal-history -n temporal-system --replicas=3

# Scale matching
kubectl scale deployment temporal-matching -n temporal-system --replicas=3
```

## Uninstall

```bash
# Uninstall Temporal
helm uninstall temporal -n temporal-system

# Delete namespaces
kubectl delete namespace temporal-system
kubectl delete namespace dex-system

# Clean up RBAC
kubectl delete clusterrole dex temporal-role
kubectl delete clusterrolebinding dex temporal-role-binding
```

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review Temporal and Dex documentation
3. Check logs for specific error messages
4. Verify network connectivity and DNS resolution 