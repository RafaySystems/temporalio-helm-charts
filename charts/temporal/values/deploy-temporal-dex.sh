#!/bin/bash

# Complete Temporal + Dex Deployment Script
# This script deploys a production-ready Temporal setup with Dex OIDC

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "WARNING" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    elif [ "$status" = "INFO" ]; then
        echo -e "${BLUE}ℹ${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "=== Checking Prerequisites ==="
if command_exists kubectl; then
    print_status "OK" "kubectl is available"
else
    print_status "ERROR" "kubectl is not installed"
    exit 1
fi

if command_exists helm; then
    print_status "OK" "helm is available"
else
    print_status "ERROR" "helm is not installed"
    exit 1
fi

# Check cluster connectivity
if kubectl cluster-info >/dev/null 2>&1; then
    print_status "OK" "Kubernetes cluster is accessible"
else
    print_status "ERROR" "Cannot connect to Kubernetes cluster"
    exit 1
fi

echo ""

# Configuration
NAMESPACE_DEX="dex-system"
NAMESPACE_TEMPORAL="temporal-system"
CONFIG_FILE="complete-temporal-dex-setup.yaml"
HELM_CHART="./charts/temporal"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_status "ERROR" "Configuration file $CONFIG_FILE not found"
    exit 1
fi

echo "=== Starting Deployment ==="
print_status "INFO" "Deploying Temporal + Dex to namespaces: $NAMESPACE_DEX, $NAMESPACE_TEMPORAL"

# Step 1: Create namespaces
echo ""
echo "=== Step 1: Creating Namespaces ==="
kubectl create namespace $NAMESPACE_DEX --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $NAMESPACE_TEMPORAL --dry-run=client -o yaml | kubectl apply -f -
print_status "OK" "Namespaces created"

# Step 2: Apply Dex configuration
echo ""
echo "=== Step 2: Deploying Dex ==="
print_status "INFO" "Applying Dex configuration..."

# Extract and apply Dex resources
kubectl apply -f <(awk '/^---$/{p=0} /^# =============================================================================$/{p=0} /^# DEX CONFIGURATION$/{p=1} p' $CONFIG_FILE)

print_status "OK" "Dex configuration applied"

# Step 3: Wait for Dex to be ready
echo ""
echo "=== Step 3: Waiting for Dex to be Ready ==="
print_status "INFO" "Waiting for Dex pods to be ready..."

kubectl wait --for=condition=ready pod -l app=dex -n $NAMESPACE_DEX --timeout=300s
print_status "OK" "Dex is ready"

# Step 4: Test Dex endpoints
echo ""
echo "=== Step 4: Testing Dex Endpoints ==="
print_status "INFO" "Testing Dex OIDC endpoints..."

# Test OIDC configuration
if kubectl run test-oidc --image=curlimages/curl -i --rm --restart=Never -n $NAMESPACE_DEX -- \
  curl -s http://dex.$NAMESPACE_DEX.svc.cluster.local:5556/.well-known/openid_configuration | grep -q "issuer"; then
    print_status "OK" "Dex OIDC configuration endpoint is working"
else
    print_status "WARNING" "Dex OIDC configuration endpoint test failed"
fi

# Test JWKS endpoint
if kubectl run test-jwks --image=curlimages/curl -i --rm --restart=Never -n $NAMESPACE_DEX -- \
  curl -s http://dex.$NAMESPACE_DEX.svc.cluster.local:5556/keys | grep -q "keys"; then
    print_status "OK" "Dex JWKS endpoint is working"
else
    print_status "WARNING" "Dex JWKS endpoint test failed"
fi

# Step 5: Deploy Temporal
echo ""
echo "=== Step 5: Deploying Temporal ==="
print_status "INFO" "Deploying Temporal with Helm..."

# Check if Temporal is already installed
if helm list -n $NAMESPACE_TEMPORAL | grep -q temporal; then
    print_status "WARNING" "Temporal is already installed, upgrading..."
    helm upgrade temporal $HELM_CHART -f $CONFIG_FILE -n $NAMESPACE_TEMPORAL
else
    helm install temporal $HELM_CHART -f $CONFIG_FILE -n $NAMESPACE_TEMPORAL
fi

print_status "OK" "Temporal deployment initiated"

