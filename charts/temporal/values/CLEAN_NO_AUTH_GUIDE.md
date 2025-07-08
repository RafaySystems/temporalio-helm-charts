# Clean No-Authentication Configuration Guide

## Problem Analysis

The temporal-worker is still getting "Request unauthorized" errors even after:
1. Setting `authorization.enabled: false`
2. Adding multiple environment variables to disable authentication
3. Configuring system authorizer with wildcard permissions

## Root Cause

The Helm template `server-configmap.yaml` always includes the authorization section if it exists in the values, regardless of the `enabled: false` setting. The template logic is:

```yaml
{{- with $server.config.authorization }}
authorization:
  {{- toYaml . | nindent 10 }}
{{- end }}
```

This means **any authorization configuration** (even with `enabled: false`) gets applied to the Temporal server.

## Solution: Complete Authentication Removal

We need to **completely remove** all authentication configuration from the Helm values to prevent the Temporal server from applying any authorization checks.

## Implementation

### Step 1: Apply the Clean No-Auth Configuration

```bash
# Apply the configuration with NO authentication at all
helm upgrade temporal charts/temporal \
  --namespace rafay-core \
  -f charts/temporal/values/values.no-auth.yaml
```

### Step 2: Verify the Configuration

Check that the authorization section is completely removed from the generated config:

```bash
# Check the generated configmap
kubectl get configmap temporal-config -n rafay-core -o yaml
```

**Expected Result:** The configmap should NOT contain any `authorization:` section.

### Step 3: Verify Worker is Working

```bash
# Check worker logs
kubectl logs -l app.kubernetes.io/component=worker -n rafay-core --tail=50
```

**Expected Success Indicators:**
- ✅ No more "Request unauthorized" errors
- ✅ Worker service starts successfully
- ✅ System workflows start without authentication issues
- ✅ No more container restarts

## What This Configuration Does

### 1. **Completely Removes Authorization Section**
```yaml
# No authorization configuration at all
# authorization: # Completely removed
```

### 2. **Removes All OIDC Environment Variables**
```yaml
server:
  additionalEnv: []  # Empty array - no auth env vars
```

### 3. **Removes All Service-Specific Auth Variables**
```yaml
worker:
  additionalEnv: []  # No worker auth vars

history:
  additionalEnv: []  # No history auth vars

matching:
  additionalEnv: []  # No matching auth vars
```

## Security Implications

⚠️ **IMPORTANT**: This configuration **completely disables all authentication** for Temporal services.

**What this means:**
- ❌ No OIDC authentication for any clients
- ❌ No authorization checks for any operations
- ❌ No authentication for internal services
- ❌ No authentication for external clients
- ❌ No authentication for system workflows

**This is a temporary measure to get the system working.**

## Verification Commands

After applying the fix:

```bash
# 1. Check configmap has no authorization section
kubectl get configmap temporal-config -n rafay-core -o yaml | grep -A 20 "authorization:"

# 2. Check worker logs
kubectl logs -l app.kubernetes.io/component=worker -n rafay-core --tail=50

# 3. Check all pods are running
kubectl get pods -n rafay-core -l app.kubernetes.io/name=temporal

# 4. Check worker pod environment variables
kubectl describe pod -l app.kubernetes.io/component=worker -n rafay-core
```

## Expected Timeline

- **Immediate**: Worker should start working within 1-2 minutes
- **Short-term**: Re-enable authentication gradually over 1-2 days
- **Long-term**: Full OIDC authentication restored with proper configuration

## Next Steps After Worker is Stable

Once the worker is running successfully:

1. **Investigate the proper way to configure Temporal authorization**
2. **Understand how the Helm template processes authorization settings**
3. **Create a proper configuration that allows internal services to bypass auth**
4. **Gradually re-enable authentication with proper internal service bypass**

## Rollback Plan

If you need to rollback:

```bash
# Rollback to the previous version
helm rollback temporal -n rafay-core

# Or apply the original configuration
helm upgrade temporal charts/temporal \
  --namespace rafay-core \
  -f charts/temporal/values.yaml
```

## Notes

- This approach **completely removes** all authentication configuration
- The root cause is in the Helm template logic, not the Temporal server itself
- We'll need to investigate the proper way to configure authorization bypass in Temporal
- External clients will need to wait until we re-enable authentication properly 