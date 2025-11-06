# LLM Rotation Proxy - Integration Guide for Osaurus

This guide shows how to integrate the LLM rotation proxy into your Osaurus macOS app.

## Overview

The proxy sits between your app and multiple LLM providers, automatically rotating when rate limits are hit:

```
┌─────────────┐
│ Osaurus App │
└──────┬──────┘
       │ http://localhost:8000
       ↓
┌────────────────────┐
│  Rotation Proxy    │
│  (Python FastAPI)  │
└─────────┬──────────┘
          │
    ┌─────┼─────┬──────┬──────┐
    ↓     ↓     ↓      ↓      ↓
  Grok Cerebras Gemini OpenAI Mistral ...
```

## Setup Steps

### 1. Install the Proxy

```bash
cd llm-proxy
./install.sh
```

This installs the required Python dependencies (FastAPI, httpx, etc.).

### 2. Set API Keys (Environment Variables)

**For security, API keys are read from environment variables, not stored in config!**

Create a `.env` file:

```bash
cd llm-proxy
cp .env.example .env
```

Edit `.env` and add your API keys:

```bash
# .env
GROK_API_KEY=xai-abc123...
CEREBRAS_API_KEY=csk-abc123...
GEMINI_API_KEY=AIza...
# Add only the ones you have
```

**Important:** When your Swift app starts the proxy, it needs to pass these environment variables. See `ProxyManager.swift` for how to do this.

You can:
- Add only the providers you have keys for (others are skipped automatically)
- Adjust priorities in `config.yaml` (1 = highest)
- Change model names if needed

### 3. Test the Proxy Manually

Start the proxy:

```bash
cd llm-proxy
python3 proxy_server.py
```

In another terminal, test it:

```bash
# Health check
curl http://localhost:8000/health

# Status
curl http://localhost:8000/status

# Test request
python3 test_proxy.py
```

If tests pass, you're ready to integrate! Press Ctrl+C to stop the proxy.

### 4. Add ProxyManager to Your Xcode Project

1. **Add the Swift file:**
   - Drag `llm-proxy/ProxyManager.swift` into your Xcode project
   - Make sure it's added to your app target

2. **Bundle the proxy with your app:**
   - In Xcode, add the `llm-proxy` folder to your project
   - In Build Phases → Copy Bundle Resources, add:
     - `proxy_server.py`
     - `providers.py`
     - `config.yaml`
     - `requirements.txt`

### 5. Update Your App Code

#### A. Start proxy on app launch

