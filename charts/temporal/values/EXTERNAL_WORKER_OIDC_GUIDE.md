# External Worker OIDC Authentication Guide

## Overview

This guide covers setting up external Temporal workers that connect to your Temporal cluster using OIDC exchange tokens for authentication.

## Architecture

```
External Worker → Exchange Token → Dex OIDC → Temporal Cluster
```

## Prerequisites

1. ✅ **Temporal cluster running** with OIDC enabled
2. ✅ **Dex OIDC provider** configured and working
3. ✅ **External worker** that needs to connect to Temporal
4. ✅ **Service account** for the external worker

## Step 1: Configure Temporal for External Worker Authentication

### Update Temporal Configuration

Add these settings to your `values.yaml`:

```yaml
server:
  additionalEnv:
    # Enable OIDC for external clients
    - name: TEMPORAL_OIDC_ENABLED
      value: "true"
    - name: TEMPORAL_OIDC_ISSUER
      value: "https://console.gaap.dev.rafay-edge.net/dex"
    - name: TEMPORAL_OIDC_AUDIENCE
      value: "temporal-server"
    - name: TEMPORAL_OIDC_CLIENT_ID
      value: "temporal-server"
    # Enable authorization for external workers
    - name: TEMPORAL_AUTHORIZATION_ENABLED
      value: "true"
    # Keep internal services bypassing auth
    - name: TEMPORAL_INTERNAL_SERVICE_AUTH_ENABLED
      value: "false"
    - name: TEMPORAL_SYSTEM_WORKFLOW_AUTH_ENABLED
      value: "false"
  config:
    authorization:
      enabled: true
      jwtKeyProvider:
        keySourceURIs:
          - https://console.gaap.dev.rafay-edge.net/dex/keys
        refreshInterval: 1m
      permissionsClaimName: groups
      authorizer: default
      claimMapper: default
```

### Frontend Service Configuration

```yaml
server:
  frontend:
    additionalEnv:
      # Enable OIDC for external clients
      - name: TEMPORAL_OIDC_ENABLED
        value: "true"
      - name: TEMPORAL_OIDC_ISSUER
        value: "https://console.gaap.dev.rafay-edge.net/dex"
      - name: TEMPORAL_OIDC_AUDIENCE
        value: "temporal-server"
      - name: TEMPORAL_OIDC_CLIENT_ID
        value: "temporal-server"
      # Enable authorization
      - name: TEMPORAL_AUTHORIZATION_ENABLED
        value: "true"
```

## Step 2: Create Dex Client for External Worker

### Add Client to Dex Configuration

Add this client to your Dex configuration:

```yaml
staticClients:
  - id: external-worker-client
    secret: your-secret-here
    name: "External Worker Client"
    redirectURIs:
      - "urn:ietf:wg:oauth:2.0:oob"  # For token exchange
    trustedPeers:
      - temporal-server
```

### Or via Dex API (if using API)

```bash
curl -X POST "https://console.gaap.dev.rafay-edge.net/dex/api/v1/clients" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -d '{
    "id": "external-worker-client",
    "secret": "your-secret-here",
    "name": "External Worker Client",
    "redirectURIs": ["urn:ietf:wg:oauth:2.0:oob"],
    "trustedPeers": ["temporal-server"]
  }'
```

## Step 3: Create Service Account for External Worker

### Create Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-worker-sa
  namespace: rafay-core
  annotations:
    temporal.io/external-worker: "true"
    temporal.io/worker-groups: "external-workers"
```

### Create RBAC for Service Account

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: temporal-external-worker
rules:
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["temporal.io"]
    resources: ["workflows", "activities"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: temporal-external-worker-binding
subjects:
  - kind: ServiceAccount
    name: external-worker-sa
    namespace: rafay-core
roleRef:
  kind: ClusterRole
  name: temporal-external-worker
  apiGroup: rbac.authorization.k8s.io
```

## Step 4: External Worker Configuration

### Worker Code Example (Go)

```go
package main

import (
    "context"
    "fmt"
    "log"
    "time"

    "go.temporal.io/sdk/client"
    "golang.org/x/oauth2"
    "golang.org/x/oauth2/clientcredentials"
)

func main() {
    // OAuth2 configuration for token exchange
    oauth2Config := &oauth2.Config{
        ClientID:     "external-worker-client",
        ClientSecret: "your-secret-here",
        TokenURL:     "https://console.gaap.dev.rafay-edge.net/dex/token",
        Scopes:       []string{"openid", "profile", "email", "groups"},
    }

    // Get token using client credentials flow
    tokenSource := oauth2Config.TokenSource(context.Background(), nil)
    token, err := tokenSource.Token()
    if err != nil {
        log.Fatalf("Failed to get token: %v", err)
    }

    // Create Temporal client with OAuth2 token
    temporalClient, err := client.NewClient(client.Options{
        HostPort:  "ops-console.gaap.dev.rafay-edge.net:443",
        Namespace: "default",
        Identity:  "external-worker-1",
        ConnectionOptions: client.ConnectionOptions{
            TLS: &client.TLSConfig{
                ServerName: "ops-console.gaap.dev.rafay-edge.net",
            },
            Headers: map[string]string{
                "Authorization": "Bearer " + token.AccessToken,
            },
        },
    })
    if err != nil {
        log.Fatalf("Failed to create Temporal client: %v", err)
    }
    defer temporalClient.Close()

    // Your worker logic here
    worker := worker.New(temporalClient, "external-worker-task-queue", worker.Options{})
    
    // Register workflows and activities
    worker.RegisterWorkflow(YourWorkflow)
    worker.RegisterActivity(YourActivity)

    // Start worker
    err = worker.Run(worker.InterruptCh())
    if err != nil {
        log.Fatalf("Failed to start worker: %v", err)
    }
}

func YourWorkflow(ctx workflow.Context, input string) (string, error) {
    // Your workflow implementation
    return "Hello from external worker: " + input, nil
}

func YourActivity(ctx context.Context, input string) (string, error) {
    // Your activity implementation
    return "Activity result: " + input, nil
}
```

