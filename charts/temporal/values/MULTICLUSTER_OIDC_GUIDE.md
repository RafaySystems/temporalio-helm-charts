# Multi-Cluster OIDC with Token Exchange Guide

This guide explains how to implement OIDC authentication for Temporal workers running in a different Kubernetes cluster than the Temporal server, using token exchange.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Cluster A                                │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │     Dex     │    │   Temporal  │    │   Token Exchange    │  │
│  │   Server    │    │   Server    │    │     Service         │  │
│  └─────────────┘    └─────────────┘    └─────────────────────┘  │
│         │                   │                       │            │
│         └───────────────────┼───────────────────────┘            │
│                             │                                    │
└─────────────────────────────┼────────────────────────────────────┘
                              │
                              │ OIDC Token Exchange
                              │
┌─────────────────────────────┼────────────────────────────────────┐
│                        Cluster B                                │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │   Workers   │    │   Workers   │    │   Workers           │  │
│  │   (App 1)   │    │   (App 2)   │    │   (App N)           │  │
│  └─────────────┘    └─────────────┘    └─────────────────────┘  │
│         │                   │                       │            │
│         └───────────────────┼───────────────────────┘            │
│                             │                                    │
└─────────────────────────────┴────────────────────────────────────┘
```

## Implementation Steps

### 1. Setup Dex in Cluster A (Temporal Cluster)

#### Install Dex with Token Exchange Support

```yaml
# dex-values.yaml
config:
  issuer: https://dex.your-domain.com
  storage:
    type: kubernetes
    config:
      inCluster: true
  
  # Enable token exchange
  oauth2:
    skipApprovalScreen: true
    alwaysShowLoginScreen: false
  
  # Configure static clients for token exchange
  staticClients:
    - id: temporal-server
      secret: your-server-secret
      name: 'Temporal Server'
      redirectURIs:
        - 'https://temporal.your-domain.com/callback'
    
    - id: temporal-worker
      secret: your-worker-secret
      name: 'Temporal Worker'
      redirectURIs:
        - 'https://worker.your-domain.com/callback'
    
    - id: token-exchange-service
      secret: your-token-exchange-secret
      name: 'Token Exchange Service'
      redirectURIs:
        - 'https://token-exchange.your-domain.com/callback'
  
  # Configure connectors (LDAP, SAML, etc.)
  connectors:
    - type: kubernetes
      id: kubernetes
      name: Kubernetes
      config:
        inCluster: true
```

#### Deploy Dex

```bash
helm repo add dex https://charts.dexidp.io
helm install dex dex/dex -f dex-values.yaml -n dex-system --create-namespace
```

### 2. Configure Temporal Server in Cluster A

#### Use the Multi-Cluster Configuration

```bash
# Copy the multi-cluster configuration
cp charts/temporal/values/values.oidc.multicluster.yaml my-multicluster-config.yaml

# Update with your specific values
# Edit my-multicluster-config.yaml

# Deploy Temporal with OIDC
helm install temporal ./charts/temporal -f my-multicluster-config.yaml
```

### 3. Deploy Token Exchange Service

#### Create Token Exchange Service

```yaml
# token-exchange-service.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: token-exchange-sa
  namespace: temporal-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: token-exchange-service
  namespace: temporal-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: token-exchange-service
  template:
    metadata:
      labels:
        app: token-exchange-service
    spec:
      serviceAccountName: token-exchange-sa
      containers:
      - name: token-exchange
        image: your-token-exchange-image:latest
        ports:
        - containerPort: 8080
        env:
        - name: DEX_ISSUER
          value: "https://dex.your-domain.com"
        - name: DEX_CLIENT_ID
          value: "token-exchange-service"
        - name: DEX_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: token-exchange-secret
              key: client_secret
        - name: TEMPORAL_SERVER_ADDRESS
          value: "temporal-frontend.temporal-system.svc.cluster.local:7233"
---
apiVersion: v1
kind: Service
metadata:
  name: token-exchange-service
  namespace: temporal-system
spec:
  selector:
    app: token-exchange-service
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
```

### 4. Configure Workers in Cluster B

#### Worker Application Configuration

```yaml
# worker-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: temporal-worker
  namespace: worker-system
