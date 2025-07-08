# OIDC Configuration for Temporal Workers

This directory contains configuration examples for enabling OpenID Connect (OIDC) authentication for workers connecting to the Temporal server.

## Overview

OIDC support allows Temporal workers to authenticate using JWT tokens issued by an OIDC provider (like Auth0, Keycloak, Okta, etc.). This provides a secure, standards-based authentication mechanism for your Temporal workflows.

## Quick Start

1. **Choose your OIDC provider** and copy the appropriate example file:
   ```bash
   # For Auth0
   cp values.oidc.auth0.yaml my-oidc-config.yaml
   
   # For Keycloak
cp values.oidc.keycloak.yaml my-oidc-config.yaml

# For Dex
cp values.oidc.dex.yaml my-oidc-config.yaml
   
   # For generic OIDC
   cp values.oidc.yaml my-oidc-config.yaml
   ```

2. **Update the configuration** with your OIDC provider details:
   - Replace `your-oidc-provider` with your actual OIDC provider URL
   - Update the `permissionsClaimName` to match your JWT token structure
   - Configure any additional environment variables

3. **Deploy with OIDC enabled**:
   ```bash
   helm install temporal ./charts/temporal -f my-oidc-config.yaml
   ```

## Configuration Files

### `values.oidc.yaml`
Generic OIDC configuration template with comprehensive examples and documentation.

### `values.oidc.auth0.yaml`
Specific configuration for Auth0 OIDC provider.

### `values.oidc.keycloak.yaml`
Specific configuration for Keycloak OIDC provider.

### `values.oidc.dex.yaml`
Specific configuration for Dex OIDC provider.

## Key Configuration Parameters

### JWT Key Provider
```yaml
jwtKeyProvider:
  keySourceURIs:
    - "https://your-oidc-provider/.well-known/jwks.json"
  refreshInterval: 1m
```

- `keySourceURIs`: List of JWKS endpoints from your OIDC provider
- `refreshInterval`: How often to refresh the JWKS (default: 1m)

### Permissions Claim
```yaml
permissionsClaimName: permissions
```

This should match the claim name in your JWT tokens that contains the permissions/roles.

### Common OIDC Providers

| Provider | JWKS Endpoint | Typical Claim Name |
|----------|---------------|-------------------|
| Auth0 | `https://your-domain.auth0.com/.well-known/jwks.json` | `permissions` |
| Keycloak | `https://your-server/auth/realms/your-realm/protocol/openid-connect/certs` | `realm_access.roles` |
| Dex | `https://your-dex-server/.well-known/jwks.json` | `groups` |
| Okta | `https://your-domain.okta.com/oauth2/v1/keys` | `permissions` |
| Azure AD | `https://login.microsoftonline.com/your-tenant-id/discovery/v2.0/keys` | `roles` |
| Google | `https://www.googleapis.com/oauth2/v1/certs` | `permissions` |

## Dex-Specific Configuration

### Dex Setup
Dex is a federated OpenID Connect provider that can act as a hub to connect many different identity providers. For Temporal workers, Dex provides:

1. **Kubernetes Integration**: Dex can use Kubernetes service accounts for authentication
2. **Multiple Identity Providers**: Connect to LDAP, SAML, OAuth2, etc.
3. **Custom Claims**: Configure custom groups and permissions

### Dex Configuration Steps

1. **Install Dex** in your cluster:
   ```bash
   # Using Helm
   helm repo add dex https://charts.dexidp.io
   helm install dex dex/dex -f dex-values.yaml
   ```

2. **Configure Dex** with your identity providers:
   ```yaml
   # dex-values.yaml
   config:
     issuer: https://dex.your-domain.com
     storage:
       type: kubernetes
       config:
         inCluster: true
     connectors:
       - type: kubernetes
         id: kubernetes
         name: Kubernetes
         config:
           inCluster: true
   ```

3. **Create a Temporal client** in Dex:
   ```yaml
   # Add to Dex config
   staticClients:
     - id: temporal-client
       secret: your-client-secret
       name: 'Temporal'
       redirectURIs:
         - 'https://temporal.your-domain.com/callback'
   ```

