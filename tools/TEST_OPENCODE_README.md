---
name: OpenCode API Tester Documentation
description: Comprehensive documentation for testing OpenCode server API endpoints, session management, and streaming responses
tool: test_opencode_server.py
version: 1.0.0
category: API Testing
tags:
  - opencode
  - api-testing
  - streaming
  - sse
  - session-management
related:
  - OPENCODE_INTEGRATION.md
  - osaurus/Services/OpenCodeProxyService.swift
requirements:
  - OpenCode server running on port 4096
  - Python 3.7+
  - requests library
---

# OpenCode Server API Test Script

## Overview

`test_opencode_server.py` is a comprehensive Python script to test the OpenCode server API running at port 4096.

## Quick Start

```bash
# Run all tests
./test_opencode_server.py

# Test specific endpoint
./test_opencode_server.py --test server      # Check connectivity
./test_opencode_server.py --test providers   # List available providers
./test_opencode_server.py --test session     # Create a session
./test_opencode_server.py --test message     # Send non-streaming message
./test_opencode_server.py --test stream      # Test streaming response
./test_opencode_server.py --test conversation # Test multi-turn chat

# Custom server URL
./test_opencode_server.py --url http://localhost:8080

# Custom message
./test_opencode_server.py --test message --message "What is 2+2?"
```

## Prerequisites

1. **Start OpenCode Server:**
   ```bash
   opencode serve --port 4096
   ```

2. **Python Requirements:**
   - Python 3.7+
   - `requests` library: `pip3 install requests`

## What It Tests

### 1. Server Connectivity
- Checks if OpenCode server is running at the specified port
- Endpoint: `GET /config/providers`

### 2. Provider Configuration
- Lists all available AI providers (GitHub Copilot, OpenAI, Anthropic, etc.)
- Shows available models for each provider
- Displays default provider/model configuration

### 3. Session Management
- Creates a new chat session
- Endpoint: `POST /session`
- Returns session ID for subsequent messages

### 4. Non-Streaming Messages
- Sends a message and waits for complete response
- Endpoint: `POST /session/:id/message` with `stream: false`
- Good for simple request-response patterns

### 5. Streaming Messages
- Sends a message and receives real-time streaming response
- Uses Server-Sent Events (SSE) format
- Shows incremental token delivery
- Endpoint: `POST /session/:id/message` with `stream: true`

### 6. Conversation Flow
- Tests multi-turn conversations
- Verifies context retention across messages
- Ensures the AI remembers previous conversation

## Example Output

```
================================================================================
  OpenCode Server API Test Suite
  Base URL: http://localhost:4096
================================================================================

================================================================================
  Server Connectivity
================================================================================
Status Code: 200
✓ OpenCode server is reachable

================================================================================
  Get Providers Configuration
================================================================================
Status Code: 200

✓ Found 2 provider(s)

  Provider: GitHub Copilot (ID: github-copilot)
  Available models: 15
    - gpt-4o
    - claude-sonnet-4.5
    - grok-code-fast-1
    ... and 12 more

  Provider: OpenCode Zen (ID: opencode)
  Available models: 2
    - big-pickle
    - grok-code

Default provider: github-copilot:claude-sonnet-4.5

...

================================================================================
  Test Summary
================================================================================
Total tests: 6
✓ Passed: 6
✗ Failed: 0
⊘ Skipped: 0
Time elapsed: 12.34s

Detailed Results:
  server_reachable          ✓ PASS
  get_providers             ✓ PASS
  create_session            ✓ PASS
  message_non_streaming     ✓ PASS
  message_streaming         ✓ PASS
  conversation_flow         ✓ PASS
```

## Troubleshooting

### "Cannot connect to server"

**Solution:**
```bash
# Check if OpenCode is running
lsof -i :4096

# Start OpenCode server
opencode serve --port 4096
```

### "Failed to create session"

**Possible causes:**
- OpenCode not authenticated with providers
- Invalid provider/model specified

**Solution:**
```bash
# Authenticate with GitHub Copilot
opencode

# Follow the prompts to authenticate
```

### Import errors

```bash
# Install requests library
pip3 install requests
```

## Integration with Osaurus

This test script validates the OpenCode API that Osaurus connects to via `OpenCodeProxyService.swift`.

**OpenCode API Endpoints:**
- `GET /config/providers` → Lists providers and models
- `POST /session` → Creates chat session
- `POST /session/:id/message` → Sends messages (streaming or non-streaming)

**Osaurus Integration:**
See `OPENCODE_INTEGRATION.md` for details on how Osaurus uses these endpoints.

## Development

### Adding New Tests

```python
def test_custom_feature(self) -> bool:
    """Test a custom feature"""
    self.print_section("Custom Feature Test")
    
    try:
        response = requests.get(f"{self.base_url}/custom/endpoint")
        if response.status_code == 200:
            print("✓ Custom feature works!")
            return True
        return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False
```

### Running Specific Providers

```python
# Modify test_create_session() payload
payload = {
    "provider": "openai",  # or "anthropic", "github-copilot"
    "model": "gpt-4"
}
```

## Related Files

- `OPENCODE_INTEGRATION.md` - Integration guide for Osaurus
- `osaurus/Services/OpenCodeProxyService.swift` - Swift client implementation
- `test_api_streaming.py` - Tests for Osaurus API (port 4096 vs OpenCode)

## License

Same as Osaurus project.
