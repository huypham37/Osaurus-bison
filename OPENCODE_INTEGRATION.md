# OpenCode Integration Guide

This guide explains how to integrate Osaurus with OpenCode backend to access GitHub Copilot and other AI providers through Osaurus's native macOS UI.

## Architecture

```
┌─────────────────────────────────────┐
│    Osaurus (Native macOS UI)        │
│  ┌──────────────────────────────┐   │
│  │   Chat Interface (SwiftUI)   │   │
│  └──────────────┬───────────────┘   │
│                 │                   │
│  ┌──────────────▼───────────────┐   │
│  │  ModelServiceRouter          │   │
│  └──┬────────┬──────────┬───────┘   │
│     │        │          │           │
│  ┌──▼──┐ ┌──▼──────┐ ┌─▼─────────┐  │
│  │ MLX │ │Foundation│ │ OpenCode  │  │
│  │     │ │  Models  │ │   Proxy   │  │
│  └─────┘ └──────────┘ └─────┬─────┘  │
└────────────────────────────────┼──────┘
                                │ HTTP
                     ┌──────────▼──────────┐
                     │  OpenCode Server    │
                     │  localhost:4096     │
                     │                     │
                     │ • GitHub Copilot    │
                     │ • Anthropic Claude  │
                     │ • OpenAI GPT        │
                     │ • Other providers   │
                     └─────────────────────┘
```

## What's Included

### OpenCodeProxyService.swift

A Swift service that implements the `ModelService` protocol and communicates with OpenCode's HTTP API.

**Features:**
- ✅ Automatic OpenCode server detection
- ✅ Session management (creates and reuses chat sessions)
- ✅ SSE streaming support for real-time responses
- ✅ Provider and model discovery
- ✅ Error handling with descriptive messages

**API Integration:**
- `GET /config/providers` - Fetch available providers and models
- `POST /session` - Create new chat session
- `POST /session/:id/message` - Send messages and receive responses

## Setup Instructions

### 1. Prerequisites

**Install OpenCode:**
```bash
curl -fsSL https://opencode.ai/install | bash
# Or via package manager
npm i -g opencode-ai@latest
```

**Authenticate with GitHub Copilot (or other providers):**
```bash
opencode
# Follow the TUI prompts to authenticate
```

### 2. Start OpenCode Server

In a terminal, run:
```bash
opencode serve --port 4096
```

The server will start at `http://127.0.0.1:4096` and expose the API endpoints.

### 3. Add OpenCodeProxyService to Osaurus

**In Xcode:**

1. Open `osaurus.xcodeproj`
2. Add `Services/OpenCodeProxyService.swift` to the project:
   - Right-click on `osaurus/Services` folder
   - Select "Add Files to 'osaurus'..."
   - Select `OpenCodeProxyService.swift`
   - Ensure "Copy items if needed" is checked
   - Add to target: `osaurus`

### 4. Register the Service

**Edit: `osaurus/Networking/AsyncHTTPHandler.swift`**

Find the `handleChat` method (around line 74) and add `OpenCodeProxyService()` to the services array:

```swift
// Prepare model services (prefer Foundation for default, MLX for explicit local models)
let services: [ModelService] = [
    FoundationModelService(),
    MLXService.shared,
    OpenCodeProxyService()  // 👈 Add this line
]
```

### 5. Build and Run

```bash
cd /path/to/Osaurus-bison
make app

# Or in Xcode: ⌘B to build, ⌘R to run
```

## Usage

### 1. Start OpenCode Server

```bash
opencode serve --port 4096
```

You should see:
```
OpenCode server running on http://127.0.0.1:4096
```

### 2. Launch Osaurus

Open the Osaurus app. The UI will automatically detect the running OpenCode server.

### 3. Select a Model

In Osaurus, you can now use models from OpenCode providers:

**Model naming format:**
- `copilot:gpt-4o` - GitHub Copilot with GPT-4o
- `copilot:gpt-4-turbo` - GitHub Copilot with GPT-4 Turbo
- `anthropic:claude-sonnet-4` - Anthropic Claude Sonnet 4
- `openai:gpt-4` - OpenAI GPT-4

**Note:** The current implementation defaults to `copilot:gpt-4o`. Future updates will add model selection UI.

### 4. Chat

Type your message in the chat interface and see responses streamed from GitHub Copilot through OpenCode!

