# Temporal Frontend Proxy

A Go-based HTTP proxy that validates JWT tokens from bearer headers and forwards requests to the Temporal frontend service. This proxy acts as an authentication layer for external workers connecting to your Temporal cluster.

## 🏗️ Architecture

```
External Worker → JWT Token → Go Proxy → Temporal Frontend
```

The proxy:
1. **Validates JWT tokens** using OIDC/JWKS
2. **Extracts user claims** (subject, groups, email)
3. **Forwards requests** to Temporal frontend with proper headers
4. **Provides health checks** and monitoring endpoints

## 🚀 Quick Start

### Prerequisites

- Go 1.21+
- Docker
- Make
- Access to your Temporal cluster
- OIDC provider (Dex) configured

### Local Development

1. **Clone and setup**:
   ```bash
   cd go-frontendproxy
   make deps
   ```

2. **Build and run locally**:
   ```bash
   make build
   make run
   ```

3. **Test the proxy**:
   ```bash
   chmod +x test-proxy.sh
   ./test-proxy.sh
   ```

### Docker Build

1. **Build Docker image**:
   ```bash
   make docker-build
   ```

2. **Run with Docker**:
   ```bash
   make docker-run
   ```

3. **Run with custom configuration**:
   ```bash
   make docker-run-custom \
     TEMPORAL_URL=http://your-temporal-frontend:7233 \
     OIDC_ISSUER=https://your-dex-url \
     OIDC_CLIENT_ID=your-client-id
   ```

## ⚙️ Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8081` | Port to listen on |
| `TEMPORAL_FRONTEND_URL` | `http://temporalio-frontend.rafay-core.svc.cluster.local:7233` | Temporal frontend service URL |
| `OIDC_ISSUER` | `https://console.gaap.dev.rafay-edge.net/dex` | OIDC issuer URL |
| `OIDC_CLIENT_ID` | `temporal-server` | OIDC client ID |
| `LOG_LEVEL` | `info` | Log level (debug, info, warn, error) |
| `ENABLE_CORS` | `true` | Enable CORS headers |
| `REQUEST_TIMEOUT` | `30s` | HTTP request timeout |
| `TOKEN_VALIDATION_TIMEOUT` | `5s` | JWT validation timeout |

### Example Configuration

```bash
export PORT=8081
export TEMPORAL_FRONTEND_URL=http://temporalio-frontend.rafay-core.svc.cluster.local:7233
export OIDC_ISSUER=https://console.gaap.dev.rafay-edge.net/dex
export OIDC_CLIENT_ID=temporal-server
export LOG_LEVEL=debug
export ENABLE_CORS=true
```

## 🐳 Kubernetes Deployment

### Deploy to Kubernetes

1. **Build and push the image**:
   ```bash
   make build-and-push
   ```

2. **Deploy to cluster**:
   ```bash
   kubectl apply -f k8s-deployment.yaml
   ```

3. **Check deployment status**:
   ```bash
   kubectl get pods -n rafay-core -l app=temporal-frontend-proxy
   kubectl logs -n rafay-core -l app=temporal-frontend-proxy
   ```

### Update Istio Virtual Service

Add this route to your Istio Virtual Service for external worker traffic:

```yaml
- match:
  - uri:
      prefix: "/temporal-proxy"
  route:
  - destination:
      host: temporal-frontend-proxy.rafay-core.svc.cluster.local
      port:
        number: 8081
```

## 🔧 API Endpoints

### Health Check
```bash
GET /health
```

Response:
```json
{
  "success": true,
  "message": "Temporal Frontend Proxy is healthy",
  "data": {
    "timestamp": "2024-01-01T00:00:00Z",
    "version": "1.0.0",
    "config": {
      "temporal_frontend_url": "http://temporalio-frontend.rafay-core.svc.cluster.local:7233",
      "oidc_issuer": "https://console.gaap.dev.rafay-edge.net/dex",
      "oidc_client_id": "temporal-server"
    }
  }
}
```

### OIDC Discovery
```bash
GET /.well-known/openid_configuration
```

Forwards to the OIDC issuer's discovery endpoint.

### Temporal API Proxy
```bash
GET /api/v1/cluster/info
POST /api/v1/namespaces/default/workflows
# ... all Temporal API endpoints
```

**Headers required:**
- `Authorization: Bearer <JWT_TOKEN>`
- `Content-Type: application/json`

## 🔐 Token Validation

