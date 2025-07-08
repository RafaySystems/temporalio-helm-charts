# Fix Istio API Routing Issue

## Problem
API requests to `/temporal/api/v1/settings` are being routed to the **web service** (port 8080) instead of the **frontend service** (port 7233).

## Root Cause
The Istio Virtual Service configuration has incorrect URI matching or rule ordering.

## Solution

### Correct Istio Virtual Service Configuration

Update your Virtual Service in the Rafay Ops Console with this exact configuration:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: temporal-vs
  namespace: rafay-core
spec:
  hosts:
  - "ops-console.gaap.dev.rafay-edge.net"
  gateways:
  - istio-system/rafay-gateway
  http:
  # RULE 1: API requests - MUST BE FIRST (more specific)
  - match:
    - uri:
        prefix: "/temporal/api"
    rewrite:
      uri: "/"
    route:
    - destination:
        host: temporalio-frontend.rafay-core.svc.cluster.local
        port:
          number: 7233
  # RULE 2: Web UI requests - MUST BE SECOND (less specific)
  - match:
    - uri:
        prefix: "/temporal"
    route:
    - destination:
        host: temporalio-web.rafay-core.svc.cluster.local
        port:
          number: 8080
```

## Key Points

### 1. Rule Order Matters
- **More specific rules must come first**
- `/temporal/api` is more specific than `/temporal`
- If `/temporal` comes first, it will match `/temporal/api` and route incorrectly

### 2. URI Rewriting
- API requests need URI rewriting: `/temporal/api/v1/settings` → `/v1/settings`
- This is handled by the `rewrite: uri: "/"` in the API rule

### 3. Service Names
- **Frontend service**: `temporalio-frontend.rafay-core.svc.cluster.local:7233`
- **Web service**: `temporalio-web.rafay-core.svc.cluster.local:8080`

## Verification Steps

### 1. Check Current Routing
```bash
# Test API endpoint
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/settings" \
  -H "Content-Type: application/json"

# Expected: Should return JSON data, not HTML
```

### 2. Check Istio Logs
Look for these patterns in the logs:
- ✅ **Correct**: `outbound|7233||temporalio-frontend.rafay-core.svc.cluster.local`
- ❌ **Wrong**: `outbound|8080||temporalio-web.rafay-core.svc.cluster.local`

### 3. Test Different Endpoints
```bash
# API endpoint (should go to frontend service)
curl "https://ops-console.gaap.dev.rafay-edge.net/temporal/api/v1/cluster/info"

# Web UI endpoint (should go to web service)
curl "https://ops-console.gaap.dev.rafay-edge.net/temporal/settings"
```

## Common Mistakes to Avoid

### 1. Wrong Rule Order
```yaml
# ❌ WRONG - /temporal will match /temporal/api
- match:
  - uri:
      prefix: "/temporal"
- match:
  - uri:
      prefix: "/temporal/api"
```

### 2. Missing URI Rewrite
```yaml
# ❌ WRONG - API calls will fail
- match:
  - uri:
      prefix: "/temporal/api"
  route:
  - destination:
      host: temporalio-frontend.rafay-core.svc.cluster.local
      port:
        number: 7233
```

### 3. Incorrect Service Names
```yaml
# ❌ WRONG - Wrong service names
- destination:
    host: temporal-frontend.rafay-core.svc.cluster.local  # Missing 'io'
    port:
      number: 7233
```

## Expected Behavior After Fix

1. **API requests** (`/temporal/api/*`) → Frontend service (port 7233) → JSON responses
2. **Web UI requests** (`/temporal/*`) → Web service (port 8080) → HTML/JS/CSS
3. **No more 415 errors** on API endpoints
4. **Proper JSON responses** from API calls

## Troubleshooting

If the issue persists:

1. **Check Virtual Service status**:
   ```bash
   kubectl get virtualservice -n rafay-core
   kubectl describe virtualservice temporal-vs -n rafay-core
   ```

2. **Check Istio proxy logs**:
   ```bash
   kubectl logs -n istio-system -l app=istio-ingressgateway --tail=50
   ```

3. **Verify service endpoints**:
   ```bash
   kubectl get endpoints -n rafay-core | grep temporal
   ``` 