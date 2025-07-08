# OIDC Troubleshooting Guide for Temporal

This guide helps you troubleshoot OIDC authentication issues with Temporal, particularly JWKS endpoint problems.

## Common Error: `json: cannot unmarshal number into Go value of type jose.JSONWebKeySet`

### What This Error Means

This error occurs when Temporal tries to fetch the JWKS (JSON Web Key Set) from your OIDC provider, but receives a number (usually an HTTP error code like 404, 500, etc.) instead of the expected JSON structure.

### Root Causes

1. **OIDC Provider Not Deployed**: The OIDC provider (Dex, Auth0, etc.) is not running at the specified URL
2. **Incorrect URL**: The JWKS endpoint URL is wrong
3. **Network Issues**: Temporal cannot reach the OIDC provider
4. **Authentication Required**: The JWKS endpoint requires authentication
5. **Wrong Path**: The JWKS endpoint is at a different path

## Step-by-Step Troubleshooting

### 1. Verify OIDC Provider is Running

```bash
# Test if the OIDC provider is accessible
curl -v https://your-oidc-provider.com/.well-known/openid_configuration

# Expected response: JSON with OIDC configuration
# If you get HTML or error pages, the provider is not running
```

### 2. Check JWKS Endpoint

```bash
# Test the JWKS endpoint directly
curl -v https://your-oidc-provider.com/.well-known/jwks.json

# Expected response: JSON with keys array
# Example:
# {
#   "keys": [
#     {
#       "kty": "RSA",
#       "kid": "key-id",
#       "n": "...",
#       "e": "AQAB"
#     }
#   ]
# }
```

### 3. Check OIDC Configuration

```bash
# Get the OIDC configuration to find the correct JWKS URL
curl -s https://your-oidc-provider.com/.well-known/openid_configuration | jq '.jwks_uri'

# This should return the correct JWKS endpoint URL
```

### 4. Test Network Connectivity

```bash
# Test from within the Kubernetes cluster
kubectl run test-oidc --image=curlimages/curl -i --rm --restart=Never -- \
  curl -v https://your-oidc-provider.com/.well-known/jwks.json

# Test from Temporal pod
kubectl exec -it $(kubectl get pods -l app.kubernetes.io/name=temporal -o jsonpath='{.items[0].metadata.name}') -- \
  curl -v https://your-oidc-provider.com/.well-known/jwks.json
```

## Common Issues and Solutions

### Issue 1: OIDC Provider Not Deployed

**Symptoms**: 
- 404 Not Found
- Parking page HTML
- Connection refused

**Solution**:
```bash
# Deploy Dex (example)
helm repo add dex https://charts.dexidp.io
helm install dex dex/dex -f dex-values.yaml

# Or use a different OIDC provider
```

### Issue 2: Wrong URL

**Symptoms**: 
- 404 Not Found
- Different service responding

**Solution**:
```yaml
# Update the JWKS URL in your configuration
server:
  config:
    authorization:
      jwtKeyProvider:
        keySourceURIs:
          - "https://correct-dex-url.com/.well-known/jwks.json"
```

### Issue 3: Dex Not Configured for JWKS

**Symptoms**: 
- 404 on JWKS endpoint
- OIDC config works but JWKS doesn't

**Solution**:
```yaml
# Ensure Dex is configured to serve JWKS
# dex-values.yaml
config:
  issuer: https://dex.your-domain.com
  storage:
    type: kubernetes
    config:
      inCluster: true
  # Dex automatically serves JWKS at /.well-known/jwks.json
  # when properly configured
```

### Issue 4: Network/Firewall Issues

**Symptoms**: 
- Connection timeout
- Connection refused

**Solution**:
```bash
# Check if the service is accessible from the cluster
kubectl run test-network --image=curlimages/curl -i --rm --restart=Never -- \
  curl -v https://your-oidc-provider.com/.well-known/jwks.json

# Check DNS resolution
kubectl run test-dns --image=busybox -i --rm --restart=Never -- \
  nslookup your-oidc-provider.com
```

## Quick Fixes

### Fix 1: Disable OIDC Temporarily

If you need to get Temporal running quickly:

```yaml
# Comment out or remove the authorization section
server:
  config:
    # authorization:
    #   jwtKeyProvider:
    #     keySourceURIs:
    #       - "https://dex.your-domain.com/.well-known/jwks.json"
    #   permissionsClaimName: groups
    #   authorizer: default
    #   claimMapper: default
```

### Fix 2: Use a Working OIDC Provider

```yaml
# Use Auth0 (free tier available)
server:
  config:
    authorization:
      jwtKeyProvider:
        keySourceURIs:
          - "https://your-domain.auth0.com/.well-known/jwks.json"
        refreshInterval: 1m
      permissionsClaimName: permissions
      authorizer: default
      claimMapper: default
```

### Fix 3: Deploy Dex Locally