spec:
  replicas: 3
  selector:
    matchLabels:
      app: temporal-worker
  template:
    metadata:
      labels:
        app: temporal-worker
    spec:
      serviceAccountName: temporal-worker-sa
      containers:
      - name: worker
        image: your-worker-image:latest
        env:
        # Temporal connection
        - name: TEMPORAL_SERVER_ADDRESS
          value: "temporal.your-domain.com:7233"
        
        # OIDC configuration
        - name: TEMPORAL_OIDC_ISSUER
          value: "https://dex.your-domain.com"
        - name: TEMPORAL_OIDC_AUDIENCE
          value: "temporal-multicluster"
        - name: TEMPORAL_OIDC_CLIENT_ID
          value: "temporal-worker"
        
        # Token exchange
        - name: TOKEN_EXCHANGE_ENDPOINT
          value: "https://token-exchange.temporal-system.svc.cluster.local:8080"
        - name: TOKEN_EXCHANGE_CLIENT_ID
          value: "temporal-worker-token-exchange"
        - name: TOKEN_EXCHANGE_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: worker-token-exchange-secret
              key: client_secret
        
        # Worker identity
        - name: WORKER_CLUSTER_ID
          value: "worker-cluster"
        - name: WORKER_NAMESPACE
          value: "worker-system"
```

#### Worker Service Account

```yaml
# worker-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: temporal-worker-sa
  namespace: worker-system
  annotations:
    # For cross-cluster authentication
    eks.amazonaws.com/role-arn: "arn:aws:iam::your-account:role/temporal-worker-role"
    # Or for Azure AD
    # azure.workload.identity/client-id: "your-worker-client-id"
    # Or for Google Cloud
    # iam.gke.io/gcp-service-account: "temporal-worker@your-project.iam.gserviceaccount.com"
```

### 5. Token Exchange Implementation

#### Token Exchange Service Code (Go Example)

```go
package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "time"

    "golang.org/x/oauth2"
    "golang.org/x/oauth2/clientcredentials"
)

type TokenExchangeRequest struct {
    SubjectToken     string `json:"subject_token"`
    SubjectTokenType string `json:"subject_token_type"`
    Audience         string `json:"audience"`
}

type TokenExchangeResponse struct {
    AccessToken  string `json:"access_token"`
    TokenType    string `json:"token_type"`
    ExpiresIn    int    `json:"expires_in"`
    RefreshToken string `json:"refresh_token,omitempty"`
}

func main() {
    http.HandleFunc("/exchange", handleTokenExchange)
    log.Fatal(http.ListenAndServe(":8080", nil))
}

func handleTokenExchange(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    var req TokenExchangeRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "Invalid request", http.StatusBadRequest)
        return
    }

    // Validate the subject token (worker's token)
    if err := validateSubjectToken(req.SubjectToken); err != nil {
        http.Error(w, "Invalid subject token", http.StatusUnauthorized)
        return
    }

    // Exchange for a new token with Temporal audience
    newToken, err := exchangeToken(req.SubjectToken, req.Audience)
    if err != nil {
        http.Error(w, "Token exchange failed", http.StatusInternalServerError)
        return
    }

    response := TokenExchangeResponse{
        AccessToken: newToken,
        TokenType:   "Bearer",
        ExpiresIn:   3600,
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

func validateSubjectToken(token string) error {
    // Validate the worker's token against Dex
    // This should verify the token signature and claims
    return nil
}

func exchangeToken(subjectToken, audience string) (string, error) {
    // Use Dex's token exchange endpoint to get a new token
    // with the appropriate audience for Temporal
    return "new-token-for-temporal", nil
}
```

### 6. Worker Authentication Flow

#### Worker Authentication Process

1. **Worker obtains initial token** from Dex (using service account or other method)
2. **Worker calls token exchange service** with the initial token
3. **Token exchange service validates** the worker's token
4. **Token exchange service requests** new token from Dex with Temporal audience
5. **Worker receives new token** and uses it to connect to Temporal server
6. **Temporal server validates** the token against Dex

#### Worker Code Example (Go)

```go
package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "time"

    "go.temporal.io/sdk/client"
)

type TokenExchangeClient struct {
    endpoint     string
    clientID     string
    clientSecret string
}

