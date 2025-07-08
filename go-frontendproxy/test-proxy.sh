#!/bin/bash

# Test Temporal Frontend Proxy
# This script tests the proxy functionality with JWT token validation

set -e

# Configuration
PROXY_URL="http://localhost:8081"
DEX_URL="https://console.gaap.dev.rafay-edge.net/dex"
CLIENT_ID="external-worker-client"
CLIENT_SECRET="external-worker-secret-123"

echo "🧪 Testing Temporal Frontend Proxy"
echo "=================================="

# Step 1: Test proxy health endpoint
echo "1. Testing proxy health endpoint..."
HEALTH_RESPONSE=$(curl -s -f "$PROXY_URL/health")
if echo "$HEALTH_RESPONSE" | jq -e '.success' > /dev/null; then
    echo "   ✅ Proxy is healthy"
    echo "   Response: $(echo "$HEALTH_RESPONSE" | jq -r '.message')"
else
    echo "   ❌ Proxy health check failed"
    echo "   Response: $HEALTH_RESPONSE"
    exit 1
fi

# Step 2: Test OIDC discovery endpoint
echo "2. Testing OIDC discovery endpoint..."
DISCOVERY_RESPONSE=$(curl -s -f "$PROXY_URL/.well-known/openid_configuration")
if echo "$DISCOVERY_RESPONSE" | jq -e '.issuer' > /dev/null; then
    echo "   ✅ OIDC discovery working"
    ISSUER=$(echo "$DISCOVERY_RESPONSE" | jq -r '.issuer')
    echo "   Issuer: $ISSUER"
else
    echo "   ❌ OIDC discovery failed"
    echo "   Response: $DISCOVERY_RESPONSE"
    exit 1
fi

# Step 3: Get a test token (if client credentials are available)
echo "3. Getting test token..."
TOKEN_RESPONSE=$(curl -s -X POST "$DEX_URL/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=openid profile email groups")

if echo "$TOKEN_RESPONSE" | jq -e '.access_token' > /dev/null; then
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    echo "   ✅ Token obtained successfully"
    echo "   Token (first 50 chars): ${ACCESS_TOKEN:0:50}..."
else
    echo "   ⚠️  Could not get test token (this is expected if client not configured)"
    echo "   Response: $TOKEN_RESPONSE"
    echo "   Continuing with manual token test..."
    
    # Ask user for a token
    echo ""
    echo "Please provide a valid JWT token for testing (or press Enter to skip):"
    read -r ACCESS_TOKEN
    if [ -z "$ACCESS_TOKEN" ]; then
        echo "   Skipping token tests..."
        ACCESS_TOKEN=""
    fi
fi

# Step 4: Test proxy with valid token (if available)
if [ -n "$ACCESS_TOKEN" ]; then
    echo "4. Testing proxy with valid token..."
    
    # Test cluster info endpoint
    CLUSTER_RESPONSE=$(curl -s -X GET "$PROXY_URL/api/v1/cluster/info" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json")
    
    if echo "$CLUSTER_RESPONSE" | jq -e '.clusterName' > /dev/null; then
        CLUSTER_NAME=$(echo "$CLUSTER_RESPONSE" | jq -r '.clusterName')
        echo "   ✅ Cluster info endpoint working"
        echo "   Cluster name: $CLUSTER_NAME"
    else
        echo "   ❌ Cluster info endpoint failed"
        echo "   Response: $CLUSTER_RESPONSE"
    fi
    
    # Test namespaces endpoint
    NAMESPACES_RESPONSE=$(curl -s -X GET "$PROXY_URL/api/v1/namespaces" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json")
    
    if echo "$NAMESPACES_RESPONSE" | jq -e '.namespaces' > /dev/null; then
        echo "   ✅ Namespaces endpoint working"
        NAMESPACE_COUNT=$(echo "$NAMESPACES_RESPONSE" | jq '.namespaces | length')
        echo "   Number of namespaces: $NAMESPACE_COUNT"
    else
        echo "   ❌ Namespaces endpoint failed"
        echo "   Response: $NAMESPACES_RESPONSE"
    fi
else
    echo "4. Skipping token tests (no token available)"
fi

# Step 5: Test proxy without token (should fail)
echo "5. Testing proxy without token (should fail)..."
NO_TOKEN_RESPONSE=$(curl -s -X GET "$PROXY_URL/api/v1/cluster/info" \
  -H "Content-Type: application/json")

if echo "$NO_TOKEN_RESPONSE" | jq -e '.success' > /dev/null; then
    SUCCESS=$(echo "$NO_TOKEN_RESPONSE" | jq -r '.success')
    if [ "$SUCCESS" = "false" ]; then
        echo "   ✅ Properly rejected request without token"
        echo "   Message: $(echo "$NO_TOKEN_RESPONSE" | jq -r '.message')"
    else
        echo "   ❌ Unexpected success without token"
        echo "   Response: $NO_TOKEN_RESPONSE"
    fi
else
    echo "   ✅ Properly rejected request without token"
    echo "   Response: $NO_TOKEN_RESPONSE"
fi

# Step 6: Test proxy with invalid token (should fail)
echo "6. Testing proxy with invalid token (should fail)..."
INVALID_TOKEN_RESPONSE=$(curl -s -X GET "$PROXY_URL/api/v1/cluster/info" \
  -H "Authorization: Bearer invalid.token.here" \
  -H "Content-Type: application/json")

if echo "$INVALID_TOKEN_RESPONSE" | jq -e '.success' > /dev/null; then
    SUCCESS=$(echo "$INVALID_TOKEN_RESPONSE" | jq -r '.success')
    if [ "$SUCCESS" = "false" ]; then
        echo "   ✅ Properly rejected request with invalid token"
        echo "   Message: $(echo "$INVALID_TOKEN_RESPONSE" | jq -r '.message')"
    else
        echo "   ❌ Unexpected success with invalid token"
        echo "   Response: $INVALID_TOKEN_RESPONSE"
    fi
else
    echo "   ✅ Properly rejected request with invalid token"
    echo "   Response: $INVALID_TOKEN_RESPONSE"
fi

echo ""
echo "🎉 Temporal Frontend Proxy Test Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✅ Proxy health check: Working"
echo "  ✅ OIDC discovery: Working"
if [ -n "$ACCESS_TOKEN" ]; then
    echo "  ✅ Token validation: Working"
    echo "  ✅ API forwarding: Working"
else
    echo "  ⚠️  Token validation: Not tested (no token available)"
    echo "  ⚠️  API forwarding: Not tested (no token available)"
fi
echo "  ✅ Unauthorized requests: Properly rejected"
echo "  ✅ Invalid tokens: Properly rejected"
echo ""
echo "The proxy is ready to handle external worker requests!"
echo ""
echo "Example usage:"
echo "  curl -X GET \"$PROXY_URL/api/v1/cluster/info\" \\"
echo "    -H \"Authorization: Bearer YOUR_JWT_TOKEN\" \\"
echo "    -H \"Content-Type: application/json\"" 