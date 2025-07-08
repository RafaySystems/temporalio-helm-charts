# Istio Troubleshooting Guide for Temporal

This guide helps you troubleshoot common Istio issues when deploying Temporal with path-based routing.

## Common Error: `503 NC cluster_not_found`

### What This Error Means

The `503 NC cluster_not_found` error indicates that Istio cannot find the destination service. This usually happens due to:

1. **Service Discovery Issues**: Istio can't resolve the service name
2. **Wrong Service Names**: Using incorrect service names in Virtual Service
3. **Namespace Issues**: Services in different namespaces
4. **Istio Sidecar Issues**: Missing or misconfigured sidecar injection

### Step-by-Step Troubleshooting

#### 1. Check Service Names

First, verify the actual service names in your cluster:

```bash
# List all services in the default namespace
kubectl get svc -n default

# Look for Temporal services
kubectl get svc -n default | grep temporal

# Get detailed service information
kubectl describe svc temporal-web -n default
kubectl describe svc temporal-frontend -n default
```

#### 2. Verify Service Discovery

Check if Istio can discover the services:

```bash
# Check if services are in the Istio service registry
istioctl x describe svc temporal-web.default.svc.cluster.local
istioctl x describe svc temporal-frontend.default.svc.cluster.local

# Check Istio proxy endpoints
istioctl proxy-config endpoints $(kubectl get pods -l app=istio-ingressgateway -n istio-system -o jsonpath='{.items[0].metadata.name}') -n istio-system
```

#### 3. Check Virtual Service Configuration

Verify your Virtual Service is correctly configured:

```bash
# Get Virtual Service details
kubectl get virtualservice temporal-path-routing -n default -o yaml

# Check Virtual Service status
istioctl x describe virtualservice temporal-path-routing.default
```

#### 4. Check Gateway Configuration

Ensure the Gateway is properly configured:

```bash
# Get Gateway details
kubectl get gateway temporal-gateway -n default -o yaml

# Check Gateway status
istioctl x describe gateway temporal-gateway.default
```

#### 5. Check Istio Sidecar Injection

Verify that Temporal pods have Istio sidecars:

```bash
# Check if pods have sidecars
kubectl get pods -l app.kubernetes.io/name=temporal -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# Check sidecar logs
kubectl logs -l app.kubernetes.io/name=temporal -c istio-proxy
```

### Quick Fixes

#### Fix 1: Use Full Service Names

Update your Virtual Service to use full service names:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: temporal-path-routing
  namespace: default
spec:
  hosts:
  - ops-console.gaap.dev.rafay-edge.net
  gateways:
  - temporal-gateway
  http:
  - match:
    - uri:
        prefix: /temporal
    route:
    - destination:
        host: temporal-web.default.svc.cluster.local  # Full service name
        port:
          number: 8080
    rewrite:
      uri: /
```

#### Fix 2: Add Service Entry

If service discovery is still failing, add a Service Entry:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: temporal-service-entry
  namespace: default
spec:
  hosts:
  - temporal-web.default.svc.cluster.local
  - temporal-frontend.default.svc.cluster.local
  ports:
  - number: 8080
    name: http-web
    protocol: HTTP
  - number: 7233
    name: grpc-frontend
    protocol: GRPC
  location: MESH_INTERNAL
  resolution: DNS
```

#### Fix 3: Enable Istio Sidecar Injection

Ensure Istio sidecar injection is enabled for the namespace:

```bash
# Enable sidecar injection for the namespace
kubectl label namespace default istio-injection=enabled

# Restart Temporal pods to get sidecars
kubectl rollout restart deployment temporal-web -n default
kubectl rollout restart deployment temporal-frontend -n default
```

### Debugging Commands

#### Check Istio Proxy Configuration

```bash
# Get proxy configuration for ingress gateway
istioctl proxy-config all $(kubectl get pods -l app=istio-ingressgateway -n istio-system -o jsonpath='{.items[0].metadata.name}') -n istio-system

# Check routes
istioctl proxy-config routes $(kubectl get pods -l app=istio-ingressgateway -n istio-system -o jsonpath='{.items[0].metadata.name}') -n istio-system

# Check clusters
istioctl proxy-config clusters $(kubectl get pods -l app=istio-ingressgateway -n istio-system -o jsonpath='{.items[0].metadata.name}') -n istio-system
```

