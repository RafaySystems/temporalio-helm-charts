# Temporary Authentication Disable Guide

## Problem Status

The temporal-worker is still experiencing "Request unauthorized" errors even after applying comprehensive authentication bypass configurations. This indicates that the Temporal server's authorization system is not properly recognizing the environment variables or configuration settings.

## Temporary Solution

We need to **temporarily disable OIDC authentication completely** to get the worker service running, then gradually re-enable it with proper configuration.

## Implementation

### Step 1: Apply the Temporary Fix

```bash
# Apply the configuration that disables OIDC completely
helm upgrade temporal charts/temporal \
  --namespace rafay-core \
  -f charts/temporal/values/values.no-oidc-internal.yaml
```

### Step 2: Verify Worker is Working

After applying the fix, check the worker logs:

```bash
kubectl logs -l app.kubernetes.io/component=worker -n rafay-core --tail=50
```

**Expected Success Indicators:**
- ✅ No more "Request unauthorized" errors
- ✅ Worker service starts successfully
- ✅ System workflows start without authentication issues
- ✅ No more container restarts

### Step 3: Verify All Services are Running

```bash
kubectl get pods -n rafay-core -l app.kubernetes.io/name=temporal
```

All pods should be in `Running` state with `Ready: 1/1`.

## What This Configuration Does

### 1. **Completely Disables Authorization**
```yaml
authorization:
  enabled: false
```

### 2. **Disables OIDC Globally**
```yaml
- name: TEMPORAL_OIDC_ENABLED
  value: "false"
```

### 3. **Disables All Authentication Flags**
- `TEMPORAL_AUTHORIZATION_ENABLED: "false"`
- `TEMPORAL_INTERNAL_SERVICE_AUTH_ENABLED: "false"`
- `TEMPORAL_SYSTEM_WORKFLOW_AUTH_ENABLED: "false"`
- `TEMPORAL_WORKER_SKIP_AUTH: "true"`

## Security Implications

⚠️ **IMPORTANT**: This configuration **temporarily disables all authentication** for Temporal services.

**What this means:**
- ❌ No OIDC authentication for external clients
- ❌ No authorization checks for any operations
- ❌ Internal services can communicate without authentication
- ❌ System workflows can run without authentication

**This is a temporary measure to get the system working.**

## Next Steps After Worker is Stable

Once the worker is running successfully, we can gradually re-enable authentication:

### Phase 1: Re-enable Authorization with Internal Bypass
```yaml
authorization:
  enabled: true
  systemAuthorizer:
    systemWorkflows:
      - "*"
    internalServices:
      - "*"
    internalOperations:
      - "*"
```

### Phase 2: Re-enable OIDC for External Clients Only
```yaml
- name: TEMPORAL_OIDC_ENABLED
  value: "true"
```

### Phase 3: Fine-tune Authentication Rules
Gradually restrict the wildcard permissions to specific services and operations.

## Rollback Plan

If you need to rollback to the previous configuration:

```bash
# Rollback to the previous version
helm rollback temporal -n rafay-core

# Or apply the original configuration
helm upgrade temporal charts/temporal \
  --namespace rafay-core \
  -f charts/temporal/values.yaml
```

## Monitoring

After applying this fix, monitor:

1. **Worker logs** for successful startup
2. **System workflow execution** without errors
3. **Service communication** between Temporal components
4. **External client access** (will be disabled during this phase)

## Expected Timeline

- **Immediate**: Worker should start working within 1-2 minutes
- **Short-term**: Re-enable authentication gradually over 1-2 days
- **Long-term**: Full OIDC authentication restored with proper internal bypass

## Notes

- This is a **temporary workaround** to get the system operational
- The root cause appears to be in how Temporal processes the authorization configuration
- We'll need to investigate the proper way to configure internal service authentication bypass
- External clients will need to wait until we re-enable OIDC authentication 