# Istio Path-Based Routing Guide for Temporal

This guide explains how to configure Temporal with path-based routing using Istio Virtual Service instead of traditional ingress controllers.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    External Traffic                             │
│                         │                                       │
│                         ▼                                       │
│              ┌─────────────────────┐                           │
│              │   Istio Gateway     │                           │
│              │   (Port 80/443)     │                           │
│              └─────────────────────┘                           │
│                         │                                       │
│                         ▼                                       │
│              ┌─────────────────────┐                           │
│              │  Virtual Service    │                           │
│              │  (Path Routing)     │                           │
│              └─────────────────────┘                           │
│                         │                                       │
│                         ▼                                       │
│  ┌─────────────────────┼─────────────────────┐                  │
│  │                     │                     │                  │
│  ▼                     ▼                     ▼                  │
│┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│   Temporal   │  │   Temporal  │  │   Other     │               │
│   Frontend   │  │   Web UI    │  │   Services  │               │
│  (gRPC API)  │  │  (HTTP UI)  │  │             │               │
│└─────────────┘  └─────────────┘  └─────────────┘               │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Istio installed** in your cluster
2. **TLS certificate** for your domain
3. **DNS configured** to point to your Istio ingress gateway

## Deployment Steps

### 1. Deploy Temporal with Istio Configuration

```bash
# Copy the Istio configuration
cp charts/temporal/values/values.istio-path-routing.yaml my-istio-config.yaml

# Update the configuration with your values
# Edit my-istio-config.yaml

# Deploy Temporal
helm install temporal ./charts/temporal -f my-istio-config.yaml
```

### 2. Create TLS Secret

```bash
# Create TLS secret for your domain
kubectl create secret tls your-domain-tls \
  --cert=path/to/your/cert.pem \
  --key=path/to/your/key.pem \
  -n default
```

### 3. Apply Istio Gateway and Virtual Service

```bash
# Apply the Istio configurations
kubectl apply -f charts/temporal/values/values.istio-path-routing.yaml
```

## Configuration Examples

### Basic Path-Based Routing

```yaml
# Basic Virtual Service
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: temporal-basic
spec:
  hosts:
  - your-domain.com
  gateways:
  - temporal-gateway
  http:
  - match:
    - uri:
        prefix: /temporal
    route:
    - destination:
        host: temporal-web
        port:
          number: 8080
    rewrite:
      uri: /
```

### Advanced Routing with Multiple Paths

```yaml
# Advanced Virtual Service with multiple paths
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: temporal-advanced
spec:
  hosts:
  - your-domain.com
  gateways:
  - temporal-gateway
  http:
  # API routes
  - match:
    - uri:
        prefix: /temporal/api
    route:
    - destination:
        host: temporal-frontend
        port:
          number: 7233
    rewrite:
      uri: /
  
  # Web UI routes
  - match:
    - uri:
        prefix: /temporal
    route:
    - destination:
        host: temporal-web
        port:
          number: 8080
    rewrite:
      uri: /
  
  # Alternative UI path
  - match:
    - uri:
        prefix: /workflows
    route:
    - destination:
        host: temporal-web
        port:
          number: 8080
    rewrite:
      uri: /
```

### Traffic Splitting and Canary Deployments

```yaml
# Canary deployment with traffic splitting
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: temporal-canary
spec:
  hosts:
  - your-domain.com
  gateways:
  - temporal-gateway
  http:
  - match:
    - uri:
        prefix: /temporal
      headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: temporal-web-canary
        port:
          number: 8080
      weight: 10
    - destination:
        host: temporal-web
        port:
          number: 8080
      weight: 90
    rewrite:
      uri: /
```

## URL Patterns

### Common Path Configurations

| Path | Service | Description |
|------|---------|-------------|
| `/temporal` | Web UI | Main Temporal UI |
| `/temporal/api` | Frontend | gRPC API |
| `/temporal/http` | Frontend | HTTP API |
| `/workflows` | Web UI | Alternative UI path |
| `/temporal-ui` | Web UI | Another UI path |

### Access URLs

After configuration, you can access:

- **Web UI**: `https://your-domain.com/temporal`
- **API**: `https://your-domain.com/temporal/api`
- **Alternative UI**: `https://your-domain.com/workflows`

## Worker Configuration

### Update Worker Connection

When using path-based routing, workers need to connect to the correct path:

