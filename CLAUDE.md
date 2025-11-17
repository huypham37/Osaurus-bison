# CLAUDE.md - AI Assistant Development Guide

> Comprehensive guide for AI assistants working on the Osaurus codebase

**Last Updated:** 2025-11-17
**Project:** Osaurus - Native macOS LLM Server
**Version:** Based on latest main branch

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture & Tech Stack](#architecture--tech-stack)
3. [Directory Structure](#directory-structure)
4. [Key Patterns & Conventions](#key-patterns--conventions)
5. [Development Workflows](#development-workflows)
6. [API Structure](#api-structure)
7. [Important Files & Entry Points](#important-files--entry-points)
8. [Configuration Management](#configuration-management)
9. [Testing Guidelines](#testing-guidelines)
10. [Common Tasks](#common-tasks)
11. [Things to Avoid](#things-to-avoid)
12. [Resources](#resources)

---

## Project Overview

### What is Osaurus?

Osaurus is a **native macOS menu bar application** that provides local LLM (Large Language Model) inference capabilities on Apple Silicon Macs. It exposes OpenAI-compatible and Ollama-compatible HTTP APIs, enabling developers to run AI models locally with optimal performance.

**Key Features:**
- Native SwiftUI app with embedded SwiftNIO HTTP server
- MLX-based inference optimized for Apple Silicon
- Apple Foundation Models integration (macOS 26+)
- OpenAI-compatible API (`/v1/chat/completions`)
- Ollama-compatible API (`/chat`)
- In-app chat overlay with global hotkey (default: ⌘;)
- Model manager for downloading from Hugging Face
- Function/tool calling support
- Streaming responses (SSE and NDJSON)
- Real-time system resource monitoring

**Target Audience:**
- Developers running local LLMs on Apple Silicon
- AI enthusiasts wanting privacy and offline capabilities
- Users of OpenAI-compatible SDKs seeking local alternatives

**Platform Requirements:**
- macOS 15.5+ (Apple Foundation Models require macOS 26)
- Apple Silicon (M1 or newer) - Intel Macs NOT supported
- Xcode 16.4+ for building from source

---

## Architecture & Tech Stack

### High-Level Architecture

```
┌─────────────────────────────────────────────┐
│       SwiftUI User Interface Layer           │
│  (ContentView, ChatView, ConfigurationView) │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│     Controllers & State Management           │
│  (ServerController, ModelManager)            │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│         Business Logic Services              │
│  (MLXService, FoundationModelService,       │
│   HuggingFaceService, etc.)                  │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│      HTTP Server & Request Routing           │
│  (SwiftNIO HTTPHandler, Router,              │
│   AsyncHTTPHandler with SSE/NDJSON)         │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│    ML Runtime & Model Inference              │
│  (MLXLLM for MLX models +                   │
│   Apple Foundation Models)                   │
└─────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **UI** | SwiftUI + AppKit | Native macOS menu bar app |
| **Runtime** | Swift 6.0+ | Core application logic |
| **HTTP Server** | SwiftNIO | Async HTTP server |
| **ML Inference** | MLXLLM, MLX-Swift | Local LLM execution on Apple Silicon |
| **JSON** | IkigaJSON | High-performance JSON codec |
| **LLM Proxy** | FastAPI (Python) | Multi-provider rotation service |
| **Build** | Xcode 16.4+, Make | Build system |

**Key Swift Dependencies:**
- `SwiftNIO` - Async I/O networking
- `NIOHTTP1` - HTTP/1.1 protocol
- `MLXLLM` & `MLX-Swift` - ML model execution
- `IkigaJSON` - Fast JSON encoding/decoding
- `Carbon.HIToolbox` - Global hotkey registration

**Python Dependencies (llm-proxy):**
- `fastapi==0.115.0` - Web framework
- `uvicorn==0.31.0` - ASGI server
- `httpx==0.27.2` - HTTP client
- `cerebras-cloud-sdk` - Cerebras provider

### Architectural Patterns

1. **Service-Oriented Architecture (SOA)**
   - Each major system is a `Service` class
   - Services expose static/shared instances for singleton access
   - Examples: `MLXService`, `FoundationModelService`, `HuggingFaceService`

2. **MVVM for UI**
   - Controllers act as observable state (`@ObservableObject`)
   - Views bind via `@EnvironmentObject` and `@StateObject`
   - Example: `ContentView` observes `ServerController.isRunning`

3. **Protocol-Based Response Writing**
   - `ResponseWriter` protocol with pluggable implementations
   - `SSEResponseWriter` for OpenAI-compatible streaming
   - `NDJSONResponseWriter` for Ollama-compatible streaming

4. **Actor-Based Concurrency**
   - `@MainActor` for UI-bound code
   - `@unchecked Sendable` for thread-safe caching
   - Semaphore gates for per-model concurrency control

### Dual Model Support

**Path 1: MLX-loaded Models** (`MLXService.swift:713`)
- Loads models from Hugging Face via MLX runtime
- Supports: Llama, Qwen, Gemma, Mistral, Phi, DeepSeek
- Default directory: `~/MLXModels` (override: `OSU_MODELS_DIR`)
- Concurrent access with per-model semaphores

**Path 2: Apple Foundation Models** (`FoundationModelService.swift:473`)
- macOS 26+ (Tahoe) native models
- ANE (Apple Neural Engine) acceleration
- Automatically detected and exposed as "foundation" model
- Preferred for "default" or empty model string

**Model Resolution** (`ModelServiceRouter`)
- Routes requests to appropriate service based on model name
- Intelligent fallback between Foundation and MLX
- Unified response interface

---

## Directory Structure

```
/home/user/Osaurus-bison/
├── osaurus/                    # Main macOS application (69 Swift files)
│   ├── Core/                   # App lifecycle
│   │   ├── osaurusApp.swift        # SwiftUI App root
│   │   └── AppDelegate.swift       # Menu bar UI, server lifecycle
│   ├── Controllers/            # Business logic controllers
│   │   ├── ServerController.swift  # Server lifecycle (335 lines)
│   │   ├── ModelManager.swift      # Model discovery/downloads (839 lines)
│   │   └── HotKeyManager.swift     # Global hotkey registration (234 lines)
│   ├── Models/                 # Data structures & DTOs
│   │   ├── OpenAIAPI.swift         # OpenAI-compatible request/response
│   │   ├── ServerConfiguration.swift
│   │   ├── ChatConfiguration.swift
│   │   ├── MLXModel.swift
│   │   └── ResponseWriters.swift   # SSE & NDJSON formatters
│   ├── Networking/             # HTTP server & routing
│   │   ├── HTTPHandler.swift       # SwiftNIO channel handler (219 lines)
│   │   ├── Router.swift            # Path normalization (345 lines)
│   │   └── AsyncHTTPHandler.swift  # Streaming handler (505+ lines)
│   ├── Services/               # Core business logic
│   │   ├── MLXService.swift        # MLX model loading/inference (713 lines)
│   │   ├── FoundationModelService.swift  # Apple models (473 lines)
│   │   ├── OpenAICompatibleService.swift # API transformation (502 lines)
│   │   ├── HuggingFaceService.swift
│   │   ├── SearchService.swift
│   │   ├── SystemMonitorService.swift    # CPU/RAM monitoring (130 lines)
│   │   └── SharedConfigurationService.swift
│   ├── Views/                  # SwiftUI components
│   │   ├── ContentView.swift       # Main server control UI
│   │   ├── ChatView.swift          # In-app chat overlay (1,062 lines)
│   │   ├── ModelDownloadView.swift # Model manager UI
│   │   └── Components/             # Reusable UI components
│   ├── Theme/
│   │   └── Theme.swift             # Design system (light/dark mode)
│   └── Assets.xcassets/        # App icons
├── osaurusCLI/                 # Command-line interface
│   └── OsaurusCLI.swift        # CLI main entry (378 lines)
├── osaurusTests/               # Unit tests
│   ├── osaurusTests.swift
│   ├── MLXModelTests.swift
│   ├── ModelManagerTests.swift
│   ├── SearchServiceTests.swift
│   ├── ServerConfigurationStoreTests.swift
│   ├── ServerControllerConfigLoadingTests.swift
│   └── ModelManagerResolveTests.swift
├── osaurusUITests/             # UI automation tests
├── llm-proxy/                  # Python-based LLM rotation proxy
│   ├── proxy_server.py         # FastAPI main app (11,128 bytes)
│   ├── providers.py            # Provider registry (6,287 bytes)
│   ├── config.yaml             # Provider configuration
│   ├── requirements.txt
│   └── test_*.py               # Provider-specific tests
├── scripts/                    # Build & utility scripts
├── docs/                       # Documentation
├── results/                    # Benchmark results
├── osaurus.xcodeproj/          # Xcode project file
├── Makefile                    # Build automation
├── README.md                   # Main documentation
├── CONTRIBUTING.md             # Contribution guidelines
├── SHARED_CONFIGURATION_GUIDE.md
└── OpenAI_API_GUIDE.md
```

**Key Directories:**

- **`/osaurus`**: Main application code (3,648+ lines of Swift)
- **`/osaurusCLI`**: CLI tool for server management
- **`/llm-proxy`**: Standalone Python proxy for multi-provider LLM routing
- **`/osaurusTests`**: Comprehensive unit tests
- **`/scripts`**: Build scripts, benchmarks, installation helpers

---

## Key Patterns & Conventions

### Naming Conventions

- **Swift Files**: PascalCase (e.g., `ServerController.swift`)
- **Classes/Structs**: PascalCase (e.g., `ChatCompletionRequest`)
- **Functions/Properties**: camelCase (e.g., `getAvailableModels()`, `isRunning`)
- **Constants**: `UPPERCASE_SNAKE_CASE` (e.g., `OSU_DEBUG`, `OSU_MODELS_DIR`)
- **Enum Cases**: lowercase (e.g., `.user`, `.assistant`)

### Code Style

**From CONTRIBUTING.md:**
- Follow standard Swift naming and clarity guidelines
- Prefer clear, multi-line code over terse one-liners
- Add doc comments for non-obvious logic; avoid redundant comments
- Handle errors explicitly; avoid swallowing exceptions

### API Compatibility Patterns

1. **Request Path Normalization** (`Router.swift:327-343`)
   ```swift
   // Strips /v1, /api, /v1/api prefixes
   // Example: "/v1/chat/completions" → "/chat/completions"
   func normalize(_ path: String) -> String
   ```
   - Allows any OpenAI SDK to work without modification

2. **Dual Response Format Support**
   - OpenAI: SSE format via `/chat/completions`
   - Ollama: NDJSON format via `/chat`
   - Both support streaming with identical semantics

3. **Tool/Function Calling**
   - OpenAI-style `tools` array with `type: "function"`
   - Arguments as JSON-escaped strings
   - Robust parser handles code fences and formatting noise
   - Foundation Models tool calls mapped through Apple's interface

### Error Handling

- **OpenAI-compatible error responses** (`OpenAIError` struct)
- HTTP status codes for client/server errors
- Detailed error messages in response body
- Example:
  ```json
  {
    "error": {
      "message": "Model not found",
      "type": "invalid_request_error",
      "code": "model_not_found"
    }
  }
  ```

### Configuration Management

1. **Persistent Storage via `Codable`**
   - Graceful default fallbacks during decode
   - Backward compatibility on config updates
   - JSON files in `~/Library/Application Support/com.dinoki.osaurus/`

2. **Environment Variables for Runtime Control**
   - `OSU_DEBUG=1` - Enable debug logging
   - `OSU_DEBUG_PROMPT=1` - Log prompt construction
   - `OSU_PORT=XXXX` - Override configured port
   - `OSU_MODELS_DIR=/path` - Override models directory

---

## Development Workflows

### Building the Project

**Using Xcode:**
1. Open `osaurus.xcodeproj` in Xcode 16.4+
2. Select the `osaurus` target
3. Build and run (⌘R)

**Using Make:**
```bash
make cli           # Build CLI binary
make app           # Build SwiftUI app
make install-cli   # Install CLI symlink to /usr/local/bin
make serve         # Build and start server (PORT=XXXX, EXPOSE=1)
make status        # Check if server is running
make clean         # Remove build artifacts
```

### Running the Server

**From Xcode:**
- Run the `osaurus` target
- Configure port in UI (default: 1337)
- Click "Start"

**From CLI:**
```bash
# Start on localhost
osaurus serve --port 1337

# Start exposed on LAN (prompts for confirmation)
osaurus serve --port 1337 --expose

# Non-interactive (for scripts)
osaurus serve --port 1337 --expose --yes

# Check status
osaurus status

# Stop server
osaurus stop

# Open UI
osaurus ui
```

### Git Workflow

**From CONTRIBUTING.md:**
- Create feature branches from `main` (e.g., `feat/...`, `fix/...`, `docs/...`)
- Write clear, focused commits
- Prefer Conventional Commits where practical
- Keep PRs small and focused
- Link related issues (e.g., `Closes #123`)
- Include screenshots for UI changes
- Update README.md/docs when behavior changes

### Testing

**Location:** `/home/user/Osaurus-bison/osaurusTests/`

**Run tests:**
- In Xcode: ⌘U
- Ensure project builds before submitting PRs

**Example Test:**
```swift
@Test func serverConfiguration_portValidation() async throws {
  var cfg = ServerConfiguration.default
  cfg.port = 65_536
  #expect(cfg.isValidPort == false)  // Out of range
}

@Test func router_models_endpoint_returns_list() async throws {
  let router = Router()
  let resp = router.route(method: "GET", path: "/models")
  #expect(resp.status == .ok)
}
```

---

## API Structure

### Endpoint Categories

All endpoints support path normalization: `/v1`, `/api`, `/v1/api` prefixes are stripped.

#### Management Endpoints

| Method | Path | Response | Purpose |
|--------|------|----------|---------|
| `GET` | `/health` | JSON | Health check with timestamp |
| `GET` | `/` | Plain text | Basic status message |
| `HEAD` | `*` | - | Connection verification |

#### Model Discovery

| Method | Path | Response | Purpose |
|--------|------|----------|---------|
| `GET` | `/models` | JSON | OpenAI-compatible model list |
| `GET` | `/tags` | JSON | Ollama-compatible model list |

#### Chat/Inference

| Method | Path | Request | Response | Purpose |
|--------|------|---------|----------|---------|
| `POST` | `/chat/completions` | JSON | SSE | OpenAI-compatible streaming |
| `POST` | `/chat` | JSON | NDJSON | Ollama-compatible streaming |

### Request/Response Examples

**OpenAI-compatible Request:**
```json
{
  "model": "llama-3.2-3b-instruct-4bit",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": true,
  "temperature": 0.7,
  "max_tokens": 200,
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get weather by city",
        "parameters": {
          "type": "object",
          "properties": {"city": {"type": "string"}},
          "required": ["city"]
        }
      }
    }
  ],
  "tool_choice": "auto"
}
```

**Streaming Response (SSE):**
```
data: {"id":"chatcmpl-xyz","object":"chat.completion.chunk","created":1234567890,"model":"llama-3.2-3b-instruct-4bit","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-xyz",...,"choices":[{"index":0,"delta":{"content":" there"},...}]}

data: [DONE]
```

### CORS Support

- **Disabled by default** (no CORS headers)
- **Enable via UI**: Gear icon → Advanced Settings → CORS Settings
- **Configuration**: Comma-separated origins or `*` for any
- **Example**: `http://localhost:3000, https://app.example.com`

---

## Important Files & Entry Points

### Application Entry Points

| File | Lines | Purpose |
|------|-------|---------|
| `osaurus/Core/osaurusApp.swift` | - | SwiftUI App root |
| `osaurus/Core/AppDelegate.swift` | - | Menu bar UI, server lifecycle |
| `osaurusCLI/OsaurusCLI.swift` | 378 | CLI command parsing |

### Critical Controllers

| File | Lines | Key Responsibilities |
|------|-------|---------------------|
| `osaurus/Controllers/ServerController.swift` | 335 | SwiftNIO server lifecycle, port binding |
| `osaurus/Controllers/ModelManager.swift` | 839 | Model discovery, downloads, UI state |
| `osaurus/Controllers/HotKeyManager.swift` | 234 | Global hotkey registration |

### Core Services

| File | Lines | Purpose |
|------|-------|---------|
| `osaurus/Services/MLXService.swift` | 713 | ML model loading, inference, caching |
| `osaurus/Services/FoundationModelService.swift` | 473 | Apple Foundation Models integration |
| `osaurus/Services/OpenAICompatibleService.swift` | 502 | OpenAI API transformation |
| `osaurus/Services/SystemMonitorService.swift` | 130 | Real-time CPU/RAM monitoring |

### Networking Layer

| File | Lines | Purpose |
|------|-------|---------|
| `osaurus/Networking/HTTPHandler.swift` | 219 | SwiftNIO channel handler |
| `osaurus/Networking/Router.swift` | 345 | Path normalization & dispatch |
| `osaurus/Networking/AsyncHTTPHandler.swift` | 505+ | Streaming handler (SSE/NDJSON) |

### Data Models

| File | Purpose |
|------|---------|
| `osaurus/Models/OpenAIAPI.swift` | OpenAI-compatible DTOs |
| `osaurus/Models/ServerConfiguration.swift` | Server settings |
| `osaurus/Models/ChatConfiguration.swift` | Chat hotkey & system prompt |
| `osaurus/Models/ResponseWriters.swift` | SSE & NDJSON formatters |

### Views

| File | Lines | Purpose |
|------|-------|---------|
| `osaurus/Views/ContentView.swift` | - | Main server control UI |
| `osaurus/Views/ChatView.swift` | 1,062 | In-app chat overlay |
| `osaurus/Views/ModelDownloadView.swift` | - | Model manager UI |

---

## Configuration Management

### Application Configuration

**Location:** `~/Library/Application Support/com.dinoki.osaurus/`

**Files:**
- `ServerConfiguration.json` - Server settings (port, CORS, threading)
- `ChatConfiguration.json` - Chat hotkey and system prompt
- `SharedConfiguration/<instanceId>/configuration.json` - Multi-app discovery

**Example ServerConfiguration.json:**
```json
{
  "port": 1337,
  "allowedOrigins": ["http://localhost:3000"],
  "exposeToNetwork": false,
  "kvCacheQuantization": 8,
  "prefillStepSize": 512
}
```

### Model Storage

**Default:** `~/MLXModels/`
**Override:** `OSU_MODELS_DIR` environment variable

**Structure:**
```
~/MLXModels/
├── llama-3.2-3b-instruct-4bit/
│   ├── config.json
│   ├── tokenizer.json
│   └── model.safetensors
└── qwen-2.5-7b-instruct-4bit/
    └── ...
```

### LLM Proxy Configuration

**File:** `/home/user/Osaurus-bison/llm-proxy/config.yaml`

**Key Features:**
- Priority-based provider ordering (1 = highest)
- Environment variable interpolation (`${VAR_NAME}`)
- Automatic rotation on HTTP 429 (rate limits)

**Example:**
```yaml
providers:
  - name: "groq"
    priority: 1
    base_url: "https://api.groq.com/openai"
    api_key: "${GROQ_API_KEY}"
    model: "llama-3.3-70b-versatile"

  - name: "cerebras"
    priority: 2
    base_url: "https://api.cerebras.ai"
    api_key: "${CEREBRAS_API_KEY}"
    model: "qwen-3-235b-a22b-instruct-2507"
```

---

## Testing Guidelines

### Test Structure

**Location:** `/home/user/Osaurus-bison/osaurusTests/`

**Test Files:**
- `osaurusTests.swift` - Core model and routing tests
- `MLXModelTests.swift` - Model configuration tests
- `ModelManagerTests.swift` - Model discovery logic
- `SearchServiceTests.swift` - Search functionality
- `ServerConfigurationStoreTests.swift` - Config persistence
- `ServerControllerConfigLoadingTests.swift` - Server startup
- `ModelManagerResolveTests.swift` - Model resolution

### Writing Tests

**Framework:** Swift Testing (modern `@Test` syntax)

**Example:**
```swift
import Testing
@testable import osaurus

@Test func serverConfiguration_portValidation() async throws {
  var cfg = ServerConfiguration.default
  cfg.port = 65_536
  #expect(cfg.isValidPort == false)  // Out of range
}

@Test func router_normalizesPathCorrectly() async throws {
  let router = Router()
  #expect(router.normalize("/v1/chat/completions") == "/chat/completions")
  #expect(router.normalize("/api/models") == "/models")
}
```

### Running Tests

```bash
# In Xcode
⌘U

# CLI (if available)
xcodebuild test -scheme osaurus -project osaurus.xcodeproj
```

---

## Common Tasks

### Adding a New API Endpoint

1. **Define route in `Router.swift`:**
   ```swift
   case ("GET", "/my-endpoint"):
     return myEndpointHandler(body: body)
   ```

2. **Implement handler:**
   ```swift
   private func myEndpointHandler(body: Data) -> (
     status: HTTPResponseStatus,
     headers: [(String, String)],
     body: String
   ) {
     let response = ["status": "ok"]
     let jsonData = try! JSONEncoder().encode(response)
     return (
       .ok,
       [("Content-Type", "application/json")],
       String(data: jsonData, encoding: .utf8)!
     )
   }
   ```

3. **Add tests:**
   ```swift
   @Test func myEndpoint_returnsOk() async throws {
     let router = Router()
     let resp = router.route(method: "GET", path: "/my-endpoint")
     #expect(resp.status == .ok)
   }
   ```

### Adding a New Service

1. **Create service file in `osaurus/Services/`:**
   ```swift
   import Foundation

   final class MyService {
     static let shared = MyService()
     private init() {}

     func performAction() async throws -> String {
       // Implementation
       return "result"
     }
   }
   ```

2. **Inject into controllers if needed:**
   ```swift
   class ServerController: ObservableObject {
     private let myService = MyService.shared

     func handleRequest() async {
       let result = try? await myService.performAction()
       // ...
     }
   }
   ```

3. **Add tests:**
   ```swift
   @Test func myService_performsAction() async throws {
     let service = MyService.shared
     let result = try await service.performAction()
     #expect(result == "expected")
   }
   ```

### Adding Model Support

1. **Update `MLXService.swift`** to recognize new model architecture
2. **Add to suggested models in `ModelManager.swift`**
3. **Update documentation in README.md**
4. **Test with actual model download and inference**

### Modifying UI

1. **Edit SwiftUI view in `osaurus/Views/`**
2. **Follow Theme.swift for colors and styles:**
   ```swift
   Text("Hello")
     .foregroundColor(Theme.textPrimary)
     .font(.system(size: 14))
   ```
3. **Use `@EnvironmentObject` for shared state:**
   ```swift
   @EnvironmentObject var serverController: ServerController

   if serverController.isRunning {
     Text("Server is running")
   }
   ```
4. **Include screenshots in PR**

### Updating Dependencies

1. **Swift packages:** Update in Xcode (File → Swift Packages → Update to Latest Package Versions)
2. **Python packages:** Update `llm-proxy/requirements.txt`
3. **Document breaking changes in PR description**

---

## Things to Avoid

### Don't Do This

1. **Don't support Intel Macs**
   - Project is Apple Silicon only
   - MLX requires M-series chips

2. **Don't add authentication to HTTP server**
   - Designed for localhost use
   - Users should use reverse proxy if needed

3. **Don't manually assemble prompts**
   - MLX `ChatSession` handles prompt templating
   - Use MLX's built-in tool call processing

4. **Don't skip error handling**
   - Always handle errors explicitly
   - Return meaningful error messages to clients

5. **Don't ignore path normalization**
   - Always use `Router.normalize()` for new endpoints
   - Ensures compatibility with various API clients

6. **Don't hardcode configuration**
   - Use `ServerConfiguration` and `ChatConfiguration`
   - Support environment variable overrides

7. **Don't break OpenAI API compatibility**
   - Match OpenAI response schemas exactly
   - Test with official OpenAI SDKs

8. **Don't commit credentials**
   - Use environment variables for API keys
   - Check `.gitignore` before adding new files

### Performance Considerations

1. **Use NSCache for model caching** (not Dictionary)
2. **Prefer semaphores over locks** for concurrency
3. **Stream responses** - don't buffer entire output
4. **Use IkigaJSON** for performance-critical JSON ops
5. **Consider KV cache quantization** for memory efficiency

### Code Quality

1. **Write clear commit messages**
   - Example: "Add CORS support to streaming endpoints"
   - Not: "Fix stuff"

2. **Keep PRs focused**
   - One feature/fix per PR
   - Easier to review and merge

3. **Update documentation**
   - README.md for user-facing changes
   - CLAUDE.md for architectural changes
   - Code comments for non-obvious logic

4. **Test on actual hardware**
   - Apple Silicon Mac required
   - Test with real models, not just mocks

---

## Resources

### Documentation

- **Main README:** `/home/user/Osaurus-bison/README.md`
- **Contributing Guide:** `/home/user/Osaurus-bison/CONTRIBUTING.md`
- **OpenAI API Guide:** `/home/user/Osaurus-bison/OpenAI_API_GUIDE.md`
- **Shared Config Guide:** `/home/user/Osaurus-bison/SHARED_CONFIGURATION_GUIDE.md`
- **LLM Proxy Guide:** `/home/user/Osaurus-bison/llm-proxy/README.md`
- **Online Docs:** https://docs.dinoki.ai/

### Key External Resources

- **MLX Framework:** https://github.com/ml-explore/mlx
- **MLX-Swift:** https://github.com/ml-explore/mlx-swift
- **SwiftNIO:** https://github.com/apple/swift-nio
- **OpenAI API Reference:** https://platform.openai.com/docs/api-reference
- **Ollama API Reference:** https://github.com/ollama/ollama/blob/main/docs/api.md

### Community

- **Discord:** https://discord.gg/dinoki
- **GitHub Issues:** https://github.com/dinoki-ai/osaurus/issues
- **Discussions:** https://github.com/dinoki-ai/osaurus/discussions

### File Path Quick Reference

**Entry Points:**
- App: `/home/user/Osaurus-bison/osaurus/Core/osaurusApp.swift`
- CLI: `/home/user/Osaurus-bison/osaurusCLI/OsaurusCLI.swift`

**Core Services:**
- MLX: `/home/user/Osaurus-bison/osaurus/Services/MLXService.swift`
- Foundation: `/home/user/Osaurus-bison/osaurus/Services/FoundationModelService.swift`

**Networking:**
- Router: `/home/user/Osaurus-bison/osaurus/Networking/Router.swift`
- Handler: `/home/user/Osaurus-bison/osaurus/Networking/AsyncHTTPHandler.swift`

**Configuration:**
- Server: `~/Library/Application Support/com.dinoki.osaurus/ServerConfiguration.json`
- Chat: `~/Library/Application Support/com.dinoki.osaurus/ChatConfiguration.json`
- Models: `~/MLXModels/` (or `$OSU_MODELS_DIR`)

---

## Request Flow Example

Understanding the complete request flow helps when debugging or adding features:

```
1. HTTP Request arrives at localhost:1337
   ↓
2. SwiftNIO → HTTPHandler.channelRead()
   File: osaurus/Networking/HTTPHandler.swift:219
   ↓
3. Router.route(method, path, body)
   File: osaurus/Networking/Router.swift:345
   - Path normalization: "/v1/chat/completions" → "/chat/completions"
   ↓
4. AsyncHTTPHandler.handleChatCompletion()
   File: osaurus/Networking/AsyncHTTPHandler.swift:505+
   - Parse OpenAI request
   - Validate parameters
   ↓
5. ModelServiceRouter.resolve(modelName)
   - Determine: Foundation or MLX?
   - Return appropriate service
   ↓
6. Service.generate() - MLXService or FoundationModelService
   File: osaurus/Services/MLXService.swift:713
   File: osaurus/Services/FoundationModelService.swift:473
   - Load model (if not cached)
   - Run inference
   - Stream tokens
   ↓
7. ResponseWriter.write(token)
   File: osaurus/Models/ResponseWriters.swift
   - Format: SSE or NDJSON
   - Write to NIOCore channel
   ↓
8. Client receives streaming response
```

---

## Environment Variables Reference

| Variable | Default | Purpose |
|----------|---------|---------|
| `OSU_DEBUG` | `0` | Enable debug logging |
| `OSU_DEBUG_PROMPT` | `0` | Log prompt construction |
| `OSU_PORT` | `1337` | Override server port |
| `OSU_MODELS_DIR` | `~/MLXModels` | Override models directory |

**Usage:**
```bash
# Enable debug logging
OSU_DEBUG=1 osaurus serve

# Use custom models directory
OSU_MODELS_DIR=/Volumes/External/Models osaurus serve

# Custom port
OSU_PORT=8080 osaurus serve
```

---

## Benchmarking

**Scripts:** `/home/user/Osaurus-bison/scripts/`
- `run_bench.sh` - Main benchmark runner
- `benchmark_models.py` - Python benchmark script

**Results:** `/home/user/Osaurus-bison/results/`
- `osaurus-vs-ollama-lmstudio-batch.results.json`
- `osaurus-vs-ollama-lmstudio-batch.summary.json`

**Run benchmarks:**
```bash
cd /home/user/Osaurus-bison
./scripts/run_bench.sh
```

**Metrics:**
- TTFT (Time To First Token)
- Total completion time
- Characters per second
- Success rate

---

## Conclusion

This guide provides a comprehensive overview of the Osaurus codebase for AI assistants. When working on this project:

1. **Understand the architecture** - Service-oriented with clear separation
2. **Follow conventions** - Swift style, API compatibility, error handling
3. **Test thoroughly** - Unit tests, integration tests, real hardware
4. **Document changes** - Update README, CLAUDE.md, code comments
5. **Maintain compatibility** - OpenAI API, Ollama API, existing clients

**Remember:** This is a macOS-native app optimized for Apple Silicon. Performance, user experience, and API compatibility are top priorities.

For questions or clarifications, refer to:
- GitHub Issues: https://github.com/dinoki-ai/osaurus/issues
- Discord: https://discord.gg/dinoki
- Documentation: https://docs.dinoki.ai/

---

**Last Updated:** 2025-11-17
**Maintainer:** Dinoki Labs (https://dinoki.ai)
**License:** See LICENSE file
