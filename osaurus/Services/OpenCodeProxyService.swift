//
//  OpenCodeProxyService.swift
//  osaurus
//
//  Created for OpenCode integration
//

import Foundation

// MARK: - OpenCode API Models

/// Represents an OpenCode provider (e.g., GitHub Copilot, Anthropic, OpenAI)
struct OpenCodeProvider: Codable {
    let id: String
    let name: String
    let models: [String: OpenCodeModel]
}

/// Represents a model within an OpenCode provider
struct OpenCodeModel: Codable {
    let id: String
    let name: String?
    let cost: OpenCodeModelCost?
}

struct OpenCodeModelCost: Codable {
    let input: Double
    let output: Double
}

/// Response from /config/providers endpoint
struct OpenCodeProvidersResponse: Codable {
    let providers: [OpenCodeProvider]
    let `default`: [String: String]
}

/// Request body for creating a session
struct OpenCodeSessionRequest: Codable {
    let parentID: String?
    let title: String?
}

/// Session info from OpenCode
struct OpenCodeSession: Codable {
    let id: String
    let title: String?
    let createdAt: String?
}

/// Request body for sending a message
struct OpenCodeMessageRequest: Codable {
    let model: OpenCodeModelInfo
    let parts: [OpenCodeMessagePartInput]
    let noReply: Bool?
}

struct OpenCodeModelInfo: Codable {
    let providerID: String
    let modelID: String
}

struct OpenCodeMessagePartInput: Codable {
    let type: String
    let text: String?
    let mime: String?      // For file/image parts
    let url: String?       // For file/image parts (data URI)
    let filename: String?  // Optional filename for images
    
    // Text-only init
    init(type: String, text: String) {
        self.type = type
        self.text = text
        self.mime = nil
        self.url = nil
        self.filename = nil
    }
    
    // Image/File init (OpenCode FilePartInput format)
    init(type: String, base64Data: String, mimeType: String, filename: String? = nil) {
        self.type = type
        self.text = nil
        self.mime = mimeType
        // Create data URI: data:image/png;base64,iVBORw0KGgo...
        self.url = "data:\(mimeType);base64,\(base64Data)"
        self.filename = filename
    }
}

/// Message response from OpenCode
struct OpenCodeMessageResponse: Codable {
    let info: OpenCodeMessageInfo
    let parts: [OpenCodeMessagePart]
}

struct OpenCodeMessageInfo: Codable {
    let id: String
    let parentID: String?
    let role: String
    let system: [String]?
}

struct OpenCodeMessagePart: Codable {
    let type: String
    let text: String?
}

// MARK: - OpenCodeProxyService

/// Service that proxies requests to an OpenCode server running locally
/// Implements the ModelService protocol to integrate with Osaurus's architecture
final class OpenCodeProxyService: ModelService {
    let id: String = "opencode"

    // Configuration
    private let baseURL: String
    private let session: URLSession

    // State management
    private var currentSessionID: String?
    private var availableProviders: [OpenCodeProvider] = []
    private var lastProvidersCheck: Date?
    private let providersCacheDuration: TimeInterval = 60 // Cache for 60 seconds

    // Threading
    private let queue = DispatchQueue(label: "com.osaurus.opencode", attributes: .concurrent)