In your `AppDelegate.swift` or main `App.swift`:

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Start the proxy
        ProxyManager.shared.ensureProxyRunning { success, error in
            if success {
                print("✓ LLM Proxy ready")
                // Continue with your app initialization
                self.setupApp()
            } else {
                // Show error to user
                self.showProxyError(error)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean shutdown
        ProxyManager.shared.stopProxy()
    }

    private func showProxyError(_ error: String?) {
        let alert = NSAlert()
        alert.messageText = "Failed to start LLM service"
        alert.informativeText = error ?? "Unknown error"
        alert.alertStyle = .critical
        alert.runModal()
    }
}
```

#### B. Update your API calls

Change your OpenAI API endpoint from the provider to the local proxy:

**Before:**
```swift
let url = URL(string: "https://api.openai.com/v1/chat/completions")!
```

**After:**
```swift
let url = URL(string: "http://localhost:8000/v1/chat/completions")!
```

**That's it!** The proxy handles everything else transparently.

Your existing code should work as-is because the proxy is OpenAI-compatible.

#### C. Optional: Show provider info in UI

You can display which provider is being used:

```swift
// After making a request, check the response headers
if let httpResponse = response as? HTTPURLResponse {
    let provider = httpResponse.value(forHTTPHeaderField: "X-Provider")
    let model = httpResponse.value(forHTTPHeaderField: "X-Model")
    print("Used provider: \(provider ?? "unknown"), model: \(model ?? "unknown")")
}
```

#### D. Optional: Show request counts in settings

Add a settings panel showing provider statistics:

```swift
func refreshProviderStats() {
    ProxyManager.shared.getStatus { status in
        guard let providers = status?["providers"] as? [[String: Any]] else {
            return
        }

        for provider in providers {
            let name = provider["name"] as? String ?? "unknown"
            let requests = provider["request_count"] as? Int ?? 0
            let isLimited = provider["is_rate_limited"] as? Bool ?? false

            // Update UI
            print("Provider \(name): \(requests) requests today, limited: \(isLimited)")
        }
    }
}
```

### 6. Build and Test

1. Build your app in Xcode
2. Run it
3. Check the console - you should see:
   ```
   Starting proxy server...
   ✓ Proxy started successfully
   ```
4. Make an LLM request from your app
5. Check which provider was used in the response headers

## First-Time User Experience

When a user runs your app for the first time:

1. ✅ App launches
2. ✅ Proxy auto-starts (takes ~1 second)
3. ✅ Everything works immediately
4. ✅ No manual setup required!

The user doesn't need to know the proxy exists.

## Deployment Considerations

### Option 1: Bundle Python with App (Recommended)

Use PyInstaller to create a standalone binary:

```bash
pip3 install pyinstaller
cd llm-proxy
pyinstaller --onefile --add-data "config.yaml:." proxy_server.py
```

This creates `dist/proxy_server` - a single binary with no Python dependency!

Update `ProxyManager.swift`:

```swift
private let proxyExecutable: String = {
    if let bundlePath = Bundle.main.resourcePath {
        return "\(bundlePath)/proxy_server"  // Single binary
    }
    // fallback...
}()
```

### Option 2: Require Python 3

macOS 12+ includes Python 3 by default, so you can just use:

```swift
process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
```

Check on first launch and show instructions if not found.

## Troubleshooting

### Proxy won't start

**Check logs:**
```swift
// In ProxyManager, the error output is captured
// Check the console for errors like:
// [Proxy Error] ModuleNotFoundError: No module named 'fastapi'
```

**Solution:** Run `pip3 install -r requirements.txt`

### Port already in use

If port 8000 is taken, change it in:
- `proxy_server.py`: `uvicorn.run(..., port=8000)` → `port=8001`
- `ProxyManager.swift`: Update URLs to use `:8001`

### API keys not working

Verify `config.yaml` has correct keys and is being loaded:

```bash
curl http://localhost:8000/status
```

Check if providers are configured correctly.

### All providers rate limited

This is expected! The proxy is working. Just wait for the cooldown period.

Check when providers will be available:

```bash
curl http://localhost:8000/status | python3 -m json.tool
```

Look for `rate_limited_until` timestamps.

## Advanced Features

### Dynamic Configuration

Users can reload config without restarting:

```swift
ProxyManager.shared.reloadConfig { success in
    if success {
        print("✓ Configuration reloaded")
    }
}
```

### Request Tracking

View per-provider request counts:

```bash
curl http://localhost:8000/stats
```

Response:
```json
{
  "providers": [
    {
      "name": "grok",
      "request_count": 42,
      "is_rate_limited": false,
      "total_tokens_used": 15000
    }
  ]
}
```

### Logging

Proxy logs go to stdout. To save them:

```swift
// In ProxyManager.startProxy()
let logFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("llm-proxy.log")

let logHandle = try? FileHandle(forWritingTo: logFile)
process.standardOutput = logHandle
process.standardError = logHandle
```

## Security Notes

1. **API Keys**: Store in config.yaml, which should be in user's Application Support directory
2. **Local Only**: Proxy binds to `127.0.0.1` - only accessible from the local machine
3. **No Authentication**: Since it's local-only, no auth is needed

## Performance

- **Startup time**: ~0.5-1 second
- **Request overhead**: <50ms (local HTTP)
- **Memory usage**: ~50MB
- **CPU usage**: Minimal (only active during requests)

## Next Steps

1. Test with a single provider first
2. Add more providers gradually
3. Monitor request counts to optimize priorities
4. Consider adding a UI panel to show provider status

## Questions?

See the main README.md for more details, or check the code comments in:
- `proxy_server.py` - Main server logic
- `providers.py` - Provider management
- `ProxyManager.swift` - Swift integration

Happy coding! 🚀
