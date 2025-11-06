#!/bin/bash
echo "=== Testing Osaurus API ==="
echo ""
echo "1. Root endpoint:"
curl -s http://localhost:4096/
echo ""
echo ""
echo "2. Health endpoint:"
curl -s http://localhost:4096/health
echo ""
echo ""
echo "3. Models endpoint:"
curl -s http://localhost:4096/models | jq '.' 2>/dev/null || curl -s http://localhost:4096/models
echo ""
echo ""
echo "4. Chat completions (non-streaming):"
curl -s -X POST http://localhost:4096/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "github-copilot:claude-sonnet-4.5",
    "messages": [{"role": "user", "content": "Explain birthday attack briefly"}],
    "stream": false,
    "max_tokens": 200
  }' | jq '.' 2>/dev/null || curl -s -X POST http://localhost:4096/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "github-copilot:claude-sonnet-4.5",
    "messages": [{"role": "user", "content": "Explain birthday attack briefly"}],
    "stream": false,
    "max_tokens": 200
  }'
