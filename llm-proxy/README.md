# LLM Rotation Proxy

An OpenAI-compatible API proxy that automatically rotates between multiple LLM providers when rate limits are hit.

## Features

- ✅ **Priority-based provider selection** - Always tries higher priority providers first
- ✅ **Automatic rate limit detection** - Detects HTTP 429 errors across all providers
- ✅ **Request counting** - Tracks requests per provider with daily resets
- ✅ **Smart retry logic** - Respects `retry-after` headers from providers
- ✅ **OpenAI-compatible API** - Works with any OpenAI-compatible client
- ✅ **Health & status endpoints** - Monitor which providers are available
- ✅ **Streaming support** - Handles both streaming and non-streaming requests

## Supported Providers

- Grok (X.AI)
- Cerebras
- Google Gemini
- OpenAI
- Mistral AI
- Together AI

## Installation

### 1. Install Python dependencies

```bash
cd llm-proxy
pip3 install -r requirements.txt
```

### 2. Set API Keys (Environment Variables)

**For security, API keys are read from environment variables!**

Create a `.env` file:

```bash
cp .env.example .env
```

Edit `.env` and add your API keys:

```bash
GROK_API_KEY=your-actual-key-here
CEREBRAS_API_KEY=your-actual-key-here
GEMINI_API_KEY=your-actual-key-here
# Add only the providers you want to use
```

Load the environment variables:

```bash
export $(cat .env | xargs)
```

Or use a tool like [direnv](https://direnv.net/) for automatic loading.

### 3. Run the proxy

```bash
python3 proxy_server.py
```

The proxy will start on `http://localhost:8000`

## Usage

### From your macOS app

Simply point your OpenAI client to the local proxy:

```swift
let apiURL = "http://localhost:8000/v1/chat/completions"
```

### Test with curl

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "default",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Check status

```bash
# Health check
curl http://localhost:8000/health

# Provider status
curl http://localhost:8000/status

# Statistics
curl http://localhost:8000/stats
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/status` | GET | Get provider status and request counts |
| `/stats` | GET | Get statistics (alias for /status) |
| `/reload` | POST | Reload configuration without restart |
| `/v1/chat/completions` | POST | OpenAI chat completions (main endpoint) |
| `/v1/completions` | POST | OpenAI completions (legacy) |

## How It Works

1. **Request comes in** → Proxy receives OpenAI-compatible request
2. **Provider selection** → Selects highest priority available provider
3. **Make request** → Forwards request to selected provider
4. **Rate limit detection** → If 429 error, marks provider as rate-limited
5. **Auto-rotation** → Tries next available provider automatically
6. **Return response** → Returns successful response to client

## Response Headers

The proxy adds these headers to responses:

- `X-Provider` - Which provider was used (e.g., "grok", "cerebras")
- `X-Model` - Which model was used

## Request Tracking

Each provider tracks:
- **Request count** (resets daily)
- **Rate limit status** (temporarily disabled when rate limited)
- **Error count** (consecutive errors)
- **Token usage** (when available from provider response)

## Configuration

### Provider Priority

Lower numbers = higher priority (tried first):

```yaml
providers:
  - name: "grok"
    priority: 1    # Tried first
  - name: "cerebras"
    priority: 2    # Tried second if grok is rate-limited
```

### Disabling Providers

Comment out or remove providers you don't want to use:

```yaml
providers:
  - name: "grok"
    priority: 1
    # ... config

  # - name: "openai"  # Disabled
  #   priority: 4
```

## Troubleshooting

### Check if proxy is running

```bash
curl http://localhost:8000/health
```

### View logs

The proxy logs all requests and provider selections to stdout:

```
2025-11-06 10:30:00 - INFO - Selected provider: grok (priority 1)
2025-11-06 10:30:01 - INFO - grok: Request successful (status 200)
```

### All providers rate limited

Check status to see when they'll be available again:

```bash
curl http://localhost:8000/status
```

### Reload configuration

After editing `config.yaml`:

```bash
curl -X POST http://localhost:8000/reload
```

## Development

### Project Structure

```
llm-proxy/
├── proxy_server.py      # Main FastAPI server
├── providers.py         # Provider management
├── config.yaml          # Configuration file
├── requirements.txt     # Python dependencies
└── README.md           # This file
```

### Adding New Providers

1. Add provider to `config.yaml`
2. Ensure the provider uses OpenAI-compatible API
3. Set appropriate priority
4. Restart or reload the proxy

## Security

**API Key Protection:**
- ✅ API keys are stored as **environment variables**, never in config files
- ✅ `.env` files are automatically excluded from git via `.gitignore`
- ✅ `config.yaml` only contains provider names and URLs, no secrets
- ✅ Keys are read at runtime using `os.getenv()`

**Network Security:**
- ✅ Proxy binds to `127.0.0.1` (localhost only)
- ✅ Not accessible from network or internet
- ✅ No authentication needed (local-only access)

**Best Practices:**
1. Never commit `.env` files to version control
2. Use different API keys for development and production
3. Rotate keys periodically
4. Store `.env` file with restricted permissions (chmod 600)

## License

MIT License - See main project LICENSE file
