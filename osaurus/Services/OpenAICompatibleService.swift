//
//  OpenAICompatibleService.swift
//  osaurus
//
//  Service for handling OpenAI-compatible API endpoints
//  Supports streaming, multimodal, and tool calling
//

import Foundation

/// Service that connects to OpenAI-compatible API endpoints
/// Compatible with OpenAI, Ollama, LM Studio, and other OpenAI-compatible servers
final class OpenAICompatibleService: ToolCapableService {
    let id: String = "openai-compatible"

    // Configuration
    private let baseURL: String
    private let apiKey: String?
    private let session: URLSession
    private let defaultModel: String

    // Threading
    private let queue = DispatchQueue(label: "com.osaurus.openai", attributes: .concurrent)

    /// Initialize the service with custom endpoint
    /// - Parameters:
    ///   - baseURL: Base URL of the API endpoint (e.g., "http://localhost:11434/v1" for Ollama)
    ///   - apiKey: Optional API key for authentication
    ///   - defaultModel: Default model to use if none specified
    init(
        baseURL: String = "http://localhost:11434/v1",
        apiKey: String? = nil,
        defaultModel: String = "llama3.2-vision"
    ) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.defaultModel = defaultModel

        // Configure URLSession with timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - ModelService Protocol

    func isAvailable() -> Bool {
        // Check if the API endpoint is responding
        let semaphore = DispatchSemaphore(value: 0)
        var available = false

        Task {
            do {
                _ = try await fetchModels()
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

        // This service handles any model name (delegates to the API)
        return true
    }

    func streamDeltas(
        prompt: String,
        parameters: GenerationParameters
    ) async throws -> AsyncStream<String> {
        // Build messages from prompt
        let messages = [ChatMessage(role: "user", content: prompt)]

        return try await streamChat(
            messages: messages,
            parameters: parameters,
            tools: nil,
            toolChoice: nil
        )
    }

    func generateOneShot(
        prompt: String,
        parameters: GenerationParameters
    ) async throws -> String {
        // Build messages from prompt
        let messages = [ChatMessage(role: "user", content: prompt)]

        return try await generateChatCompletion(
            messages: messages,
            parameters: parameters,
            tools: nil,
            toolChoice: nil
        )
    }

    // MARK: - ToolCapableService Protocol

    func respondWithTools(
        prompt: String,
        parameters: GenerationParameters,
        stopSequences: [String],
        tools: [Tool],
        toolChoice: ToolChoiceOption?
    ) async throws -> String {
        let messages = [ChatMessage(role: "user", content: prompt)]

        return try await generateChatCompletion(
            messages: messages,
            parameters: parameters,
            tools: tools,
            toolChoice: toolChoice
        )
    }

    func streamWithTools(
        prompt: String,
        parameters: GenerationParameters,
        stopSequences: [String],
        tools: [Tool],
        toolChoice: ToolChoiceOption?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let messages = [ChatMessage(role: "user", content: prompt)]

        let stream = try await streamChat(
            messages: messages,
            parameters: parameters,
            tools: tools,
            toolChoice: toolChoice
        )

        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                for await chunk in stream {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Multimodal Support

    /// Stream chat completion with multimodal support (text + images)
    /// - Parameters:
    ///   - messages: Array of chat messages
    ///   - parameters: Generation parameters
    ///   - attachments: Optional array of image attachments
    ///   - tools: Optional tool definitions
    ///   - toolChoice: Optional tool choice directive
    func streamChatWithAttachments(
        messages: [ChatMessage],
        parameters: GenerationParameters,
        attachments: [Attachment] = [],
        tools: [Tool]? = nil,
        toolChoice: ToolChoiceOption? = nil
    ) async throws -> AsyncStream<String> {
        // Convert messages to support multimodal content
        var multimodalMessages = messages

        // Add images to the last user message if attachments provided
        if !attachments.isEmpty, let lastIndex = multimodalMessages.lastIndex(where: { $0.role == "user" }) {
            var contentParts: [ContentPart] = []

            // Add existing text content
            if let text = multimodalMessages[lastIndex].content {
                contentParts.append(.text(text))
            }

            // Add image parts
            for attachment in attachments {
                let dataURI = "data:\(attachment.mimeType);base64,\(attachment.base64Data)"
                contentParts.append(.imageURL(ContentPart.ImageURL(url: dataURI, detail: "auto")))
            }

            // Replace the message with multimodal version
            multimodalMessages[lastIndex] = ChatMessage(role: "user", contentParts: contentParts)
        }

        return try await streamChat(
            messages: multimodalMessages,
            parameters: parameters,
            tools: tools,
            toolChoice: toolChoice
        )
    }

    // MARK: - Private API Methods

    /// Fetch available models from the API
    private func fetchModels() async throws -> ModelsResponse {
        let url = URL(string: "\(baseURL)/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenAICompatibleError.invalidResponse
        }

        return try JSONDecoder().decode(ModelsResponse.self, from: data)
    }

    /// Generate a complete (non-streaming) chat completion
    private func generateChatCompletion(
        messages: [ChatMessage],
        parameters: GenerationParameters,
        tools: [Tool]?,
        toolChoice: ToolChoiceOption?
    ) async throws -> String {
        let request = ChatCompletionRequest(
            model: defaultModel,
            messages: messages,
            temperature: parameters.temperature,
            max_tokens: parameters.maxTokens,
            stream: false,
            top_p: nil,
            frequency_penalty: nil,
            presence_penalty: nil,
            stop: nil,
            n: nil,
            tools: tools,
            tool_choice: toolChoice,
            session_id: nil
        )

        let url = URL(string: "\(baseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Try to parse error response
            if let errorResponse = try? JSONDecoder().decode(OpenAIError.self, from: data) {
                throw OpenAICompatibleError.apiError(errorResponse.error.message)
            }
            throw OpenAICompatibleError.invalidResponse
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        // Check for tool calls
        if let toolCalls = completion.choices.first?.message.tool_calls, !toolCalls.isEmpty {
            let firstCall = toolCalls[0]
            throw ServiceToolInvocation(
                toolName: firstCall.function.name,
                jsonArguments: firstCall.function.arguments
            )
        }

        return completion.choices.first?.message.content ?? ""
    }

    /// Stream chat completion responses using SSE
    private func streamChat(
        messages: [ChatMessage],
        parameters: GenerationParameters,
        tools: [Tool]?,
        toolChoice: ToolChoiceOption?
    ) async throws -> AsyncStream<String> {
        let request = ChatCompletionRequest(
            model: defaultModel,
            messages: messages,
            temperature: parameters.temperature,
            max_tokens: parameters.maxTokens,
            stream: true,
            top_p: nil,
            frequency_penalty: nil,
            presence_penalty: nil,
            stop: nil,
            n: nil,
            tools: tools,
            tool_choice: toolChoice,
            session_id: nil
        )

        let url = URL(string: "\(baseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let apiKey = apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try JSONEncoder().encode(request)

        return AsyncStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.yield("Error: Invalid response")
                        continuation.finish()
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        continuation.yield("Error: HTTP \(httpResponse.statusCode)")
                        continuation.finish()
                        return
                    }

                    // Process SSE stream
                    try await processSSEStream(
                        bytes: bytes,
                        continuation: continuation
                    )

                } catch {
                    continuation.yield("Error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    /// Process Server-Sent Events stream
    private func processSSEStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncStream<String>.Continuation
    ) async throws {
        var buffer = ""
        var accumulatedToolCalls: [Int: AccumulatedToolCall] = [:]

        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))
            buffer.append(char)

            // Process complete lines
            while let lineEnd = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<lineEnd]).trimmingCharacters(in: .whitespaces)
                buffer.removeSubrange(...lineEnd)

                // Skip empty lines and comments
                if line.isEmpty || line.hasPrefix(":") {
                    continue
                }

                // Parse SSE format: "data: {json}"
                if line.hasPrefix("data: ") {
                    let jsonString = line.dropFirst(6) // Remove "data: "

                    // Check for [DONE] signal
                    if jsonString == "[DONE]" {
                        // Handle any accumulated tool calls
                        if let firstToolCall = accumulatedToolCalls.values.first {
                            throw ServiceToolInvocation(
                                toolName: firstToolCall.name,
                                jsonArguments: firstToolCall.arguments
                            )
                        }
                        continuation.finish()
                        return
                    }

                    // Parse JSON chunk
                    guard let jsonData = jsonString.data(using: .utf8) else {
                        continue
                    }

                    do {
                        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData)

                        // Extract content delta
                        if let delta = chunk.choices.first?.delta {
                            // Handle tool calls
                            if let toolCalls = delta.tool_calls {
                                for toolCall in toolCalls {
                                    let index = toolCall.index ?? 0

                                    if accumulatedToolCalls[index] == nil {
                                        accumulatedToolCalls[index] = AccumulatedToolCall(
                                            id: toolCall.id ?? "",
                                            name: toolCall.function?.name ?? "",
                                            arguments: toolCall.function?.arguments ?? ""
                                        )
                                    } else {
                                        if let name = toolCall.function?.name {
                                            accumulatedToolCalls[index]?.name += name
                                        }
                                        if let args = toolCall.function?.arguments {
                                            accumulatedToolCalls[index]?.arguments += args
                                        }
                                    }
                                }
                            }

                            // Handle text content
                            if let content = delta.content, !content.isEmpty {
                                continuation.yield(content)
                            }
                        }

                        // Check finish reason
                        if let finishReason = chunk.choices.first?.finish_reason {
                            if finishReason == "tool_calls" {
                                // Throw accumulated tool call
                                if let firstToolCall = accumulatedToolCalls.values.first {
                                    throw ServiceToolInvocation(
                                        toolName: firstToolCall.name,
                                        jsonArguments: firstToolCall.arguments
                                    )
                                }
                            }
                        }
                    } catch is DecodingError {
                        // Skip malformed chunks
                        continue
                    } catch {
                        // Re-throw ServiceToolInvocation
                        throw error
                    }
                }
            }
        }

        continuation.finish()
    }
}

// MARK: - Supporting Types

/// Accumulated tool call information during streaming
private struct AccumulatedToolCall {
    var id: String
    var name: String
    var arguments: String
}

// MARK: - Errors

enum OpenAICompatibleError: Error, LocalizedError {
    case invalidResponse
    case apiError(String)
    case noModelsAvailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received invalid response from API endpoint"
        case .apiError(let message):
            return "API error: \(message)"
        case .noModelsAvailable:
            return "No models available on the API endpoint"
        }
    }
}
