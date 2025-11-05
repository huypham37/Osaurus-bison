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
            } catch {
                available = false
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

        // Ensure we have a session
        if currentSessionID == nil {
            let session = try await createSession()
            currentSessionID = session.id
        } else {
        }

        guard let sessionID = currentSessionID else {
            throw OpenCodeError.noSession
        }

        // Build multimodal parts array
        var parts: [OpenCodeMessagePartInput] = []
        
        // Add text part first
        parts.append(OpenCodeMessagePartInput(type: "text", text: prompt))
        
        // Add image parts (OpenCode FilePartInput format)
        if !attachments.isEmpty {
        }
        
        for (index, attachment) in attachments.enumerated() {
            
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
                
            } else {
            }
            
            
            parts.append(imagePart)
        }


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


                    let url = URL(string: "\(self.baseURL)/session/\(sessionID)/message")!
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    
                    // Encode the request
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let requestBody = try encoder.encode(messageRequest)
                    urlRequest.httpBody = requestBody
                    
                    let bodySize = requestBody.count
                    let bodySizeFormatted = ByteCountFormatter.string(fromByteCount: Int64(bodySize), countStyle: .file)
                    
                    // Log the complete JSON request
                    if let jsonString = String(data: requestBody, encoding: .utf8) {
                        // Truncate base64 data in URL field for readability in logs
                        _ = jsonString.replacingOccurrences(
                            of: #"("url"\s*:\s*"data:[^;]+;base64,)([^"]{100})[^"]*""#,
                            with: "$1$2...[TRUNCATED to save space]\"",
                            options: .regularExpression
                        )
                    }

                    let startTime = Date()
                    let (data, response) = try await self.session.data(for: urlRequest)
                    let elapsed = Date().timeIntervalSince(startTime)


                    guard let httpResponse = response as? HTTPURLResponse else {
                        eventTask.cancel()
                        throw OpenCodeError.invalidResponse
                    }
                    
                    
                    if httpResponse.statusCode != 200 {
                        if let responseBody = String(data: data, encoding: .utf8) {
                        }
                        eventTask.cancel()
                        throw OpenCodeError.invalidResponse
                    }
                    
                    // Parse the response to extract text from parts
                    let messageResponse = try JSONDecoder().decode(OpenCodeMessageResponse.self, from: data)
                    
                    
                    // Extract text from all text parts
                    var fullText = ""
                    for (index, part) in messageResponse.parts.enumerated() {
                        
                        if part.type == "text", let text = part.text, !text.isEmpty {
                            fullText += text
                        }
                    }
                    
                    if !fullText.isEmpty {
                        
                        // Yield the complete text to the UI
                        continuation.yield(fullText)
                    } else {
                    }
                    
                    // Cancel SSE listener since we got the complete response
                    eventTask.cancel()
                    
                    // Finish the stream
                    continuation.finish()

                } catch {
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


        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.invalidResponse
        }


        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
            }
            throw OpenCodeError.invalidResponse
        }

        let decoder = JSONDecoder()
        do {
            let session = try decoder.decode(OpenCodeSession.self, from: data)
            return session
        } catch {
            if let responseString = String(data: data, encoding: .utf8) {
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


        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.invalidResponse
        }


        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
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


        // Use URLSession's bytes stream for SSE
        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.invalidResponse
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none"

        guard httpResponse.statusCode == 200 else {
            throw OpenCodeError.invalidResponse
        }

        // Check if response is JSON (non-streaming) or SSE (streaming)
        if contentType.contains("application/json") {
            // Non-streaming JSON response
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }

            // Parse JSON response
            do {
                // First, check if JSON can be decoded
                if let _ = String(data: data, encoding: .utf8) {
                    // JSON available for decoding
                }

                let response = try JSONDecoder().decode(OpenCodeMessageResponse.self, from: data)

                // Debug: print each part
                for (index, part) in response.parts.enumerated() {
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

                    // Wait a bit and try to get the message
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

                    // Try to fetch the complete message
                    if let sessionID = currentSessionID {
                        let messageID = response.info.id
                        // TODO: Implement GET /session/:id/message/:messageID to get full content
                        // For now, yield an error message
                        continuation.yield("Response received but no text content found. Message ID: \(messageID)")
                        continuation.finish()
                        return
                    }
                }


                if text.isEmpty {
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
                    continuation.yield(chunk)
                    chunkCount += 1
                    index = endIndex

                    // Small delay to simulate streaming effect
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }

                continuation.finish()
            } catch {
                // If decoding fails, log the raw response
                if let responseString = String(data: data, encoding: .utf8) {
                }
                throw error
            }
        } else {
            // SSE streaming response
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


        // Use URLSession's bytes stream for SSE
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if let httpResponse = response as? HTTPURLResponse {
            }
            throw OpenCodeError.invalidResponse
        }


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
            }
            
            // Log every 100 bytes to show activity
            if totalBytesReceived % 100 == 0 {
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
                        let data = String(line.dropFirst(5))
                        if eventData.isEmpty {
                            eventData = data
                        } else {
                            eventData += "\n" + data
                        }
                    }

                    // If message is complete, we can stop listening
                    if messageComplete {
                        continuation.finish()
                        return
                    }
                }
            }
        }

        
        if !messageComplete {
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
                        return  // Skip parts from user's message
                    }

                    // OpenCode sends the full text each time, not deltas
                    // Only yield the new portion
                    if fullText.count > lastTextLength {
                        let startIndex = fullText.index(fullText.startIndex, offsetBy: lastTextLength)
                        let newText = String(fullText[startIndex...])
                        let deltaSize = newText.count
                        continuation.yield(newText)
                        lastTextLength = fullText.count
                    } else {
                    }
                } else {
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
                        }
                    }

                    // Check if message has completed
                    if let time = info["time"] as? [String: Any],
                       time["completed"] != nil {
                        messageComplete = true
                    }
                }

            case "session.idle":
                // Session is idle, message processing complete
                messageComplete = true

            case "message.error":
                // Handle error
                if let properties = json["properties"] as? [String: Any],
                   let error = properties["error"] as? String {
                    continuation.yield("Error: \(error)")
                    messageComplete = true
                }

            default:
                // Log other event types for debugging
                let eventSummary = json.keys.joined(separator: ", ")
                break
            }
        } catch {
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
