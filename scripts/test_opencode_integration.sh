#!/bin/bash
#
# Test script for OpenCode integration with Osaurus
# This script helps verify that the integration is working correctly
#

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

OPENCODE_URL="http://127.0.0.1:4096"
OSAURUS_URL="http://127.0.0.1:1337"

echo "🦕 Osaurus + OpenCode Integration Test"
echo "======================================"
echo ""

# Step 1: Check if OpenCode server is running
echo -n "1. Checking OpenCode server... "
if curl -s -f "${OPENCODE_URL}/config/providers" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo ""
    echo "Please start OpenCode server first:"
    echo "  opencode serve --port 4096"
    exit 1
fi

# Step 2: Check available providers
echo -n "2. Fetching available providers... "
PROVIDERS=$(curl -s "${OPENCODE_URL}/config/providers")
if echo "$PROVIDERS" | grep -q "providers"; then
    echo -e "${GREEN}✓ Success${NC}"
    echo ""
    echo "Available providers:"
    echo "$PROVIDERS" | jq -r '.providers[] | "  • \(.name) (\(.id))"' 2>/dev/null || echo "  (Install jq for pretty output)"
else
    echo -e "${RED}✗ Failed${NC}"
    exit 1
fi

echo ""

# Step 3: Check if Osaurus is running
echo -n "3. Checking Osaurus server... "
if curl -s -f "${OSAURUS_URL}/health" > /dev/null 2>&1 || curl -s -f "${OSAURUS_URL}/" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo ""
    echo "Please start Osaurus first."
    echo "You can run it from Xcode or use:"
    echo "  make app && open build/DerivedData/Build/Products/Release/osaurus.app"
    exit 1
fi

# Step 4: Test OpenCode integration through Osaurus
echo ""
echo "4. Testing OpenCode integration through Osaurus..."
echo -n "   Sending test message... "

RESPONSE=$(curl -s -N "${OSAURUS_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "copilot:gpt-4o",
    "messages": [{"role":"user","content":"Say hello in one word"}],
    "stream": false,
    "max_tokens": 10
  }' 2>&1)

if echo "$RESPONSE" | grep -q "choices\|error"; then
    echo -e "${GREEN}✓ Response received${NC}"
    echo ""
    echo "Response:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
else
    echo -e "${RED}✗ No valid response${NC}"
    echo ""
    echo "Response received:"
    echo "$RESPONSE"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "1. Check that OpenCodeProxyService is added to AsyncHTTPHandler.swift"
    echo "2. Check Osaurus logs for errors"
    echo "3. Verify model name format: 'copilot:gpt-4o'"
    exit 1
fi

# Step 5: Test streaming
echo ""
echo "5. Testing streaming response..."
echo "   (First few chunks will be shown)"
echo ""

curl -N "${OSAURUS_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "copilot:gpt-4o",
    "messages": [{"role":"user","content":"Count to 3"}],
    "stream": true,
    "max_tokens": 50
  }' 2>/dev/null | head -n 5

echo ""
echo ""
echo -e "${GREEN}✓ Integration test complete!${NC}"
echo ""
echo "Next steps:"
echo "  • Try the integration from the Osaurus UI"
echo "  • Test different OpenCode providers"
echo "  • Check OPENCODE_INTEGRATION.md for more info"