The proxy validates JWT tokens by:

1. **Extracting token** from `Authorization: Bearer <token>` header
2. **Verifying signature** using OIDC JWKS endpoint
3. **Validating claims**:
   - `iss` (issuer) matches configured OIDC issuer
   - `aud` (audience) includes configured client ID
   - Token is not expired
4. **Extracting user information**:
   - `sub` (subject) - user ID
   - `email` - user email
   - `groups` - user groups/roles

### Example Token Claims

```json
{
  "iss": "https://console.gaap.dev.rafay-edge.net/dex",
  "sub": "user123",
  "aud": ["temporal-server"],
  "email": "user@example.com",
  "groups": ["temporal-users", "developers"],
  "exp": 1640995200,
  "iat": 1640908800
}
```

## 🧪 Testing

### Manual Testing

1. **Get a JWT token** from your OIDC provider
2. **Test the proxy**:
   ```bash
   curl -X GET "http://localhost:8081/api/v1/cluster/info" \
     -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     -H "Content-Type: application/json"
   ```

### Automated Testing

Run the test script:
```bash
./test-proxy.sh
```

The script tests:
- ✅ Health endpoint
- ✅ OIDC discovery
- ✅ Token validation
- ✅ API forwarding
- ✅ Unauthorized request rejection
- ✅ Invalid token rejection

## 📊 Monitoring

### Health Checks

The proxy provides health checks at `/health` for Kubernetes liveness and readiness probes.

### Logging

The proxy logs:
- Request details (method, path, user, groups)
- Token validation results
- Forwarding requests
- Errors and failures

Example logs:
```
2024/01/01 12:00:00 🚀 Temporal Frontend Proxy starting on port 8081
2024/01/01 12:00:01 Request: GET /api/v1/cluster/info from 192.168.1.100 (user: user123, groups: [temporal-users developers])
2024/01/01 12:00:01 Forwarding: GET /api/v1/cluster/info -> http://temporalio-frontend.rafay-core.svc.cluster.local:7233/api/v1/cluster/info
```

### Metrics

The proxy exposes Prometheus metrics (when implemented) for:
- Request count by status code
- Token validation success/failure rates
- Response times
- Active connections

## 🔒 Security

### Security Features

- **JWT validation** using OIDC JWKS
- **Non-root container** execution
- **Read-only filesystem** in production
- **Dropped capabilities** for security
- **TLS support** for HTTPS connections
- **CORS configuration** for web clients

### Best Practices

1. **Use HTTPS** in production
2. **Rotate JWT tokens** regularly
3. **Monitor token validation** failures
4. **Implement rate limiting** if needed
5. **Use network policies** to restrict access
6. **Audit logs** regularly

## 🛠️ Development

### Available Make Targets

```bash
make help                    # Show all available targets
make build                   # Build the application
make test                    # Run tests
make deps                    # Download dependencies
make run                     # Run locally
make dev                     # Run with hot reload (requires air)
make docker-build           # Build Docker image
make docker-push            # Push to registry
make docker-run             # Run with Docker
make fmt                     # Format code
make lint                    # Lint code
make security-scan          # Security scan
```

### Adding New Features

1. **Add new endpoints** in `setupRoutes()`
2. **Extend configuration** in `Config` struct
3. **Add environment variables** in `loadConfig()`
4. **Update tests** and documentation

## 🚨 Troubleshooting

### Common Issues

1. **Token validation fails**:
   - Check OIDC issuer URL
   - Verify client ID configuration
   - Check token expiration
   - Validate token signature

2. **Proxy can't reach Temporal**:
   - Check network connectivity
   - Verify Temporal frontend URL
   - Check Kubernetes service endpoints

3. **Health check fails**:
   - Check proxy logs
   - Verify port configuration
   - Check resource limits

### Debug Mode

Enable debug logging:
```bash
export LOG_LEVEL=debug
make run
```

### Log Analysis

```bash
# Check proxy logs
kubectl logs -n rafay-core -l app=temporal-frontend-proxy --tail=100

# Check Temporal frontend logs
kubectl logs -n rafay-core -l app.kubernetes.io/component=frontend --tail=50

# Check OIDC provider logs
kubectl logs -n dex-system -l app=dex --tail=50
```

## 📝 License

This project is part of the Rafay Systems GAAP platform.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📞 Support

For support and questions:
- Check the troubleshooting section
- Review the logs
- Contact the Rafay Systems team 