```bash
# Deploy Dex in your cluster
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: dex-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dex
  namespace: dex-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dex
  template:
    metadata:
      labels:
        app: dex
    spec:
      containers:
      - name: dex
        image: dexidp/dex:v2.38.1
        ports:
        - containerPort: 5556
        args:
        - serve
        - /etc/dex/config.yaml
        volumeMounts:
        - name: dex-config
          mountPath: /etc/dex
      volumes:
      - name: dex-config
        configMap:
          name: dex-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dex-config
  namespace: dex-system
data:
  config.yaml: |
    issuer: http://dex.dex-system.svc.cluster.local:5556
    storage:
      type: memory
    web:
      http: 0.0.0.0:5556
    connectors:
    - type: mockCallback
      id: mock
      name: Mock
    oauth2:
      skipApprovalScreen: true
    staticClients:
    - id: temporal-client
      secret: temporal-secret
      name: 'Temporal'
      redirectURIs:
      - 'http://localhost:8080/callback'
---
apiVersion: v1
kind: Service
metadata:
  name: dex
  namespace: dex-system
spec:
  ports:
  - port: 5556
    targetPort: 5556
  selector:
    app: dex
EOF

# Update Temporal configuration
server:
  config:
    authorization:
      jwtKeyProvider:
        keySourceURIs:
          - "http://dex.dex-system.svc.cluster.local:5556/.well-known/jwks.json"
        refreshInterval: 1m
      permissionsClaimName: groups
      authorizer: default
      claimMapper: default
```

## Debugging Commands

### Check Temporal Logs

```bash
# Check Temporal server logs for OIDC errors
kubectl logs -l app.kubernetes.io/name=temporal -c temporal-server | grep -i oidc

# Check for JWKS refresh errors
kubectl logs -l app.kubernetes.io/name=temporal -c temporal-server | grep -i jwks
```

### Test JWKS Endpoint

```bash
# Test JWKS endpoint and validate JSON
curl -s https://your-oidc-provider.com/.well-known/jwks.json | jq .

# Check if it's valid JSON
curl -s https://your-oidc-provider.com/.well-known/jwks.json | python3 -m json.tool
```

### Validate OIDC Configuration

```bash
# Get and validate OIDC configuration
curl -s https://your-oidc-provider.com/.well-known/openid_configuration | jq .

# Check if jwks_uri is present
curl -s https://your-oidc-provider.com/.well-known/openid_configuration | jq '.jwks_uri'
```

## Monitoring and Alerts

### Set Up Monitoring

```yaml
# Prometheus monitoring for OIDC
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: temporal-oidc
spec:
  selector:
    matchLabels:
      app: temporal-server
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

### Common Metrics to Monitor

- `temporal_oidc_jwks_refresh_total`: JWKS refresh attempts
- `temporal_oidc_jwks_refresh_errors_total`: JWKS refresh errors
- `temporal_oidc_token_validation_total`: Token validation attempts
- `temporal_oidc_token_validation_errors_total`: Token validation errors

## Prevention

### Best Practices

1. **Test OIDC endpoints before deployment**
2. **Use health checks for OIDC providers**
3. **Implement fallback OIDC providers**
4. **Monitor OIDC provider availability**
5. **Use proper TLS certificates**

### Validation Script

```bash
#!/bin/bash
# OIDC validation script

OIDC_PROVIDER=${1:-"https://dex.your-domain.com"}

echo "Testing OIDC provider: $OIDC_PROVIDER"

# Test OIDC configuration
echo "1. Testing OIDC configuration..."
OIDC_CONFIG=$(curl -s "$OIDC_PROVIDER/.well-known/openid_configuration")
if [ $? -eq 0 ]; then
    echo "✓ OIDC configuration accessible"
    JWKS_URI=$(echo "$OIDC_CONFIG" | jq -r '.jwks_uri // empty')
    if [ -n "$JWKS_URI" ]; then
        echo "✓ JWKS URI found: $JWKS_URI"
    else
        echo "✗ No JWKS URI in OIDC configuration"
    fi
else
    echo "✗ OIDC configuration not accessible"
fi

# Test JWKS endpoint
echo "2. Testing JWKS endpoint..."
JWKS_RESPONSE=$(curl -s "$OIDC_PROVIDER/.well-known/jwks.json")
if [ $? -eq 0 ]; then
    if echo "$JWKS_RESPONSE" | jq . >/dev/null 2>&1; then
        echo "✓ JWKS endpoint returns valid JSON"
        KEYS_COUNT=$(echo "$JWKS_RESPONSE" | jq '.keys | length')
        echo "✓ Found $KEYS_COUNT keys"
    else
        echo "✗ JWKS endpoint does not return valid JSON"
        echo "Response: $JWKS_RESPONSE"
    fi
else
    echo "✗ JWKS endpoint not accessible"
fi

# Test from within cluster
echo "3. Testing from within cluster..."
kubectl run test-oidc-cluster --image=curlimages/curl -i --rm --restart=Never -- \
  curl -s "$OIDC_PROVIDER/.well-known/jwks.json" | jq . >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ JWKS accessible from cluster"
else
    echo "✗ JWKS not accessible from cluster"
fi
```

This troubleshooting guide should help you resolve the OIDC/JWKS issues with Temporal. 