#### Check Istio Logs

```bash
# Check ingress gateway logs
kubectl logs -l app=istio-ingressgateway -n istio-system

# Check Temporal service logs
kubectl logs -l app.kubernetes.io/name=temporal -c temporal-web

# Check sidecar logs
kubectl logs -l app.kubernetes.io/name=temporal -c istio-proxy
```

#### Test Service Connectivity

```bash
# Test from within the cluster
kubectl run test-pod --image=curlimages/curl -i --rm --restart=Never -- curl -v http://temporal-web.default.svc.cluster.local:8080

# Test from ingress gateway
kubectl exec -it $(kubectl get pods -l app=istio-ingressgateway -n istio-system -o jsonpath='{.items[0].metadata.name}') -n istio-system -- curl -v http://temporal-web.default.svc.cluster.local:8080
```

### Common Issues and Solutions

#### Issue 1: Service Not Found

**Symptoms**: `503 NC cluster_not_found`

**Solution**:
```yaml
# Use full service names in Virtual Service
destination:
  host: temporal-web.default.svc.cluster.local
  port:
    number: 8080
```

#### Issue 2: Wrong Port Configuration

**Symptoms**: Connection refused or timeout

**Solution**:
```bash
# Verify service ports
kubectl get svc temporal-web -o jsonpath='{.spec.ports[*].port}'

# Update Virtual Service with correct port
destination:
  host: temporal-web.default.svc.cluster.local
  port:
    number: 8080  # Must match service port
```

#### Issue 3: Namespace Mismatch

**Symptoms**: Service not found in different namespace

**Solution**:
```yaml
# If Temporal is in different namespace
destination:
  host: temporal-web.temporal-namespace.svc.cluster.local
  port:
    number: 8080
```

#### Issue 4: Istio Sidecar Not Injected

**Symptoms**: Services not visible to Istio

**Solution**:
```bash
# Enable sidecar injection
kubectl label namespace default istio-injection=enabled

# Restart deployments
kubectl rollout restart deployment temporal-web
kubectl rollout restart deployment temporal-frontend
```

### Testing Your Fix

#### 1. Apply the Fixed Configuration

```bash
# Apply the fixed configuration
kubectl apply -f charts/temporal/values/values.istio-path-routing-fixed.yaml
```

#### 2. Test the Endpoint

```bash
# Test the endpoint
curl -v -H "Host: ops-console.gaap.dev.rafay-edge.net" \
  https://your-ingress-ip/temporal

# Or test locally
curl -v -H "Host: ops-console.gaap.dev.rafay-edge.net" \
  http://localhost/temporal
```

#### 3. Check Virtual Service Status

```bash
# Verify Virtual Service is working
istioctl x describe virtualservice temporal-path-routing.default

# Check for any errors
kubectl describe virtualservice temporal-path-routing
```

### Monitoring and Alerts

#### Set Up Monitoring

```yaml
# Prometheus monitoring for Istio
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-ingressgateway
  namespace: istio-system
spec:
  selector:
    matchLabels:
      app: istio-ingressgateway
  endpoints:
  - port: http-monitoring
```

#### Common Metrics to Monitor

- `istio_requests_total`: Total requests
- `istio_request_duration_milliseconds`: Request duration
- `istio_request_errors_total`: Error count
- `istio_tcp_connections_closed_total`: Connection issues

### Prevention

#### Best Practices

1. **Always use full service names** in Virtual Services
2. **Enable Istio sidecar injection** for all namespaces with services
3. **Test service discovery** before applying Virtual Services
4. **Use consistent naming conventions** for services
5. **Monitor Istio proxy logs** for early detection of issues

#### Validation Script

```bash
#!/bin/bash
# Validation script for Istio Temporal setup

echo "Checking Temporal services..."
kubectl get svc -l app.kubernetes.io/name=temporal

echo "Checking Virtual Service..."
kubectl get virtualservice temporal-path-routing

echo "Checking Gateway..."
kubectl get gateway temporal-gateway

echo "Checking Istio sidecars..."
kubectl get pods -l app.kubernetes.io/name=temporal -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

echo "Testing service connectivity..."
kubectl run test-curl --image=curlimages/curl -i --rm --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" http://temporal-web.default.svc.cluster.local:8080
```

This troubleshooting guide should help you resolve the `503 NC cluster_not_found` error and other common Istio issues with Temporal. 