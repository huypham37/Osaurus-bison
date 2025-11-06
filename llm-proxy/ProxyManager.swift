//
//  ProxyManager.swift
//  LLM Rotation Proxy Manager for macOS
//
//  This file manages the Python proxy server lifecycle from your Swift app
//

import Foundation

/// Manages the LLM rotation proxy server lifecycle
class ProxyManager {

    // MARK: - Properties

    static let shared = ProxyManager()

    private var proxyProcess: Process?
    private let proxyURL = URL(string: "http://localhost:8000")!
    private let healthCheckURL = URL(string: "http://localhost:8000/health")!

    // Path to the proxy server script
    // Update this path based on where you install the proxy
    private let proxyScriptPath: String

    // MARK: - Initialization

    private init() {
        // Get path to proxy script
        // Option 1: Bundled with app
        if let bundlePath = Bundle.main.resourcePath {
            proxyScriptPath = "\(bundlePath)/llm-proxy/proxy_server.py"
        } else {
            // Option 2: In Application Support
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            proxyScriptPath = appSupport.appendingPathComponent("Osaurus/llm-proxy/proxy_server.py").path
        }
    }

    // MARK: - Public Methods

    /// Ensure the proxy is running, start it if needed
    func ensureProxyRunning(completion: @escaping (Bool, String?) -> Void) {
        // First check if it's already running
        if isProxyRunning() {
            print("✓ Proxy already running")
            completion(true, nil)
            return
        }

        print("Starting proxy server...")

        // Start the proxy
        startProxy { success, error in
            if success {
                // Wait a moment for startup
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // Verify it started
                    if self.isProxyRunning() {
                        print("✓ Proxy started successfully")
                        completion(true, nil)
                    } else {
                        let error = "Proxy started but health check failed"
                        print("❌ \(error)")
                        completion(false, error)
                    }
                }
            } else {
                print("❌ Failed to start proxy: \(error ?? "unknown error")")
                completion(false, error)
            }
        }
    }

    /// Check if the proxy is running by hitting the health endpoint
    func isProxyRunning() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var running = false

        let task = URLSession.shared.dataTask(with: healthCheckURL) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                running = httpResponse.statusCode == 200

                // Parse response to verify it's our proxy
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    running = running && json["status"] as? String == "healthy"
                }
            }
            semaphore.signal()
        }

        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.0)

        return running
    }

    /// Start the proxy server
    func startProxy(completion: @escaping (Bool, String?) -> Void) {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: proxyScriptPath) else {
            completion(false, "Proxy script not found at: \(proxyScriptPath)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [proxyScriptPath]

        // Set up logging (optional)
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Log output in background
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("[Proxy] \(output.trimmingCharacters(in: .newlines))")
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("[Proxy Error] \(output.trimmingCharacters(in: .newlines))")
            }
        }

        do {
            try process.run()
            self.proxyProcess = process
            completion(true, nil)
        } catch {
            completion(false, "Failed to start process: \(error.localizedDescription)")
        }
    }

    /// Stop the proxy server
    func stopProxy() {
        guard let process = proxyProcess, process.isRunning else {
            print("Proxy is not running")
            return
        }

        print("Stopping proxy server...")
        process.terminate()

        // Wait for termination
        process.waitUntilExit()

        proxyProcess = nil
        print("✓ Proxy stopped")
    }

    /// Get proxy status and statistics
    func getStatus(completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: "http://localhost:8000/status") else {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(json)
        }
        task.resume()
    }

    /// Reload proxy configuration
    func reloadConfig(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://localhost:8000/reload") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            completion(success)
        }
        task.resume()
    }
}

// MARK: - App Integration Example

/*
 Usage in your App:

 // 1. In your AppDelegate or App struct:

 func applicationDidFinishLaunching(_ notification: Notification) {
     ProxyManager.shared.ensureProxyRunning { success, error in
         if success {
             print("✓ Ready to make LLM requests")
             // Continue with app initialization
         } else {
             // Show error to user
             self.showProxyError(error)
         }
     }
 }

 func applicationWillTerminate(_ notification: Notification) {
     ProxyManager.shared.stopProxy()
 }

 // 2. In your API client, use the local proxy:

 let url = URL(string: "http://localhost:8000/v1/chat/completions")!
 var request = URLRequest(url: url)
 request.httpMethod = "POST"
 request.setValue("application/json", forHTTPHeaderField: "Content-Type")

 let body: [String: Any] = [
     "model": "default",
     "messages": [
         ["role": "user", "content": "Hello!"]
     ]
 ]
 request.httpBody = try? JSONSerialization.data(withJSONObject: body)

 // Make request...

 // 3. Optional: Show status in UI

 ProxyManager.shared.getStatus { status in
     if let providers = status?["providers"] as? [[String: Any]] {
         for provider in providers {
             let name = provider["name"] as? String ?? "unknown"
             let requests = provider["request_count"] as? Int ?? 0
             let limited = provider["is_rate_limited"] as? Bool ?? false

             print("\(name): \(requests) requests, limited: \(limited)")
         }
     }
 }
 */