4. **Use the Dex configuration** with Temporal:
   ```bash
   helm install temporal ./charts/temporal -f values.oidc.dex.yaml
   ```

### Dex with Kubernetes Service Accounts
For workers running in Kubernetes, you can use Dex's Kubernetes connector:

```yaml
server:
  serviceAccount:
    create: true
    name: temporal-worker-sa
    extraAnnotations:
      dex.coreos.com/automount-service-account-token: "true"
      dex.coreos.com/oauth2-redirecturi: "https://dex.your-domain.com/callback"
```

## Worker Configuration

### Environment Variables
Workers can be configured with OIDC-specific environment variables:

```yaml
server:
  worker:
    additionalEnv:
      - name: TEMPORAL_WORKER_OIDC_TOKEN
        valueFrom:
          secretKeyRef:
            name: worker-oidc-secret
            key: token
```

### Token Management
Workers need to obtain and refresh JWT tokens from your OIDC provider. Common approaches:

1. **Service Account Tokens** (Kubernetes)
2. **Workload Identity** (Cloud providers)
3. **Client Credentials Flow**
4. **Manual token injection**

## Security Considerations

### TLS Configuration
Enable TLS for secure communication with your OIDC provider:

```yaml
server:
  config:
    tls:
      frontend:
        server:
          certFile: /path/to/cert/file
          keyFile: /path/to/key/file
          requireClientAuth: true
```

### Certificate Management
Mount OIDC provider certificates if needed:

```yaml
server:
  additionalVolumes:
    - name: oidc-certs
      secret:
        secretName: oidc-certificates
  additionalVolumeMounts:
    - name: oidc-certs
      mountPath: /etc/temporal/oidc/certs
      readOnly: true
```

## Testing OIDC Configuration

### 1. Verify JWKS Endpoint
Test that your JWKS endpoint is accessible:
```bash
curl https://your-oidc-provider/.well-known/jwks.json
```

### 2. Check JWT Token Structure
Decode a JWT token to verify the claim structure:
```bash
# Install jwt-cli or use online tools
jwt decode your-jwt-token
```

### 3. Test Worker Connection
Deploy a simple worker and verify it can connect with OIDC authentication.

## Troubleshooting

### Common Issues

1. **JWKS Endpoint Unreachable**
   - Verify network connectivity
   - Check firewall rules
   - Ensure TLS certificates are valid

2. **Invalid JWT Token**
   - Verify token issuer matches configuration
   - Check token audience
   - Ensure token hasn't expired

3. **Permission Denied**
   - Verify `permissionsClaimName` matches JWT structure
   - Check that required permissions are present in token
   - Review authorization configuration

### Debug Logs
Enable debug logging to troubleshoot OIDC issues:

```yaml
server:
  config:
    logLevel: "debug,info"
```

### Metrics
Monitor OIDC authentication metrics:

```yaml
server:
  metrics:
    tags:
      oidc_enabled: "true"
      oidc_provider: "your-provider-name"
```

## Advanced Configuration

### Custom Authorizers
Implement custom authorization logic:

```yaml
server:
  config:
    authorization:
      authorizer: custom
      customAuthorizer:
        plugin: "your-custom-authorizer-plugin"
```

### Namespace-Specific OIDC
Configure different OIDC settings per namespace:

```yaml
server:
  config:
    namespaces:
      namespace:
        - name: default
          authorization:
            jwtKeyProvider:
              keySourceURIs:
                - "https://default-oidc-provider/.well-known/jwks.json"
        - name: secure
          authorization:
            jwtKeyProvider:
              keySourceURIs:
                - "https://secure-oidc-provider/.well-known/jwks.json"
```

## References

- [Temporal Security Documentation](https://docs.temporal.io/self-hosted-guide/security#authorization)
- [OIDC Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [JWT Specification](https://tools.ietf.org/html/rfc7519)
- [JWKS Specification](https://tools.ietf.org/html/rfc7517) 