```go
// Go worker example
c, err := client.NewClient(client.Options{
    HostPort: "your-domain.com:443",  // Use HTTPS port
    Identity: "my-worker",
    Headers: map[string]string{
        "Authorization": "Bearer " + token,
    },
    // For path-based routing, you might need to configure the path
    // This depends on your specific setup
})
```

### Environment Variables

```yaml
# Worker deployment
env:
- name: TEMPORAL_SERVER_ADDRESS
  value: "your-domain.com:443"
- name: TEMPORAL_API_PATH
  value: "/temporal/api"
- name: TEMPORAL_UI_PATH
  value: "/temporal"
```

## Security Configuration

### CORS Policy

```yaml
# CORS configuration in Virtual Service
corsPolicy:
  allowOrigins:
  - exact: https://your-domain.com
  allowMethods:
  - GET
  - POST
  - PUT
  - DELETE
  - OPTIONS
  allowHeaders:
  - "DNT"
  - "User-Agent"
  - "X-Requested-With"
  - "If-Modified-Since"
  - "Cache-Control"
  - "Content-Type"
  - "Range"
  - "Authorization"
```

### Authorization Policy

```yaml
# Istio Authorization Policy
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: temporal-auth
spec:
  selector:
    matchLabels:
      app: temporal-frontend
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/temporal-worker-sa"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/temporal.api.workflowservice.v1.WorkflowService/*"]
```

## Monitoring and Troubleshooting

### Check Virtual Service Status

```bash
# Check Virtual Service
kubectl get virtualservice temporal-path-routing

# Describe Virtual Service
kubectl describe virtualservice temporal-path-routing

# Check Gateway
kubectl get gateway temporal-gateway
```

### Check Traffic Flow

```bash
# Check Istio proxy logs
kubectl logs -n istio-system -l app=istio-ingressgateway

# Check Temporal service logs
kubectl logs -l app.kubernetes.io/name=temporal -c temporal-frontend
```

### Common Issues

1. **404 Errors**: Check path matching in Virtual Service
2. **CORS Errors**: Verify CORS policy configuration
3. **TLS Errors**: Ensure TLS secret is properly configured
4. **Routing Issues**: Check Gateway selector matches ingress gateway

## Advanced Configurations

### Multiple Domains

```yaml
# Virtual Service with multiple domains
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: temporal-multi-domain
spec:
  hosts:
  - temporal.your-domain.com
  - workflows.your-domain.com
  - your-domain.com
  gateways:
  - temporal-gateway
  http:
  - match:
    - authority:
        prefix: temporal.your-domain.com
    route:
    - destination:
        host: temporal-frontend
        port:
          number: 7233
    rewrite:
      uri: /
  - match:
    - authority:
        prefix: workflows.your-domain.com
    route:
    - destination:
        host: temporal-web
        port:
          number: 8080
    rewrite:
      uri: /
```

### Rate Limiting

```yaml
# Rate limiting with EnvoyFilter
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: temporal-rate-limit
spec:
  workloadSelector:
    labels:
      app: temporal-frontend
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
      listener:
        filterChain:
          filter:
            name: envoy.filters.network.http_connection_manager
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.ratelimit
        typed_config:
          "@type": type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.ratelimit.v3.RateLimit
          value:
            domain: temporal
            rate_limit_service:
              grpc_service:
                envoy_grpc:
                  cluster_name: rate_limit_cluster
```

## Benefits of Istio Path-Based Routing

1. **Advanced Traffic Management**: Canary deployments, traffic splitting
2. **Security**: Built-in mTLS, authorization policies
3. **Observability**: Rich metrics and tracing
4. **Flexibility**: Complex routing rules and transformations
5. **Performance**: Efficient proxy-based routing

## Comparison with Ingress

| Feature | Istio Virtual Service | Ingress |
|---------|----------------------|---------|
| Path Rewriting | ✅ Native support | ⚠️ Limited |
| Traffic Splitting | ✅ Built-in | ❌ Not available |
| Canary Deployments | ✅ Easy | ❌ Complex |
| Security Policies | ✅ Rich | ⚠️ Basic |
| Observability | ✅ Excellent | ⚠️ Limited |
| Performance | ✅ High | ✅ Good |
| Complexity | ⚠️ Higher | ✅ Lower |

## Conclusion

Istio Virtual Service provides a powerful and flexible way to implement path-based routing for Temporal. It offers advanced features like traffic splitting, canary deployments, and rich security policies that are not available with traditional ingress controllers. 