    init(baseURL: String = "http://127.0.0.1:4096") {
        self.baseURL = baseURL

        // Configure URLSession with timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - ModelService Protocol

    func isAvailable() -> Bool {
        // Check if OpenCode server is responding
        let semaphore = DispatchSemaphore(value: 0)
        var available = false

        Task {
            do {
                _ = try await fetchProviders()
                available = true
                print("[OpenCodeProxy] ✓ OpenCode server is available")
            } catch {
                available = false
                print("[OpenCodeProxy] ✗ OpenCode server not available: \(error)")
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 2.0)
        return available
    }

    func handles(requestedModel: String?) -> Bool {
        guard let model = requestedModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty else {
            return false
        }

        // Check if model matches format: "providerID:modelID" or "copilot:*"
        return model.contains(":") || model.lowercased().contains("copilot")
    }

    func streamDeltas(
        prompt: String,
        parameters: GenerationParameters
    ) async throws -> AsyncStream<String> {
        // Delegate to multimodal method with no attachments
        return try await streamDeltasWithAttachments(
            prompt: prompt,
            parameters: parameters,
            attachments: []
        )
    }
    
    /// Stream deltas with multimodal support (text + images)
    /// - Parameters:
    ///   - prompt: Text prompt
    ///   - parameters: Generation parameters
    ///   - attachments: Array of image attachments (base64 encoded)
    func streamDeltasWithAttachments(
        prompt: String,
        parameters: GenerationParameters,
        attachments: [Attachment]
    ) async throws -> AsyncStream<String> {
        print("[OpenCodeProxy] ╔══════════════════════════════════════════════════════════")
        print("[OpenCodeProxy] ║ STREAM REQUEST INITIATED")
        print("[OpenCodeProxy] ╠══════════════════════════════════════════════════════════")
        print("[OpenCodeProxy] ║ Prompt: \(prompt.prefix(100))...")
        print("[OpenCodeProxy] ║ Prompt length: \(prompt.count) characters")
        print("[OpenCodeProxy] ║ Attachments count: \(attachments.count)")
        print("[OpenCodeProxy] ╚══════════════════════════════════════════════════════════")

        // Ensure we have a session
        if currentSessionID == nil {
            print("[OpenCodeProxy] ⚙️  Creating new OpenCode session...")
            let session = try await createSession()
            currentSessionID = session.id
            print("[OpenCodeProxy] ✓ Session created: \(session.id)")
        } else {
            print("[OpenCodeProxy] ♻️  Reusing existing session: \(currentSessionID!)")
        }

        guard let sessionID = currentSessionID else {
            print("[OpenCodeProxy] ✗ FATAL: No session available")
            throw OpenCodeError.noSession
        }

        // Build multimodal parts array
        var parts: [OpenCodeMessagePartInput] = []
        
        // Add text part first
        print("[OpenCodeProxy] 📝 Building message parts...")
        parts.append(OpenCodeMessagePartInput(type: "text", text: prompt))
        print("[OpenCodeProxy]    ✓ Added text part (length: \(prompt.count) chars)")
        
        // Add image parts (OpenCode FilePartInput format)
        if !attachments.isEmpty {
            print("[OpenCodeProxy] 🖼️  Processing \(attachments.count) image attachment(s)...")
        }
        
        for (index, attachment) in attachments.enumerated() {
            print("[OpenCodeProxy] ╔═══════════════════════════════════════════════════════")
            print("[OpenCodeProxy] ║ 🖼️  IMAGE ATTACHMENT #\(index + 1)")
            print("[OpenCodeProxy] ╠═══════════════════════════════════════════════════════")
            print("[OpenCodeProxy] ║ Filename:     \(attachment.fileName)")
            print("[OpenCodeProxy] ║ File size:    \(attachment.formattedFileSize)")
            print("[OpenCodeProxy] ║ MIME type:    \(attachment.mimeType)")
            print("[OpenCodeProxy] ║ Base64 len:   \(attachment.base64Data.count) characters")
            print("[OpenCodeProxy] ║ Base64 start: \(String(attachment.base64Data.prefix(60)))...")
            
            // Create the image part (OpenCode expects FilePartInput: type="file" with data URI)
            let imagePart = OpenCodeMessagePartInput(
                type: "file",
                base64Data: attachment.base64Data,
                mimeType: attachment.mimeType,
                filename: attachment.fileName
            )
            
            // Validate the structure being created
            if let dataUrl = imagePart.url {
                let dataUriLength = dataUrl.count
                let expectedPrefix = "data:\(attachment.mimeType);base64,"
                let hasValidPrefix = dataUrl.hasPrefix(expectedPrefix)
                
                print("[OpenCodeProxy] ║ Data URI len: \(dataUriLength) characters")
                print("[OpenCodeProxy] ║ Data URI prefix: \(String(dataUrl.prefix(100)))...")
                print("[OpenCodeProxy] ║ Expected prefix: \(expectedPrefix)")
                print("[OpenCodeProxy] ║ Prefix valid: \(hasValidPrefix ? "✓ YES" : "✗ NO - MISMATCH!")")
            } else {
                print("[OpenCodeProxy] ║ ⚠️  WARNING: Data URI is nil!")
            }
            
            print("[OpenCodeProxy] ║ Part structure:")
            print("[OpenCodeProxy] ║   - type: \(imagePart.type)")
            print("[OpenCodeProxy] ║   - mime: \(imagePart.mime ?? "nil")")
            print("[OpenCodeProxy] ║   - filename: \(imagePart.filename ?? "nil")")
            print("[OpenCodeProxy] ║   - url: \(imagePart.url != nil ? "present (\(imagePart.url!.count) chars)" : "nil")")
            
            parts.append(imagePart)
            print("[OpenCodeProxy] ║ ✓ Image part added to request")
            print("[OpenCodeProxy] ╚═══════════════════════════════════════════════════════")
        }

        print("[OpenCodeProxy] 📦 Total parts prepared: \(parts.count) (1 text + \(attachments.count) image(s))")
        print("[OpenCodeProxy] 🚀 Preparing to send multimodal message to OpenCode...")

        return AsyncStream { continuation in
            Task {
                do {
                    // Start listening to SSE events BEFORE sending the message
                    let eventTask = Task {
                        try await self.listenToEvents(sessionID: sessionID, continuation: continuation)
                    }

                    // Small delay to ensure event stream is connected
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                    // Send multimodal message to OpenCode
                    let messageRequest = OpenCodeMessageRequest(
                        model: OpenCodeModelInfo(
                            providerID: "github-copilot",
                            modelID: "claude-sonnet-4.5"
                        ),
                        parts: parts,
                        noReply: false
                    )

                    print("[OpenCodeProxy] ╔══════════════════════════════════════════════════════════")
                    print("[OpenCodeProxy] ║ 📤 SENDING MESSAGE TO OPENCODE")
                    print("[OpenCodeProxy] ╠══════════════════════════════════════════════════════════")
                    print("[OpenCodeProxy] ║ Session ID: \(sessionID)")
                    print("[OpenCodeProxy] ║ Provider: \(messageRequest.model.providerID)")
                    print("[OpenCodeProxy] ║ Model: \(messageRequest.model.modelID)")
                    print("[OpenCodeProxy] ║ Parts count: \(messageRequest.parts.count)")
                    print("[OpenCodeProxy] ╚══════════════════════════════════════════════════════════")

                    let url = URL(string: "\(self.baseURL)/session/\(sessionID)/message")!
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    print("[OpenCodeProxy] 🌐 Target URL: \(url.absoluteString)")
                    
                    // Encode the request
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let requestBody = try encoder.encode(messageRequest)
                    urlRequest.httpBody = requestBody
                    
                    let bodySize = requestBody.count
                    let bodySizeFormatted = ByteCountFormatter.string(fromByteCount: Int64(bodySize), countStyle: .file)
                    print("[OpenCodeProxy] 📦 Request body size: \(bodySizeFormatted) (\(bodySize) bytes)")
                    
                    // Log the complete JSON request
                    if let jsonString = String(data: requestBody, encoding: .utf8) {
                        print("[OpenCodeProxy] ╔══════════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ 📋 REQUEST JSON PAYLOAD:")
                        print("[OpenCodeProxy] ╠══════════════════════════════════════════════════════════")
                        // Truncate base64 data in URL field for readability in logs
                        let truncatedJson = jsonString.replacingOccurrences(
                            of: #"("url"\s*:\s*"data:[^;]+;base64,)([^"]{100})[^"]*""#,
                            with: "$1$2...[TRUNCATED to save space]\"",
                            options: .regularExpression
                        )
                        print(truncatedJson)
                        print("[OpenCodeProxy] ╚══════════════════════════════════════════════════════════")
                    }

                    print("[OpenCodeProxy] ⏳ Sending HTTP POST request to OpenCode...")
                    let startTime = Date()
                    let (data, response) = try await self.session.data(for: urlRequest)
                    let elapsed = Date().timeIntervalSince(startTime)

                    print("[OpenCodeProxy] ⏱️  Request completed in \(String(format: "%.2f", elapsed))s")

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("[OpenCodeProxy] ✗ FATAL: No HTTP response received from OpenCode")
                        eventTask.cancel()
                        throw OpenCodeError.invalidResponse
                    }
                    
                    print("[OpenCodeProxy] ╔══════════════════════════════════════════════════════════")
                    print("[OpenCodeProxy] ║ 📥 OPENCODE RESPONSE RECEIVED")
                    print("[OpenCodeProxy] ╠══════════════════════════════════════════════════════════")
                    print("[OpenCodeProxy] ║ Status code: \(httpResponse.statusCode) \(httpResponse.statusCode == 200 ? "✓ OK" : "✗ ERROR")")
                    print("[OpenCodeProxy] ║ Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none")")
                    print("[OpenCodeProxy] ║ Response size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                    
                    if httpResponse.statusCode != 200 {
                        print("[OpenCodeProxy] ║ ✗ HTTP ERROR: Status code \(httpResponse.statusCode)")
                        if let responseBody = String(data: data, encoding: .utf8) {
                            print("[OpenCodeProxy] ║ Error response body:")
                            print("[OpenCodeProxy] ║ \(responseBody)")
                        }
                        print("[OpenCodeProxy] ╚══════════════════════════════════════════════════════════")
                        eventTask.cancel()
                        throw OpenCodeError.invalidResponse
                    }
                    
                    // Parse the response to extract text from parts
                    print("[OpenCodeProxy] ║ Parsing response JSON...")
                    let messageResponse = try JSONDecoder().decode(OpenCodeMessageResponse.self, from: data)
                    
                    print("[OpenCodeProxy] ║ ✓ Response parsed successfully!")
                    print("[OpenCodeProxy] ║ Assistant message ID: \(messageResponse.info.id)")
                    print("[OpenCodeProxy] ║ Parts count: \(messageResponse.parts.count)")
                    print("[OpenCodeProxy] ╚══════════════════════════════════════════════════════════")
                    
                    // Extract text from all text parts
                    var fullText = ""
                    for (index, part) in messageResponse.parts.enumerated() {
                        print("[OpenCodeProxy] 📄 Part \(index + 1): type=\(part.type)")
                        
                        if part.type == "text", let text = part.text, !text.isEmpty {
                            print("[OpenCodeProxy] ✓ Found text content (\(text.count) chars)")
                            fullText += text
                        }
                    }
                    
                    if !fullText.isEmpty {
                        print("[OpenCodeProxy] ╔══════════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ 📝 YIELDING COMPLETE RESPONSE TO UI")
                        print("[OpenCodeProxy] ╠══════════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ Total text length: \(fullText.count) characters")
                        print("[OpenCodeProxy] ║ Preview: \(String(fullText.prefix(100)))\(fullText.count > 100 ? "..." : "")")
                        print("[OpenCodeProxy] ╚══════════════════════════════════════════════════════════")
                        
                        // Yield the complete text to the UI
                        continuation.yield(fullText)
                    } else {
                        print("[OpenCodeProxy] ⚠️  No text content found in response parts")
                    }
                    
                    // Cancel SSE listener since we got the complete response
                    eventTask.cancel()
                    
                    // Finish the stream
                    continuation.finish()

                } catch {
                    print("[OpenCodeProxy] Streaming error: \(error)")
                    continuation.yield("Error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    func generateOneShot(
        prompt: String,
        parameters: GenerationParameters
    ) async throws -> String {
        // Ensure we have a session
        if currentSessionID == nil {
            let session = try await createSession()
            currentSessionID = session.id
        }

        guard let sessionID = currentSessionID else {
            throw OpenCodeError.noSession
        }

        // Send message to OpenCode
        let messageRequest = OpenCodeMessageRequest(
            model: OpenCodeModelInfo(
                providerID: "github-copilot",
                modelID: "claude-sonnet-4.5"
            ),
            parts: [
                OpenCodeMessagePartInput(type: "text", text: prompt)
            ],
            noReply: false
        )

        let response = try await sendMessage(sessionID: sessionID, request: messageRequest)

        // Extract text from response parts
        return response.parts
            .compactMap { $0.text }
            .joined(separator: "\n")
    }

    // MARK: - OpenCode API Methods

    /// Fetch available providers from OpenCode server
    private func fetchProviders() async throws -> [OpenCodeProvider] {
        // Check cache
        if let lastCheck = lastProvidersCheck,
           Date().timeIntervalSince(lastCheck) < providersCacheDuration {
            return availableProviders
        }

        let url = URL(string: "\(baseURL)/config/providers")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenCodeError.invalidResponse
        }

        let decoder = JSONDecoder()
        let providersResponse = try decoder.decode(OpenCodeProvidersResponse.self, from: data)

        // Update cache
        queue.async(flags: .barrier) {
            self.availableProviders = providersResponse.providers
            self.lastProvidersCheck = Date()
        }

        return providersResponse.providers
    }

    /// Create a new OpenCode session
    private func createSession(title: String? = nil) async throws -> OpenCodeSession {
        let url = URL(string: "\(baseURL)/session")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OpenCodeSessionRequest(parentID: nil, title: title ?? "Osaurus Chat")
        request.httpBody = try JSONEncoder().encode(body)

        print("[OpenCodeProxy] Creating session with URL: \(url)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.invalidResponse
        }

        print("[OpenCodeProxy] Session creation response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                print("[OpenCodeProxy] Session creation failed. Response: \(responseString)")
            }
            throw OpenCodeError.invalidResponse
        }

        let decoder = JSONDecoder()
        do {
            let session = try decoder.decode(OpenCodeSession.self, from: data)
            return session
        } catch {
            if let responseString = String(data: data, encoding: .utf8) {
                print("[OpenCodeProxy] Failed to decode session. Response: \(responseString)")
            }
            throw error
        }
    }

    /// Send a message to an OpenCode session
    private func sendMessage(
        sessionID: String,
        request: OpenCodeMessageRequest
    ) async throws -> OpenCodeMessageResponse {
        let url = URL(string: "\(baseURL)/session/\(sessionID)/message")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        urlRequest.httpBody = try JSONEncoder().encode(request)

        print("[OpenCodeProxy] Sending message to: \(url)")
        print("[OpenCodeProxy] Provider: \(request.model.providerID), Model: \(request.model.modelID)")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.invalidResponse
        }

        print("[OpenCodeProxy] Message response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                print("[OpenCodeProxy] Message failed. Response: \(responseString)")
            }
            throw OpenCodeError.invalidResponse
        }

        return try JSONDecoder().decode(OpenCodeMessageResponse.self, from: data)
    }

    /// Get list of available models from all providers
    func getAvailableModels() async throws -> [(provider: String, model: String, displayName: String)] {
        let providers = try await fetchProviders()
        var models: [(String, String, String)] = []

        for provider in providers {
            for (modelID, model) in provider.models {
                let displayName = model.name ?? modelID
                models.append((provider.id, modelID, displayName))
            }
        }

        return models
    }

    /// Reset the current session (for starting a new conversation)
    func resetSession() {
        currentSessionID = nil
    }

    /// Stream message response from OpenCode using SSE
    private func streamMessageResponse(
        sessionID: String,
        request: OpenCodeMessageRequest,
        continuation: AsyncStream<String>.Continuation
    ) async throws {
        let url = URL(string: "\(baseURL)/session/\(sessionID)/message")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        urlRequest.httpBody = try JSONEncoder().encode(request)

        print("[OpenCodeProxy] Streaming from: \(url)")

        // Use URLSession's bytes stream for SSE
        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[OpenCodeProxy] No HTTP response received")
            throw OpenCodeError.invalidResponse
        }

        print("[OpenCodeProxy] Stream response status: \(httpResponse.statusCode)")
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none"
        print("[OpenCodeProxy] Stream content-type: \(contentType)")

        guard httpResponse.statusCode == 200 else {
            print("[OpenCodeProxy] Invalid status code: \(httpResponse.statusCode)")
            throw OpenCodeError.invalidResponse
        }

        // Check if response is JSON (non-streaming) or SSE (streaming)
        if contentType.contains("application/json") {
            // Non-streaming JSON response
            print("[OpenCodeProxy] Handling non-streaming JSON response")
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }

            // Parse JSON response
            do {
                // First, print the raw JSON to see the structure
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[OpenCodeProxy] Raw JSON response:")
                    print(jsonString)
                }

                let response = try JSONDecoder().decode(OpenCodeMessageResponse.self, from: data)
                print("[OpenCodeProxy] Decoded response successfully")
                print("[OpenCodeProxy] Response has \(response.parts.count) parts")

                // Debug: print each part
                for (index, part) in response.parts.enumerated() {
                    print("[OpenCodeProxy] Part \(index): type=\(part.type), text=\(part.text ?? "nil")")
                }

                // Extract text from parts - look for "text" type parts or any part with text content
                var text = ""

                // First try to get text from parts with type="text"
                let textParts = response.parts.filter { $0.type == "text" }
                if !textParts.isEmpty {
                    text = textParts.compactMap { $0.text }.joined(separator: "\n")
                } else {
                    // If no text parts, the message might still be processing
                    // Try to fetch the message again to get the complete response
                    print("[OpenCodeProxy] No text parts found, message might still be processing...")

                    // Wait a bit and try to get the message
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

                    // Try to fetch the complete message
                    if let sessionID = currentSessionID {
                        let messageID = response.info.id
                        print("[OpenCodeProxy] Fetching complete message: \(messageID)")
                        // TODO: Implement GET /session/:id/message/:messageID to get full content
                        // For now, yield an error message
                        continuation.yield("Response received but no text content found. Message ID: \(messageID)")
                        continuation.finish()
                        return
                    }
                }

                print("[OpenCodeProxy] Full text length: \(text.count) characters")
                print("[OpenCodeProxy] Full text: \(text)")

                if text.isEmpty {
                    print("[OpenCodeProxy] Warning: Empty response text")
                    continuation.yield("(No response generated)")
                    continuation.finish()
                    return
                }

                // Simulate streaming by yielding text in chunks
                // This makes the UI appear to stream even though we got the whole response
                let chunkSize = 10  // Characters per chunk
                var index = text.startIndex
                var chunkCount = 0

                while index < text.endIndex {
                    let endIndex = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
                    let chunk = String(text[index..<endIndex])
                    print("[OpenCodeProxy] Yielding chunk \(chunkCount): '\(chunk)'")
                    continuation.yield(chunk)
                    chunkCount += 1
                    index = endIndex

                    // Small delay to simulate streaming effect
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }

                print("[OpenCodeProxy] Finished yielding \(chunkCount) chunks")
                continuation.finish()
            } catch {
                // If decoding fails, log the raw response
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[OpenCodeProxy] Failed to decode. Raw response: \(responseString.prefix(500))")
                }
                throw error
            }
        } else {
            // SSE streaming response
            print("[OpenCodeProxy] Handling SSE stream")
            var buffer = ""
            for try await byte in bytes {
                let char = Character(UnicodeScalar(byte))
                buffer.append(char)

                // Process complete lines
                while let lineEnd = buffer.firstIndex(of: "\n") {
                    let line = String(buffer[..<lineEnd])
                    buffer.removeSubrange(...lineEnd)

                    // Parse SSE line
                    if let delta = parseSSELine(line) {
                        continuation.yield(delta)
                    }
                }
            }
            continuation.finish()
        }
    }

    /// Parse a single SSE line and extract text delta
    private func parseSSELine(_ line: String) -> String? {
        // SSE format: "data: {json}\n"
        guard line.hasPrefix("data: ") else {
            return nil
        }

        let jsonString = line.dropFirst(6) // Remove "data: "
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let parts = json["parts"] as? [[String: Any]] {
                // Extract text from parts
                for part in parts {
                    if let text = part["text"] as? String {
                        return text
                    }
                }
            }
        } catch {
            // Ignore JSON parsing errors (some SSE lines might not be JSON)
        }

        return nil
    }

    /// Listen to OpenCode's SSE event stream for real-time message updates
    private func listenToEvents(
        sessionID: String,
        continuation: AsyncStream<String>.Continuation
    ) async throws {
        let url = URL(string: "\(baseURL)/event")!
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30  // 30 second timeout

        print("[OpenCodeProxy] ╔══════════════════════════════════════════════════════════")
        print("[OpenCodeProxy] ║ 🎧 CONNECTING TO SSE EVENT STREAM")
        print("[OpenCodeProxy] ╠══════════════════════════════════════════════════════════")
        print("[OpenCodeProxy] ║ URL: \(url.absoluteString)")
        print("[OpenCodeProxy] ║ Session: \(sessionID)")
        print("[OpenCodeProxy] ║ Timeout: 30s")
        print("[OpenCodeProxy] ╚══════════════════════════════════════════════════════════")

        // Use URLSession's bytes stream for SSE
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("[OpenCodeProxy] ✗ FATAL: Failed to connect to event stream")
            if let httpResponse = response as? HTTPURLResponse {
                print("[OpenCodeProxy] Status code: \(httpResponse.statusCode)")
            }
            throw OpenCodeError.invalidResponse
        }

        print("[OpenCodeProxy] ✓ SSE stream connected successfully!")
        print("[OpenCodeProxy] 👂 Listening for events from OpenCode...")
        print("[OpenCodeProxy] (Expecting: message.part.updated, message.updated, session.idle)")

        var byteBuffer = Data()
        var eventType = ""
        var eventData = ""
        var messageComplete = false
        var lastTextLength = 0  // Track how much text we've already sent
        var assistantMessageID: String? = nil  // Track the assistant's message ID to filter events
        var lastByteTime = Date()
        var totalBytesReceived = 0

        for try await byte in bytes {
            totalBytesReceived += 1
            lastByteTime = Date()
            
            // Log first byte received
            if totalBytesReceived == 1 {
                print("[OpenCodeProxy] 🎉 First byte received from SSE stream!")
            }
            
            // Log every 100 bytes to show activity
            if totalBytesReceived % 100 == 0 {
                print("[OpenCodeProxy] 📊 Received \(totalBytesReceived) bytes from SSE stream...")
            }
            byteBuffer.append(byte)

            // Try to decode the buffer as UTF-8 and process complete lines
            if let bufferString = String(data: byteBuffer, encoding: .utf8) {
                // Successfully decoded, clear byte buffer
                byteBuffer.removeAll()

                // Process each line
                let lines = bufferString.split(separator: "\n", omittingEmptySubsequences: false)
                for (index, lineSubstring) in lines.enumerated() {
                    // Skip the last line as it might be incomplete
                    if index == lines.count - 1 && !bufferString.hasSuffix("\n") {
                        // Keep incomplete line in buffer
                        if let lastData = String(lineSubstring).data(using: .utf8) {
                            byteBuffer = lastData
                        }
                        break
                    }

                    let line = String(lineSubstring).trimmingCharacters(in: .whitespacesAndNewlines)

                    // Parse SSE format
                    if line.isEmpty {
                        // Empty line signals end of event
                        if !eventData.isEmpty {
                            processEvent(type: eventType, data: eventData, sessionID: sessionID, continuation: continuation, messageComplete: &messageComplete, lastTextLength: &lastTextLength, assistantMessageID: &assistantMessageID)
                            eventType = ""
                            eventData = ""
                        }
                    } else if line.hasPrefix("event:") {
                        eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if line.hasPrefix("data:") {
                        let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if eventData.isEmpty {
                            eventData = data
                        } else {
                            eventData += "\n" + data
                        }
                    }

                    // If message is complete, we can stop listening
                    if messageComplete {
                        print("[OpenCodeProxy] ╔════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ 🏁 STREAM COMPLETE")
                        print("[OpenCodeProxy] ╠════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ Stopping event listener")
                        print("[OpenCodeProxy] ║ Total text received: \(lastTextLength) characters")
                        print("[OpenCodeProxy] ║ Stream finished successfully!")
                        print("[OpenCodeProxy] ╚════════════════════════════════════════════════════")
                        continuation.finish()
                        return
                    }
                }
            }
        }

        print("[OpenCodeProxy] ╔════════════════════════════════════════════════════")
        print("[OpenCodeProxy] ║ 🔚 SSE STREAM ENDED")
        print("[OpenCodeProxy] ╠════════════════════════════════════════════════════")
        print("[OpenCodeProxy] ║ Total bytes received: \(totalBytesReceived)")
        print("[OpenCodeProxy] ║ Message completed: \(messageComplete ? "✓ Yes" : "✗ No")")
        print("[OpenCodeProxy] ║ Last byte time: \(lastByteTime)")
        print("[OpenCodeProxy] ╚════════════════════════════════════════════════════")
        
        if !messageComplete {
            print("[OpenCodeProxy] ⚠️  Stream ended but message not complete - this may indicate an issue")
        }
        
        continuation.finish()
    }

    /// Process a single SSE event
    private func processEvent(
        type: String,
        data: String,
        sessionID: String,
        continuation: AsyncStream<String>.Continuation,
        messageComplete: inout Bool,
        lastTextLength: inout Int,
        assistantMessageID: inout String?
    ) {
        guard let jsonData = data.data(using: .utf8) else {
            return
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return
            }

            // Check if this event is for our session
            if let eventSessionID = json["sessionID"] as? String,
               eventSessionID != sessionID {
                // Event is for a different session, ignore it
                return
            }

            // Event type is in the JSON "type" field, not in SSE "event:" field
            let eventType = json["type"] as? String ?? ""

            switch eventType {
            case "message.part.updated":
                // Extract text from message part
                if let properties = json["properties"] as? [String: Any],
                   let part = properties["part"] as? [String: Any],
                   part["type"] as? String == "text",
                   let partMessageID = part["messageID"] as? String,
                   let fullText = part["text"] as? String {

                    // Only process parts from the assistant's message, not the user's
                    guard let assistantID = assistantMessageID, partMessageID == assistantID else {
                        print("[OpenCodeProxy] 🔇 Skipping part update (not from assistant message)")
                        return  // Skip parts from user's message
                    }

                    // OpenCode sends the full text each time, not deltas
                    // Only yield the new portion
                    if fullText.count > lastTextLength {
                        let startIndex = fullText.index(fullText.startIndex, offsetBy: lastTextLength)
                        let newText = String(fullText[startIndex...])
                        let deltaSize = newText.count
                        print("[OpenCodeProxy] ╔════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ 💬 RESPONSE DELTA RECEIVED FROM OPENCODE")
                        print("[OpenCodeProxy] ╠════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ Previous length: \(lastTextLength) chars")
                        print("[OpenCodeProxy] ║ New total length: \(fullText.count) chars")
                        print("[OpenCodeProxy] ║ Delta size: \(deltaSize) chars")
                        print("[OpenCodeProxy] ║ Delta preview: \(String(newText.prefix(100)))\(newText.count > 100 ? "..." : "")")
                        print("[OpenCodeProxy] ╚════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ✓ Yielding delta to Osaurus UI...")
                        continuation.yield(newText)
                        lastTextLength = fullText.count
                    } else {
                        print("[OpenCodeProxy] 🔄 No new content (length unchanged: \(fullText.count))")
                    }
                } else {
                    print("[OpenCodeProxy] ⚠️  message.part.updated event missing expected fields")
                }

            case "message.updated":
                // Track assistant message ID and check for completion
                if let properties = json["properties"] as? [String: Any],
                   let info = properties["info"] as? [String: Any] {

                    // Capture assistant message ID
                    if let role = info["role"] as? String,
                       role == "assistant",
                       let msgID = info["id"] as? String {
                        if assistantMessageID == nil {
                            assistantMessageID = msgID
                            print("[OpenCodeProxy] ╔════════════════════════════════════════════════════")
                            print("[OpenCodeProxy] ║ 🤖 ASSISTANT MESSAGE IDENTIFIED")
                            print("[OpenCodeProxy] ╠════════════════════════════════════════════════════")
                            print("[OpenCodeProxy] ║ Message ID: \(msgID)")
                            print("[OpenCodeProxy] ║ Now tracking this message for text deltas...")
                            print("[OpenCodeProxy] ╚════════════════════════════════════════════════════")
                        }
                    }

                    // Check if message has completed
                    if let time = info["time"] as? [String: Any],
                       time["completed"] != nil {
                        print("[OpenCodeProxy] ╔════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ ✅ MESSAGE GENERATION COMPLETE")
                        print("[OpenCodeProxy] ╠════════════════════════════════════════════════════")
                        print("[OpenCodeProxy] ║ Total characters received: \(lastTextLength)")
                        print("[OpenCodeProxy] ║ Assistant message ID: \(assistantMessageID ?? "unknown")")
                        print("[OpenCodeProxy] ╚════════════════════════════════════════════════════")
                        messageComplete = true
                    }
                }

            case "session.idle":
                // Session is idle, message processing complete
                print("[OpenCodeProxy] ╔════════════════════════════════════════════════════")
                print("[OpenCodeProxy] ║ 💤 SESSION IDLE")
                print("[OpenCodeProxy] ╠════════════════════════════════════════════════════")
                print("[OpenCodeProxy] ║ OpenCode session is now idle")
                print("[OpenCodeProxy] ║ Finishing stream...")
                print("[OpenCodeProxy] ╚════════════════════════════════════════════════════")
                messageComplete = true

            case "message.error":
                // Handle error
                if let properties = json["properties"] as? [String: Any],
                   let error = properties["error"] as? String {
                    print("[OpenCodeProxy] ╔════════════════════════════════════════════════════")
                    print("[OpenCodeProxy] ║ ❌ MESSAGE ERROR FROM OPENCODE")
                    print("[OpenCodeProxy] ╠════════════════════════════════════════════════════")
                    print("[OpenCodeProxy] ║ Error: \(error)")
                    print("[OpenCodeProxy] ╚════════════════════════════════════════════════════")
                    continuation.yield("Error: \(error)")
                    messageComplete = true
                }

            default:
                // Log other event types for debugging
                let eventSummary = json.keys.joined(separator: ", ")
                print("[OpenCodeProxy] 🔔 Event: \(eventType) (keys: \(eventSummary))")
                break
            }
        } catch {
            print("[OpenCodeProxy] Failed to parse event JSON: \(error)")
        }
    }
}

// MARK: - Errors

enum OpenCodeError: Error, LocalizedError {
    case serverNotAvailable
    case invalidResponse
    case noSession
    case invalidModelFormat

    var errorDescription: String? {
        switch self {
        case .serverNotAvailable:
            return "OpenCode server is not running at the configured URL"
        case .invalidResponse:
            return "Received invalid response from OpenCode server"
        case .noSession:
            return "No active OpenCode session"
        case .invalidModelFormat:
            return "Model name must be in format 'providerID:modelID'"
        }
    }
}
