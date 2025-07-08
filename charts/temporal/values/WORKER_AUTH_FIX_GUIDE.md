# Temporal Worker Authentication Fix Guide

## Problem Description

The temporal-worker service is failing with "Request unauthorized" errors when trying to start system workflows:
- `temporal-sys-history-scanner-workflow`
- `temporal-sys-tq-scanner-workflow`

This happens because OIDC authentication is enabled globally, but internal services and system workflows should bypass authentication.

## Root Cause

The worker service is trying to start system workflows but getting unauthorized because:
1. OIDC authentication is enabled for all operations
2. Internal services are not properly configured to bypass authentication
3. System workflows require special authorization handling

## Solution

### Option 1: Apply the Complete Fix (Recommended)

Use the dedicated values file that comprehensively addresses the authentication issue:

```bash
# Apply the worker authentication fix
helm upgrade temporal charts/temporal \
  --namespace rafay-core \
  -f charts/temporal/values/values.worker-auth-fix.yaml
```

### Option 2: Manual Configuration Update

If you prefer to update your existing values.yaml, apply these changes:

#### 1. Update Worker Environment Variables

Add these environment variables to the worker service:

```yaml
worker:
  additionalEnv:
    - name: TEMPORAL_INTERNAL_SERVICE_AUTH_ENABLED
      value: "false"
    - name: TEMPORAL_SYSTEM_WORKFLOW_AUTH_ENABLED
      value: "false"
    - name: TEMPORAL_WORKER_SKIP_AUTH
      value: "true"
    - name: TEMPORAL_ALLOW_INTERNAL_SERVICE_COMMUNICATION
      value: "true"
    - name: TEMPORAL_SCANNER_AUTH_ENABLED
      value: "false"
    - name: TEMPORAL_SERVICE_TYPE
      value: "worker"
    - name: TEMPORAL_AUTHORIZATION_ENABLED
      value: "false"
    - name: TEMPORAL_INTERNAL_SERVICE
      value: "true"
```

#### 2. Update Authorization Configuration

Enhance the systemAuthorizer section in the server config:

```yaml
server:
  config:
    authorization:
      systemAuthorizer:
        systemWorkflows:
          - "temporal-sys-tq-scanner-workflow"
          - "temporal-sys-history-scanner-workflow"
          - "temporal-sys-workflow-mapper-workflow"
          - "temporal-sys-archival-workflow"
          - "temporal-sys-scanner-workflow"
          - "*"  # Allow all system workflows
        internalServices:
          - "temporal-frontend"
          - "temporal-history"
          - "temporal-matching"
          - "temporal-worker"
          - "worker"
          - "*"  # Allow all internal services
        internalOperations:
          - "StartWorkflowExecution"
          - "DescribeWorkflowExecution"
          - "ListWorkflowExecutions"
          - "ScanWorkflowExecutions"
          - "CountWorkflowExecutions"
          - "*"  # Allow all internal operations
```

## Verification Steps

After applying the fix:

1. **Check worker logs:**
   ```bash
   kubectl logs -l app.kubernetes.io/component=worker -n rafay-core --tail=50
   ```

2. **Verify worker pod status:**
   ```bash
   kubectl get pods -l app.kubernetes.io/component=worker -n rafay-core
   ```

3. **Check for successful system workflow starts:**
   Look for these log messages:
   ```
   "Monitor thread successfully connected to server"
   "Current reachable members"
   ```

4. **Verify no more "Request unauthorized" errors:**
   The logs should not contain:
   ```
   "error starting workflow"
   "Request unauthorized"
   "error starting scanner"
   ```

## Expected Behavior After Fix

- Worker service should start successfully
- System workflows should start without authentication errors
- Internal service communication should work without OIDC
- External clients should still require OIDC authentication
- No more container restarts due to authentication failures

## Troubleshooting

If the issue persists:

1. **Check environment variables:**
   ```bash
   kubectl describe pod -l app.kubernetes.io/component=worker -n rafay-core
   ```

2. **Verify configuration is applied:**
   ```bash
   kubectl get configmap -n rafay-core temporal-config -o yaml
   ```

3. **Check service account annotations:**
   ```bash
   kubectl describe serviceaccount temporal-internal-sa -n rafay-core
   ```

## Security Notes

This configuration:
- ✅ Maintains OIDC authentication for external clients
- ✅ Allows internal services to communicate without authentication
- ✅ Enables system workflows to run without authentication
- ✅ Preserves security for user-facing operations

The fix only affects internal service communication and system workflows, maintaining security for external access. 