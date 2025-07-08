# Temporal Web UI 500 Internal Error Troubleshooting Guide

## Problem Description

The Temporal Web UI at `https://ops-console.gaap.dev.rafay-edge.net/temporal` is showing a 500 "Internal Error" instead of loading properly.

## Root Cause Analysis

A 500 error on the Web UI typically indicates:
1. **Web UI can't connect to Temporal backend**
2. **Authentication issues** (even though we disabled auth)
3. **API endpoint configuration problems**
4. **CORS issues**
5. **Backend service unavailability**

## Troubleshooting Steps

### Step 1: Check Web UI Logs

```bash
# Check web UI pod logs
kubectl logs -l app.kubernetes.io/component=web -n rafay-core --tail=50

# Check for specific error messages
kubectl logs -l app.kubernetes.io/component=web -n rafay-core | grep -i "error\|500\|failed"
```

### Step 2: Check Frontend Service Logs

```bash
# Check frontend service logs (the API backend)
kubectl logs -l app.kubernetes.io/component=frontend -n rafay-core --tail=50

# Look for connection errors
kubectl logs -l app.kubernetes.io/component=frontend -n rafay-core | grep -i "error\|failed\|connection"
```

### Step 3: Check Service Connectivity

```bash
# Check if all services are running
kubectl get pods -n rafay-core -l app.kubernetes.io/name=temporal

# Check service endpoints
kubectl get endpoints -n rafay-core | grep temporal

# Check if web UI can reach frontend service
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/component=web -n rafay-core -o jsonpath='{.items[0].metadata.name}') -n rafay-core -- curl -v http://temporal-frontend:7233
```

### Step 4: Check Web UI Environment Variables

```bash
# Check web UI pod environment variables
kubectl describe pod -l app.kubernetes.io/component=web -n rafay-core

# Look for API configuration
kubectl get pod -l app.kubernetes.io/component=web -n rafay-core -o jsonpath='{.items[0].spec.containers[0].env}' | jq
```

### Step 5: Test Direct API Access

```bash
# Port forward to test direct access
kubectl port-forward svc/temporal-frontend 7233:7233 -n rafay-core

# In another terminal, test the API
curl -X GET "http://localhost:7233/api/v1/cluster/info" \
  -H "Content-Type: application/json"
```

## Common Solutions

### Solution 1: Fix Web UI API Configuration

The issue might be that the Web UI is still trying to use authentication. Update the web UI configuration:

```yaml
web:
  additionalEnv:
    - name: TEMPORAL_UI_PUBLIC_PATH
      value: "/temporal"
    - name: TEMPORAL_UI_API_BASE_URL
      value: "/temporal"
    - name: TEMPORAL_UI_SERVER_API_BASE_URL
      value: "/temporal"
    - name: TEMPORAL_UI_SERVER_API_TIMEOUT
      value: "10000"
    # Disable authentication for web UI
    - name: TEMPORAL_AUTH_ENABLED
      value: "false"
    # Remove OIDC configuration
    # - name: TEMPORAL_AUTH_PROVIDER_URL
    #   value: "https://console.gaap.dev.rafay-edge.net/dex"
    # - name: TEMPORAL_AUTH_CLIENT_ID
    #   value: "temporal-web-ui"
    # - name: TEMPORAL_AUTH_CALLBACK_URL
    #   value: "https://ops-console.gaap.dev.rafay-edge.net/temporal/auth/sso/callback"
```

### Solution 2: Check Istio Virtual Service Configuration

The issue might be in the Istio routing. Check your Virtual Service:

```bash
# Check Virtual Service configuration
kubectl get virtualservice -A | grep temporal

# Check the specific configuration
kubectl get virtualservice -n rafay-core -o yaml
```

### Solution 3: Test Web UI Directly

```bash
# Port forward web UI directly
kubectl port-forward svc/temporal-web 8080:8080 -n rafay-core

# Then access locally
curl -X GET "http://localhost:8080"
```

### Solution 4: Check Network Policies

```bash
# Check if network policies are blocking communication
kubectl get networkpolicy -n rafay-core

# If there are policies, they might be blocking web UI to frontend communication
```

## Debugging Commands

### Check Service Status

```bash
# Check all temporal services
kubectl get pods -n rafay-core -l app.kubernetes.io/name=temporal

# Check service endpoints
kubectl get endpoints -n rafay-core | grep temporal

# Check if services can communicate
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/component=web -n rafay-core -o jsonpath='{.items[0].metadata.name}') -n rafay-core -- nslookup temporal-frontend
```

### Check Configuration

```bash
# Check web UI configmap
kubectl get configmap -n rafay-core | grep temporal

# Check if there are any configuration issues
kubectl describe configmap temporal-web-config -n rafay-core
```

## Expected Behavior After Fix

After resolving the issue, you should see:
- ✅ Web UI loads without 500 error
- ✅ Can navigate to different sections
- ✅ Can view workflows and namespaces
- ✅ Can access settings through the UI

## Quick Fix Attempt

Try this immediate fix by updating the web UI configuration:

```bash
# Apply a simple web UI configuration without auth
helm upgrade temporal charts/temporal \
  --namespace rafay-core \
  --set web.additionalEnv[0].name=TEMPORAL_UI_PUBLIC_PATH \
  --set web.additionalEnv[0].value="/temporal" \
  --set web.additionalEnv[1].name=TEMPORAL_UI_API_BASE_URL \
  --set web.additionalEnv[1].value="/temporal" \
  --set web.additionalEnv[2].name=TEMPORAL_UI_SERVER_API_BASE_URL \
  --set web.additionalEnv[2].value="/temporal" \
  --set web.additionalEnv[3].name=TEMPORAL_UI_SERVER_API_TIMEOUT \
  --set web.additionalEnv[3].value="10000" \
  --set web.additionalEnv[4].name=TEMPORAL_AUTH_ENABLED \
  --set web.additionalEnv[4].value="false"
```

## Next Steps

1. **Check the logs** to identify the specific error
2. **Verify service connectivity** between web UI and frontend
3. **Update web UI configuration** to disable authentication
4. **Test the fix** by accessing the web UI again 