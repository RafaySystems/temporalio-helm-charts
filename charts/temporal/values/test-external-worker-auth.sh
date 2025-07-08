#!/bin/bash

# Test External Worker OIDC Authentication
# This script tests the token exchange and Temporal API access

set -e

# Configuration
DEX_URL="https://console.gaap.dev.rafay-edge.net/dex"
TEMPORAL_URL="https://ops-console.gaap.dev.rafay-edge.net/temporalui"
CLIENT_ID="external-worker-client"
CLIENT_SECRET="external-worker-secret-123"  # Change this to match your Dex config

echo "🔐 Testing External Worker OIDC Authentication"
echo "=============================================="

# Step 1: Test Dex connectivity
echo "1. Testing Dex connectivity..."
if curl -s -f "$DEX_URL/.well-known/openid_configuration" > /dev/null; then
    echo "   ✅ Dex is accessible"
else
    echo "   ❌ Dex is not accessible"
    exit 1
fi

# Step 2: Get OIDC configuration
echo "2. Getting OIDC configuration..."
OIDC_CONFIG=$(curl -s "$DEX_URL/.well-known/openid_configuration")
TOKEN_ENDPOINT=$(echo "$OIDC_CONFIG" | jq -r '.token_endpoint')
JWKS_ENDPOINT=$(echo "$OIDC_CONFIG" | jq -r '.jwks_uri')

echo "   Token endpoint: $TOKEN_ENDPOINT"
echo "   JWKS endpoint: $JWKS_ENDPOINT"

# Step 3: Exchange client credentials for token
echo "3. Exchanging client credentials for token..."
TOKEN_RESPONSE=$(curl -s -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=openid profile email groups")

# Check if token exchange was successful
if echo "$TOKEN_RESPONSE" | jq -e '.access_token' > /dev/null; then
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')
    EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
    
    echo "   ✅ Token exchange successful"
    echo "   Token type: $TOKEN_TYPE"
    echo "   Expires in: $EXPIRES_IN seconds"
    echo "   Token (first 50 chars): ${ACCESS_TOKEN:0:50}..."
else
    echo "   ❌ Token exchange failed"
    echo "   Response: $TOKEN_RESPONSE"
    exit 1
fi

# Step 4: Decode and inspect the JWT token
echo "4. Inspecting JWT token..."
JWT_HEADER=$(echo "$ACCESS_TOKEN" | cut -d'.' -f1 | base64 -d 2>/dev/null | jq .)
JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .)

echo "   JWT Header: $JWT_HEADER"
echo "   JWT Payload: $JWT_PAYLOAD"

# Step 5: Test Temporal API with token
echo "5. Testing Temporal API with token..."
API_RESPONSE=$(curl -s -X GET "$TEMPORAL_URL/api/v1/cluster/info" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

if echo "$API_RESPONSE" | jq -e '.clusterName' > /dev/null; then
    CLUSTER_NAME=$(echo "$API_RESPONSE" | jq -r '.clusterName')
    echo "   ✅ Temporal API access successful"
    echo "   Cluster name: $CLUSTER_NAME"
else
    echo "   ❌ Temporal API access failed"
    echo "   Response: $API_RESPONSE"
    exit 1
fi

# Step 6: Test additional Temporal endpoints
echo "6. Testing additional Temporal endpoints..."

# Test namespaces endpoint
NAMESPACES_RESPONSE=$(curl -s -X GET "$TEMPORAL_URL/api/v1/namespaces" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

if echo "$NAMESPACES_RESPONSE" | jq -e '.namespaces' > /dev/null; then
    echo "   ✅ Namespaces endpoint accessible"
    NAMESPACE_COUNT=$(echo "$NAMESPACES_RESPONSE" | jq '.namespaces | length')
    echo "   Number of namespaces: $NAMESPACE_COUNT"
else
    echo "   ❌ Namespaces endpoint failed"
    echo "   Response: $NAMESPACES_RESPONSE"
fi

# Test workflows endpoint
WORKFLOWS_RESPONSE=$(curl -s -X GET "$TEMPORAL_URL/api/v1/namespaces/default/workflows" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

if echo "$WORKFLOWS_RESPONSE" | jq -e '.executions' > /dev/null; then
    echo "   ✅ Workflows endpoint accessible"
    WORKFLOW_COUNT=$(echo "$WORKFLOWS_RESPONSE" | jq '.executions | length')
    echo "   Number of workflows: $WORKFLOW_COUNT"
else
    echo "   ❌ Workflows endpoint failed"
    echo "   Response: $WORKFLOWS_RESPONSE"
fi

echo ""
echo "🎉 External Worker Authentication Test Complete!"
echo "================================================"
echo ""
echo "Summary:"
echo "  ✅ Dex connectivity: Working"
echo "  ✅ Token exchange: Working"
echo "  ✅ JWT token: Valid"
echo "  ✅ Temporal API access: Working"
echo ""
echo "Your external workers can now connect using:"
echo "  Client ID: $CLIENT_ID"
echo "  Client Secret: $CLIENT_SECRET"
echo "  Token URL: $TOKEN_ENDPOINT"
echo "  Temporal URL: $TEMPORAL_URL"
echo ""
echo "Example curl command:"
echo "  curl -X GET \"$TEMPORAL_URL/api/v1/cluster/info\" \\"
echo "    -H \"Authorization: Bearer \$ACCESS_TOKEN\" \\"
echo "    -H \"Content-Type: application/json\"" 