func (t *TokenExchangeClient) ExchangeToken(subjectToken, audience string) (string, error) {
    req := map[string]string{
        "subject_token":     subjectToken,
        "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
        "audience":          audience,
    }

    reqBody, _ := json.Marshal(req)
    resp, err := http.Post(t.endpoint+"/exchange", "application/json", bytes.NewBuffer(reqBody))
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()

    var tokenResp map[string]interface{}
    json.NewDecoder(resp.Body).Decode(&tokenResp)

    return tokenResp["access_token"].(string), nil
}

func main() {
    // Get initial token (from service account, environment, etc.)
    initialToken := getInitialToken()

    // Exchange for Temporal token
    tokenClient := &TokenExchangeClient{
        endpoint:     "https://token-exchange.temporal-system.svc.cluster.local:8080",
        clientID:     "temporal-worker",
        clientSecret: "your-secret",
    }

    temporalToken, err := tokenClient.ExchangeToken(initialToken, "temporal-multicluster")
    if err != nil {
        log.Fatal(err)
    }

    // Connect to Temporal with the exchanged token
    c, err := client.NewClient(client.Options{
        HostPort:  "temporal.your-domain.com:7233",
        Identity:  "worker-cluster-worker",
        Headers: map[string]string{
            "Authorization": "Bearer " + temporalToken,
        },
    })
    if err != nil {
        log.Fatal(err)
    }
    defer c.Close()

    // Start worker
    w := worker.New(c, "your-task-queue", worker.Options{})
    w.RegisterWorkflow(YourWorkflow)
    w.RegisterActivity(YourActivity)
    w.Run(worker.InterruptCh())
}
```

## Security Considerations

### 1. Network Security
- Use network policies to restrict cross-cluster communication
- Implement TLS for all token exchange communications
- Use service mesh (Istio, Linkerd) for additional security

### 2. Token Security
- Implement token rotation
- Use short-lived tokens
- Validate token claims thoroughly
- Implement token revocation

### 3. Access Control
- Use RBAC to control access to token exchange service
- Implement audit logging for all token exchanges
- Monitor for suspicious token exchange patterns

## Monitoring and Troubleshooting

### 1. Metrics
```yaml
# Add to your monitoring configuration
metrics:
  - name: token_exchange_requests_total
    type: counter
    labels:
      - client_id
      - status
      - cluster_id
  
  - name: token_exchange_duration_seconds
    type: histogram
    labels:
      - client_id
      - status
```

### 2. Logging
```yaml
# Configure structured logging
logging:
  level: info
  format: json
  fields:
    - name: cluster_id
      value: "worker-cluster"
    - name: service
      value: "temporal-worker"
```

### 3. Health Checks
```yaml
# Add health check endpoints
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Alternative Approaches

### 1. Direct Dex Access
If network connectivity allows, workers can directly obtain tokens from Dex:

```yaml
# Worker configuration with direct Dex access
env:
- name: DEX_ISSUER
  value: "https://dex.your-domain.com"
- name: DEX_CLIENT_ID
  value: "temporal-worker"
- name: DEX_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: dex-worker-secret
      key: client_secret
```

### 2. Service Mesh Token Exchange
Use service mesh (Istio) for automatic token exchange:

```yaml
# Istio configuration for automatic token exchange
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: temporal-worker-auth
spec:
  selector:
    matchLabels:
      app: temporal-frontend
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/worker-system/sa/temporal-worker-sa"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/temporal.api.workflowservice.v1.WorkflowService/*"]
```

### 3. Cloud Provider Token Exchange
Use cloud provider-specific token exchange:

```yaml
# AWS IAM token exchange
env:
- name: AWS_ROLE_ARN
  value: "arn:aws:iam::your-account:role/temporal-worker-role"
- name: AWS_WEB_IDENTITY_TOKEN_FILE
  value: "/var/run/secrets/eks.amazonaws.com/serviceaccount/token"

# Azure AD token exchange
env:
- name: AZURE_CLIENT_ID
  value: "your-worker-client-id"
- name: AZURE_TENANT_ID
  value: "your-tenant-id"
```

## Conclusion

This multi-cluster OIDC setup with token exchange provides a secure and scalable way to authenticate Temporal workers across different Kubernetes clusters. The token exchange pattern ensures that workers can obtain appropriate tokens for Temporal server access while maintaining security boundaries between clusters. 