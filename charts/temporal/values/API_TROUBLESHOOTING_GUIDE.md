# Temporal API 415 Error Troubleshooting Guide

## Problem Description

The Temporal API endpoint `https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/settings` is returning a **415 Unsupported Media Type** error.

## Service Architecture

- **URL**: `https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/settings`
- **Service**: Temporal Frontend (port 7233)
- **Protocol**: HTTP API (not gRPC)
- **Path**: `/temporal/api/v1/settings`

## 415 Error Analysis

A 415 error means "Unsupported Media Type" - the server doesn't understand the content type of the request.

### Possible Causes

1. **Incorrect Content-Type Header**
2. **Missing Request Body**
3. **Wrong API Endpoint**
4. **Authentication Issues**
5. **Istio Routing Problems**

## Troubleshooting Steps

### Step 1: Check the Correct API Endpoint

The Temporal API might not use `/v1/` in the path. Try these endpoints:

```bash
# Test different API paths
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/settings"
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/settings"
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/settings"
```

### Step 2: Check Request Headers

```bash
# Test with proper headers
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/settings" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -v
```

### Step 3: Check if it's a POST Request

Some Temporal API endpoints expect POST requests:

```bash
# Test as POST request
curl -X POST "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/settings" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{}' \
  -v
```

### Step 4: Check Frontend Service Logs

```bash
# Check frontend service logs
kubectl logs -l app.kubernetes.io/component=frontend -n rafay-core --tail=50

# Check for any errors related to the API request
kubectl logs -l app.kubernetes.io/component=frontend -n rafay-core | grep -i "415\|unsupported\|media"
```

### Step 5: Verify Istio Routing

Check if the request is reaching the correct service:

```bash
# Check Istio Virtual Service
kubectl get virtualservice -A | grep temporal

# Check the specific Virtual Service configuration
kubectl get virtualservice -n rafay-core -o yaml
```

### Step 6: Test Direct Service Access

Test if the issue is with Istio routing or the service itself:

```bash
# Port forward to test direct access
kubectl port-forward svc/temporal-frontend 7233:7233 -n rafay-core

# Then test locally
curl -X GET "http://localhost:7233/api/v1/settings" \
  -H "Content-Type: application/json" \
  -v
```

## Common Solutions

### Solution 1: Fix Content-Type Header

```bash
# Use the correct content type
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/settings" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json"
```

### Solution 2: Use Correct API Path

The Temporal API might not use `/v1/`:

```bash
# Try without version
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/settings"

# Try different paths
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/settings"
```

### Solution 3: Check if Authentication is Required

Even though we disabled auth, some endpoints might still require it:

```bash
# Test with a simple endpoint first
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/health"

# Test with basic auth if needed
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/settings" \
  -u "username:password"
```

### Solution 4: Fix Istio Virtual Service

The issue might be in the Istio routing configuration:

```yaml
# Check if the Virtual Service is correctly routing API requests
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: temporal-api
spec:
  hosts:
  - ops-console.gaap.dev.rafay-edge.net
  http:
  - match:
    - uri:
        prefix: /temporal/api
    route:
    - destination:
        host: temporal-frontend.rafay-core.svc.cluster.local
        port:
          number: 7233
    rewrite:
      uri: /
```

## Debugging Commands

### Check Service Status

```bash
# Check if frontend service is running
kubectl get pods -l app.kubernetes.io/component=frontend -n rafay-core

# Check service endpoints
kubectl get endpoints temporal-frontend -n rafay-core
```

### Check Network Policies

```bash
# Check if there are network policies blocking the request
kubectl get networkpolicy -n rafay-core
```

### Check Istio Sidecar

```bash
# Check if Istio sidecar is working
kubectl logs -l app.kubernetes.io/component=frontend -n rafay-core -c istio-proxy
```

## Expected Behavior

After fixing the issue, you should get a successful response:

```json
{
  "settings": {
    // Temporal settings
  }
}
```

## Next Steps

1. **Identify the correct API endpoint** for the settings
2. **Check the Temporal API documentation** for the correct format
3. **Verify Istio routing** is working correctly
4. **Test with a known working endpoint** first
5. **Check if authentication is actually required** for this endpoint 