# Step 6: Wait for Temporal to be ready
echo ""
echo "=== Step 6: Waiting for Temporal to be Ready ==="
print_status "INFO" "Waiting for Temporal pods to be ready..."

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=temporal -n $NAMESPACE_TEMPORAL --timeout=600s
print_status "OK" "Temporal is ready"

# Step 7: Verify deployment
echo ""
echo "=== Step 7: Verifying Deployment ==="

# Check Dex pods
DEX_PODS=$(kubectl get pods -n $NAMESPACE_DEX -l app=dex --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
if [ -n "$DEX_PODS" ]; then
    print_status "OK" "Dex pods are running:"
    echo "$DEX_PODS" | while read pod; do
        STATUS=$(kubectl get pod $pod -n $NAMESPACE_DEX -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "  - $pod: $STATUS"
    done
else
    print_status "ERROR" "No Dex pods found"
fi

# Check Temporal pods
TEMPORAL_PODS=$(kubectl get pods -n $NAMESPACE_TEMPORAL -l app.kubernetes.io/name=temporal --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
if [ -n "$TEMPORAL_PODS" ]; then
    print_status "OK" "Temporal pods are running:"
    echo "$TEMPORAL_PODS" | while read pod; do
        STATUS=$(kubectl get pod $pod -n $NAMESPACE_TEMPORAL -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "  - $pod: $STATUS"
    done
else
    print_status "ERROR" "No Temporal pods found"
fi

# Step 8: Test external endpoints
echo ""
echo "=== Step 8: Testing External Endpoints ==="
print_status "INFO" "Testing external endpoints..."

# Test Dex external endpoint
if curl -s -f https://console.gaap.dev.rafay-edge.net/dex/keys >/dev/null 2>&1; then
    print_status "OK" "Dex external endpoint is accessible"
else
    print_status "WARNING" "Dex external endpoint is not accessible (may need ingress configuration)"
fi

# Test Temporal Web UI
if curl -s -f -I https://ops-console.gaap.dev.rafay-edge.net/temporal >/dev/null 2>&1; then
    print_status "OK" "Temporal Web UI is accessible"
else
    print_status "WARNING" "Temporal Web UI is not accessible (may need Istio configuration)"
fi

# Step 9: Display access information
echo ""
echo "=== Step 9: Access Information ==="
print_status "INFO" "Deployment completed successfully!"
echo ""
echo "Access URLs:"
echo "  - Dex OIDC: https://console.gaap.dev.rafay-edge.net/dex"
echo "  - Temporal Web UI: https://ops-console.gaap.dev.rafay-edge.net/temporal"
echo ""
echo "Default Dex credentials (for testing):"
echo "  - Email: admin@rafay-edge.net"
echo "  - Password: admin123"
echo ""
echo "OIDC Client IDs:"
echo "  - Temporal Server: temporal-client"
echo "  - Temporal Worker: temporal-worker"
echo "  - Temporal Web UI: temporal-web-ui"
echo ""
echo "Next steps:"
echo "  1. Change the default Dex password"
echo "  2. Configure proper TLS certificates"
echo "  3. Set up monitoring and alerting"
echo "  4. Configure backup and disaster recovery"
echo "  5. Test OIDC authentication flow"

# Step 10: Show useful commands
echo ""
echo "=== Useful Commands ==="
echo "Check Dex logs:"
echo "  kubectl logs -f -l app=dex -n $NAMESPACE_DEX"
echo ""
echo "Check Temporal logs:"
echo "  kubectl logs -f -l app.kubernetes.io/name=temporal -n $NAMESPACE_TEMPORAL"
echo ""
echo "Access Dex directly:"
echo "  kubectl port-forward svc/dex 5556:5556 -n $NAMESPACE_DEX"
echo ""
echo "Access Temporal directly:"
echo "  kubectl port-forward svc/temporal-frontend 7233:7233 -n $NAMESPACE_TEMPORAL"
echo ""
echo "Uninstall everything:"
echo "  helm uninstall temporal -n $NAMESPACE_TEMPORAL"
echo "  kubectl delete namespace $NAMESPACE_TEMPORAL"
echo "  kubectl delete namespace $NAMESPACE_DEX"

print_status "OK" "Deployment script completed successfully!" 