### Worker Code Example (Python)

```python
import asyncio
from temporalio.client import Client
from temporalio.worker import Worker
from temporalio import workflow, activity
import requests

# OAuth2 token exchange
def get_access_token():
    token_url = "https://console.gaap.dev.rafay-edge.net/dex/token"
    data = {
        "grant_type": "client_credentials",
        "client_id": "external-worker-client",
        "client_secret": "your-secret-here",
        "scope": "openid profile email groups"
    }
    
    response = requests.post(token_url, data=data)
    response.raise_for_status()
    return response.json()["access_token"]

@workflow.defn
class YourWorkflow:
    @workflow.run
    async def run(self, input: str) -> str:
        result = await workflow.execute_activity(
            your_activity, input, start_to_close_timeout=timedelta(seconds=10)
        )
        return f"Hello from external worker: {result}"

@activity.defn
async def your_activity(input: str) -> str:
    return f"Activity result: {input}"

async def main():
    # Get OAuth2 token
    access_token = get_access_token()
    
    # Create client with token
    client = await Client.connect(
        "ops-console.gaap.dev.rafay-edge.net:443",
        namespace="default",
        identity="external-worker-1",
        tls=True,
        headers={"Authorization": f"Bearer {access_token}"}
    )
    
    # Create worker
    worker = Worker(
        client,
        task_queue="external-worker-task-queue",
        workflows=[YourWorkflow],
        activities=[your_activity]
    )
    
    # Start worker
    await worker.run()

if __name__ == "__main__":
    asyncio.run(main())
```

## Step 5: Token Exchange Flow

### 1. Client Credentials Flow

```bash
# Get access token using client credentials
curl -X POST "https://console.gaap.dev.rafay-edge.net/dex/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=external-worker-client" \
  -d "client_secret=your-secret-here" \
  -d "scope=openid profile email groups"
```

### 2. Use Token with Temporal

```bash
# Use the token to connect to Temporal
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporalui/api/v1/cluster/info" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json"
```

## Step 6: Security Considerations

### 1. Token Management

- **Rotate secrets regularly**
- **Use short-lived tokens** (configure in Dex)
- **Implement token refresh logic** in workers
- **Store secrets securely** (use Kubernetes secrets)

### 2. Network Security

- **Use TLS** for all connections
- **Implement network policies** to restrict access
- **Use service mesh** for additional security

### 3. RBAC Configuration

```yaml
# Example RBAC for specific namespaces
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: temporal-worker-role
  namespace: default
rules:
  - apiGroups: ["temporal.io"]
    resources: ["workflows"]
    verbs: ["get", "list", "watch", "create", "update"]
```

## Step 7: Testing

### Test Token Exchange

```bash
# Test token exchange
TOKEN_RESPONSE=$(curl -s -X POST "https://console.gaap.dev.rafay-edge.net/dex/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=external-worker-client" \
  -d "client_secret=your-secret-here" \
  -d "scope=openid profile email groups")

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.access_token')

# Test Temporal API with token
curl -X GET "https://ops-console.gaap.dev.rafay-edge.net/temporalui/api/v1/cluster/info" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json"
```

### Test Worker Connection

```bash
# Run your worker and verify it connects
python your_worker.py

# Check Temporal logs for successful authentication
kubectl logs -l app.kubernetes.io/component=frontend -n rafay-core --tail=50
```

## Troubleshooting

### Common Issues

1. **Token Exchange Fails**
   - Check Dex client configuration
   - Verify client credentials
   - Check Dex logs

2. **Temporal Rejects Token**
   - Verify OIDC issuer URL
   - Check JWT key provider configuration
   - Verify audience and client ID

3. **Worker Can't Connect**
   - Check network connectivity
   - Verify TLS configuration
   - Check Temporal service status

### Debug Commands

```bash
# Check Dex logs
kubectl logs -l app=dex -n dex-system --tail=50

# Check Temporal frontend logs
kubectl logs -l app.kubernetes.io/component=frontend -n rafay-core --tail=50

# Test token validation
curl -X GET "https://console.gaap.dev.rafay-edge.net/dex/keys"

# Check service endpoints
kubectl get endpoints -n rafay-core | grep temporal
```

## Next Steps

1. **Implement the configuration** in your Temporal cluster
2. **Create the Dex client** for your external worker
3. **Update your worker code** to use OAuth2 tokens
4. **Test the connection** and verify authentication works
5. **Monitor logs** for any authentication issues

Let me know when you're ready to implement any specific part of this setup! 