## Configuration

### Change OpenCode Server URL

If you run OpenCode on a different port or host, modify the service initialization:

**In `AsyncHTTPHandler.swift`:**
```swift
let services: [ModelService] = [
    FoundationModelService(),
    MLXService.shared,
    OpenCodeProxyService(baseURL: "http://localhost:8080")  // Custom URL
]
```

### Model Selection (Future Enhancement)

The service will be enhanced to:
1. Fetch available providers from `/config/providers`
2. Display them in the model selector UI
3. Allow users to choose provider:model combinations
4. Save preferences

## Troubleshooting

### "OpenCode server not available"

**Check if OpenCode is running:**
```bash
curl http://127.0.0.1:4096/config/providers
```

**Expected response:**
```json
{
  "providers": [
    {
      "id": "copilot",
      "name": "GitHub Copilot",
      "models": { ... }
    }
  ],
  "default": { ... }
}
```

**If error:**
- Ensure `opencode serve --port 4096` is running
- Check firewall settings
- Verify port 4096 is not in use: `lsof -i :4096`

### "No active OpenCode session"

The service automatically creates sessions. If you see this error:
- Restart Osaurus
- Check OpenCode server logs for errors

### Streaming not working

- Ensure you're using OpenCode v0.1.x or later
- Check that SSE is enabled on the OpenCode server
- Monitor network traffic to verify streaming responses

## Development Notes

### Code Structure

**OpenCodeProxyService.swift** (~370 lines):
- Models (Codable structs for API types)
- Service implementation (ModelService protocol)
- HTTP client methods
- SSE streaming parser
- Error types

### Key Methods

1. `isAvailable()` - Checks if OpenCode server is reachable
2. `handles(requestedModel:)` - Determines if this service should handle a model request
3. `streamDeltas(...)` - Streams response tokens in real-time
4. `generateOneShot(...)` - Non-streaming response generation
5. `fetchProviders()` - Gets available providers from OpenCode
6. `createSession()` - Creates a new OpenCode chat session
7. `sendMessage(...)` - Sends a message to OpenCode
8. `streamMessageResponse(...)` - Handles SSE streaming

### Future Enhancements

- [ ] UI for selecting OpenCode providers and models
- [ ] Configuration panel for OpenCode server URL
- [ ] Provider authentication status display
- [ ] Model parameter passthrough (temperature, max_tokens, etc.)
- [ ] Multi-session support
- [ ] Session history and management
- [ ] Error recovery and retry logic
- [ ] Provider cost estimation display

## Testing

### Manual Testing

1. **Start OpenCode:**
   ```bash
   opencode serve --port 4096
   ```

2. **Start Osaurus** (with OpenCodeProxyService integrated)

3. **Send test message:**
   - Type: "Hello, can you hear me?"
   - Verify response comes from GitHub Copilot

4. **Test streaming:**
   - Type: "Write a haiku about dinosaurs"
   - Verify tokens appear incrementally

### Automated Testing (Future)

```swift
// Unit tests for OpenCodeProxyService
class OpenCodeProxyServiceTests: XCTestCase {
    func testServerAvailability() async throws {
        let service = OpenCodeProxyService()
        XCTAssertTrue(service.isAvailable())
    }

    func testModelHandling() {
        let service = OpenCodeProxyService()
        XCTAssertTrue(service.handles(requestedModel: "copilot:gpt-4o"))
        XCTAssertFalse(service.handles(requestedModel: "llama-3.2-3b"))
    }
}
```

## License

This integration follows the licenses of both projects:
- Osaurus: Check LICENSE file in Osaurus repository
- OpenCode: Open source (check OpenCode repository)

## Contributing

To contribute improvements to this integration:

1. Fork the Osaurus repository
2. Create a feature branch
3. Make your changes to `OpenCodeProxyService.swift`
4. Test thoroughly
5. Submit a pull request

## Support

- **Osaurus Issues:** https://github.com/dinoki-ai/osaurus/issues
- **OpenCode Issues:** https://github.com/sst/opencode/issues
- **Integration Issues:** File in the Osaurus repository with `[OpenCode]` tag

## Acknowledgments

- **Osaurus** by Dinoki Labs - Native MLX server for macOS
- **OpenCode** by SST - Terminal-based AI coding agent
- **GitHub Copilot** - AI pair programmer
