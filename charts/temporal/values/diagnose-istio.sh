#!/bin/bash

# Istio Temporal Diagnostic Script
# This script helps diagnose the "503 NC cluster_not_found" error

set -e

echo "=== Istio Temporal Diagnostic Script ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "WARNING" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
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

if command_exists istioctl; then
    print_status "OK" "istioctl is available"
else
    print_status "WARNING" "istioctl is not installed - some checks will be skipped"
fi

echo ""

# Check cluster connectivity
echo "=== Checking Cluster Connectivity ==="
if kubectl cluster-info >/dev/null 2>&1; then
    print_status "OK" "Kubernetes cluster is accessible"
    CLUSTER_INFO=$(kubectl cluster-info | head -1)
    echo "   Cluster: $CLUSTER_INFO"
else
    print_status "ERROR" "Cannot connect to Kubernetes cluster"
    exit 1
fi

echo ""

# Check namespace
echo "=== Checking Namespace ==="
NAMESPACE=${NAMESPACE:-default}
if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    print_status "OK" "Namespace '$NAMESPACE' exists"
else
    print_status "ERROR" "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

echo ""

# Check Temporal services
echo "=== Checking Temporal Services ==="
TEMPORAL_SERVICES=$(kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=temporal --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

if [ -n "$TEMPORAL_SERVICES" ]; then
    print_status "OK" "Temporal services found:"
    echo "$TEMPORAL_SERVICES" | while read service; do
        echo "   - $service"
        
        # Get service details
        SERVICE_TYPE=$(kubectl get svc $service -n $NAMESPACE -o jsonpath='{.spec.type}' 2>/dev/null || echo "Unknown")
        SERVICE_PORT=$(kubectl get svc $service -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "Unknown")
        SERVICE_TARGET_PORT=$(kubectl get svc $service -n $NAMESPACE -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "Unknown")
        
        echo "     Type: $SERVICE_TYPE, Port: $SERVICE_PORT, TargetPort: $SERVICE_TARGET_PORT"
        
        # Check if service has endpoints
        ENDPOINTS=$(kubectl get endpoints $service -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")
        if [ -n "$ENDPOINTS" ]; then
            print_status "OK" "     Service has endpoints: $ENDPOINTS"
        else
            print_status "ERROR" "     Service has no endpoints"
        fi
    done
else
    print_status "ERROR" "No Temporal services found in namespace '$NAMESPACE'"
    echo "   Available services:"
    kubectl get svc -n $NAMESPACE --no-headers -o custom-columns=":metadata.name" | head -10
fi

echo ""

# Check Istio resources
echo "=== Checking Istio Resources ==="

# Check Virtual Services
VS_COUNT=$(kubectl get virtualservice -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$VS_COUNT" -gt 0 ]; then
    print_status "OK" "Found $VS_COUNT Virtual Service(s)"
    kubectl get virtualservice -n $NAMESPACE --no-headers -o custom-columns=":metadata.name" | while read vs; do
        echo "   - $vs"
        
        # Check Virtual Service configuration
        VS_HOSTS=$(kubectl get virtualservice $vs -n $NAMESPACE -o jsonpath='{.spec.hosts[*]}' 2>/dev/null || echo "Unknown")
        VS_GATEWAYS=$(kubectl get virtualservice $vs -n $NAMESPACE -o jsonpath='{.spec.gateways[*]}' 2>/dev/null || echo "Unknown")
        
        echo "     Hosts: $VS_HOSTS"
        echo "     Gateways: $VS_GATEWAYS"
        
        # Check destinations
        DESTINATIONS=$(kubectl get virtualservice $vs -n $NAMESPACE -o jsonpath='{.spec.http[*].route[*].destination.host}' 2>/dev/null || echo "")
        if [ -n "$DESTINATIONS" ]; then
            echo "     Destinations: $DESTINATIONS"
        fi
    done
else
    print_status "WARNING" "No Virtual Services found in namespace '$NAMESPACE'"
fi

# Check Gateways
GATEWAY_COUNT=$(kubectl get gateway -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$GATEWAY_COUNT" -gt 0 ]; then
    print_status "OK" "Found $GATEWAY_COUNT Gateway(s)"
    kubectl get gateway -n $NAMESPACE --no-headers -o custom-columns=":metadata.name" | while read gw; do
        echo "   - $gw"
    done
else
    print_status "WARNING" "No Gateways found in namespace '$NAMESPACE'"
fi

echo ""

# Check Istio sidecar injection
echo "=== Checking Istio Sidecar Injection ==="
NAMESPACE_LABEL=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "")
if [ "$NAMESPACE_LABEL" = "enabled" ]; then
    print_status "OK" "Istio sidecar injection is enabled for namespace '$NAMESPACE'"
else
    print_status "WARNING" "Istio sidecar injection is not enabled for namespace '$NAMESPACE'"
    echo "   To enable: kubectl label namespace $NAMESPACE istio-injection=enabled"
fi

# Check if pods have sidecars
TEMPORAL_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=temporal --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
if [ -n "$TEMPORAL_PODS" ]; then
    echo "   Checking Temporal pods for sidecars:"
    echo "$TEMPORAL_PODS" | while read pod; do
        SIDECAR_COUNT=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[?(@.name=="istio-proxy")].name}' 2>/dev/null | wc -w || echo "0")
        if [ "$SIDECAR_COUNT" -gt 0 ]; then
            print_status "OK" "     $pod has Istio sidecar"
        else
            print_status "WARNING" "     $pod does not have Istio sidecar"
        fi
    done
fi

echo ""

# Check Istio ingress gateway
echo "=== Checking Istio Ingress Gateway ==="
INGRESS_NAMESPACE=${INGRESS_NAMESPACE:-istio-system}
INGRESS_PODS=$(kubectl get pods -n $INGRESS_NAMESPACE -l app=istio-ingressgateway --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

if [ -n "$INGRESS_PODS" ]; then
    print_status "OK" "Istio ingress gateway found in namespace '$INGRESS_NAMESPACE'"
    echo "$INGRESS_PODS" | while read pod; do
        POD_STATUS=$(kubectl get pod $pod -n $INGRESS_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$POD_STATUS" = "Running" ]; then
            print_status "OK" "     $pod is Running"
        else
            print_status "WARNING" "     $pod status: $POD_STATUS"
        fi
    done
else
    print_status "WARNING" "No Istio ingress gateway found in namespace '$INGRESS_NAMESPACE'"
fi

echo ""

# Test service connectivity
echo "=== Testing Service Connectivity ==="
if [ -n "$TEMPORAL_SERVICES" ]; then
    echo "$TEMPORAL_SERVICES" | while read service; do
        echo "Testing connectivity to $service..."
        
        # Test from within cluster
        TEST_POD=$(kubectl run test-connectivity-$service --image=curlimages/curl -i --rm --restart=Never --timeout=30s -- curl -s -o /dev/null -w "%{http_code}" http://$service.$NAMESPACE.svc.cluster.local:8080 2>/dev/null || echo "FAILED")
        
        if [ "$TEST_POD" = "200" ] || [ "$TEST_POD" = "404" ]; then
            print_status "OK" "     $service is reachable (HTTP $TEST_POD)"
        else
            print_status "ERROR" "     $service is not reachable ($TEST_POD)"
        fi
    done
fi

echo ""

# Check Istio proxy configuration (if istioctl is available)
if command_exists istioctl; then
    echo "=== Checking Istio Proxy Configuration ==="
    
    # Get ingress gateway pod
    INGRESS_POD=$(kubectl get pods -n $INGRESS_NAMESPACE -l app=istio-ingressgateway --no-headers -o custom-columns=":metadata.name" | head -1 2>/dev/null || echo "")
    
    if [ -n "$INGRESS_POD" ]; then
        echo "Checking proxy configuration for $INGRESS_POD..."
        
        # Check clusters
        CLUSTERS=$(istioctl proxy-config clusters $INGRESS_POD.$INGRESS_NAMESPACE | grep temporal || echo "")
        if [ -n "$CLUSTERS" ]; then
            print_status "OK" "Temporal services found in proxy clusters"
            echo "$CLUSTERS" | head -5
        else
            print_status "WARNING" "No Temporal services found in proxy clusters"
        fi
        
        # Check routes
        ROUTES=$(istioctl proxy-config routes $INGRESS_POD.$INGRESS_NAMESPACE | grep temporal || echo "")
        if [ -n "$ROUTES" ]; then
            print_status "OK" "Temporal routes found in proxy routes"
            echo "$ROUTES" | head -5
        else
            print_status "WARNING" "No Temporal routes found in proxy routes"
        fi
    fi
fi

echo ""

# Summary and recommendations
echo "=== Summary and Recommendations ==="

if [ -n "$TEMPORAL_SERVICES" ] && [ "$VS_COUNT" -gt 0 ]; then
    print_status "OK" "Basic setup appears correct"
    echo ""
    echo "If you're still getting '503 NC cluster_not_found', try these steps:"
    echo "1. Verify service names in Virtual Service match actual service names"
    echo "2. Ensure Istio sidecar injection is enabled: kubectl label namespace $NAMESPACE istio-injection=enabled"
    echo "3. Restart Temporal pods after enabling sidecar injection"
    echo "4. Check Virtual Service destination host format: temporal-web.$NAMESPACE.svc.cluster.local"
    echo "5. Verify Gateway selector matches ingress gateway labels"
else
    print_status "ERROR" "Setup issues detected"
    echo ""
    echo "Please fix the issues above before proceeding."
fi

echo ""
echo "=== Diagnostic Complete ===" 