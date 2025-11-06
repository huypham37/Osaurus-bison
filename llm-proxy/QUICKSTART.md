# LLM Rotation Proxy - Quick Start

Get up and running in 5 minutes!

## What This Does

Automatically rotates between multiple free-tier LLM providers when you hit rate limits. Never pay for LLM subscriptions again!

**Supported providers:**
- Grok (X.AI)
- Cerebras
- Google Gemini
- OpenAI
- Mistral AI
- Together AI

## Installation

### Step 1: Install Dependencies

```bash
cd llm-proxy
./install.sh
```

### Step 2: Set Your API Keys (Environment Variables)

For security, API keys are stored as environment variables, not in config files!

**Create a `.env` file:**

```bash
cp .env.example .env
nano .env  # or use your favorite editor
```

**Add your API keys:**

```bash
# .env file
GROK_API_KEY=your-actual-key-here
CEREBRAS_API_KEY=your-actual-key-here
GEMINI_API_KEY=your-actual-key-here
# ... add others as needed
```

**Load environment variables:**

```bash
export $(cat .env | xargs)
```

**Tip:** You don't need all of them! Providers without keys will be automatically skipped.

Get free API keys from:
- Grok: https://x.ai/api
- Cerebras: https://cloud.cerebras.ai/
- Gemini: https://makersuite.google.com/app/apikey
- OpenAI: https://platform.openai.com/api-keys
- Mistral: https://console.mistral.ai/
- Together: https://api.together.xyz/

### Step 3: Test It

```bash
# Start the proxy
python3 proxy_server.py
```

In another terminal:

```bash
# Run tests
python3 test_proxy.py
```

You should see:
```
✓ PASS - Health Check
✓ PASS - Status Endpoint
✓ PASS - Chat Completion
```

Press Ctrl+C to stop the proxy.

## Integration with Osaurus App

### Quick Integration (3 steps)

1. **Add ProxyManager to your Xcode project:**
   ```
   Drag ProxyManager.swift into Xcode
   ```

2. **Start proxy on app launch:**
   ```swift
   // In AppDelegate.swift
   func applicationDidFinishLaunching() {
       ProxyManager.shared.ensureProxyRunning { success, error in
           if success {
               print("✓ Ready!")
           }
       }
   }
   ```

3. **Update your API endpoint:**
   ```swift
   // Change from:
   let url = "https://api.openai.com/v1/chat/completions"

   // To:
   let url = "http://localhost:8000/v1/chat/completions"
   ```

**Done!** Your app now automatically rotates providers.

See `INTEGRATION_GUIDE.md` for detailed instructions.

## Usage

### Manual Testing

```bash
# Start the proxy
python3 proxy_server.py
```

The proxy runs on `http://localhost:8000`

### Check Status

```bash
# Health check
curl http://localhost:8000/health

# See which providers are available
curl http://localhost:8000/status
```

### Make a Request

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "default",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## How It Works

```
Your request
    ↓
Try Provider 1 (highest priority)
    ├─ Success? → Return response ✓
    └─ Rate limited (429)? → Try Provider 2
            ├─ Success? → Return response ✓
            └─ Rate limited? → Try Provider 3
                    └─ ... and so on
```

## Configuration

### Adjust Provider Priority

Lower number = higher priority (tried first):

```yaml
providers:
  - name: "grok"
    priority: 1      # Tried first

  - name: "gemini"
    priority: 2      # Tried second
```

### Disable a Provider

Just comment it out:

```yaml
  # - name: "openai"    # Disabled
  #   priority: 4
```

### Use Different Models

Change the `model` field:

```yaml
  - name: "cerebras"
    model: "llama3.1-70b"  # Use larger model
```

## Monitoring

### View Request Counts

```bash
curl http://localhost:8000/stats | python3 -m json.tool
```

Output:
```json
{
  "providers": [
    {
      "name": "grok",
      "request_count": 42,
      "is_rate_limited": false,
      "last_reset": "2025-11-06"
    }
  ]
}
```

Request counts reset daily.

### Check Rate Limits

```bash
curl http://localhost:8000/status
```

Shows which providers are currently rate-limited and when they'll be available.

## Troubleshooting

### "Connection refused"

The proxy isn't running. Start it:
```bash
python3 proxy_server.py
```

### "All providers unavailable"

All providers are rate-limited. Wait a few minutes or check your API keys:
```bash
curl http://localhost:8000/status
```

### "ModuleNotFoundError"

Install dependencies:
```bash
pip3 install -r requirements.txt
```

## Tips

1. **Prioritize fastest providers first** - They'll give the best user experience
2. **Check free tier limits** - Each provider has different daily limits
3. **Monitor request counts** - Use `/stats` to see which providers you use most
4. **Add all providers** - More providers = less downtime
5. **Test individually** - Verify each API key works before adding to production

## Files Overview

```
llm-proxy/
├── proxy_server.py          # Main server (run this)
├── providers.py             # Provider management logic
├── config.yaml              # Your configuration (edit this)
├── ProxyManager.swift       # Swift integration for your app
├── requirements.txt         # Python dependencies
├── install.sh               # Installation script
├── test_proxy.py            # Test script
├── README.md                # Full documentation
├── INTEGRATION_GUIDE.md     # Detailed integration guide
└── QUICKSTART.md            # This file
```

## Next Steps

1. ✅ Install and test the proxy (you just did this!)
2. ✅ Add to your Osaurus app (see INTEGRATION_GUIDE.md)
3. ✅ Test with real API keys
4. ✅ Monitor usage and adjust priorities
5. ✅ Enjoy unlimited LLM access! 🎉

## Need Help?

- Check `README.md` for full documentation
- Check `INTEGRATION_GUIDE.md` for app integration details
- Review code comments in `proxy_server.py` and `providers.py`

Happy coding! 🚀
