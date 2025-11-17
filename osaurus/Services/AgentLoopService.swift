//
//  AgentLoopService.swift
//  osaurus
//
//  Service for handling agent mode with automatic tool execution
//

import Foundation

/// Configuration for agent loop execution
struct AgentLoopConfiguration {
    /// Maximum number of iterations (tool call -> execution -> continue)
    let maxIterations: Int
    /// Whether to enable agent mode at all
    let enabled: Bool

    static let `default` = AgentLoopConfiguration(
        maxIterations: 5,
        enabled: false
    )
}

/// Result of an agent loop execution
enum AgentLoopResult {
    case completion(text: String)
    case toolCall(name: String, arguments: String, callId: String)
    case error(String)
    case maxIterationsReached
}

/// Service for managing agent loops with automatic tool execution
final class AgentLoopService {

    // MARK: - Singleton

    static let shared = AgentLoopService()

    private init() {}

    // MARK: - Configuration

    var configuration = AgentLoopConfiguration.default

    // MARK: - Agent Loop Execution

    /// Execute an agent loop with automatic tool execution
    /// - Parameters:
    ///   - messages: Initial conversation messages
    ///   - tools: Available tools
    ///   - service: Model service to use
    ///   - parameters: Generation parameters
    ///   - onIteration: Callback for each iteration (tool call and result)
    /// - Returns: Final result after all iterations
    func executeLoop(
        messages: [Message],
        tools: [Tool],
        service: ModelService,
        parameters: GenerationParameters,
        onIteration: ((String, ToolExecutionResult) async -> Void)? = nil
    ) async -> AgentLoopResult {
        var conversationMessages = messages
        var iterationCount = 0

        while iterationCount < configuration.maxIterations {
            iterationCount += 1

            // Try to generate with current messages
            let prompt = PromptBuilder.buildPrompt(from: conversationMessages)

            do {
                // Check if service supports tools
                guard let toolService = service as? ToolCapableService else {
                    // No tool support, just generate normally
                    let text = try await service.generate(
                        prompt: prompt,
                        parameters: parameters,
                        stopSequences: []
                    )
                    return .completion(text: text)
                }

                // Generate with tools
                let result = try await toolService.respondWithTools(
                    prompt: prompt,
                    parameters: parameters,
                    stopSequences: [],
                    tools: tools,
                    toolChoice: nil
                )

                // If we got a completion, return it
                return .completion(text: result)

            } catch let inv as ServiceToolInvocation {
                // Tool was called - check if it's a built-in tool
                guard BuiltInToolsService.shared.isBuiltInTool(inv.toolName) else {
                    // Not a built-in tool, return it to the client to handle
                    return .toolCall(
                        name: inv.toolName,
                        arguments: inv.jsonArguments,
                        callId: "call_\(UUID().uuidString.prefix(8))"
                    )
                }

                // Execute the built-in tool
                let callId = "call_\(UUID().uuidString.prefix(8))"
                let executionResult = await BuiltInToolsService.shared.executeTool(
                    name: inv.toolName,
                    arguments: inv.jsonArguments
                )

                // Call the iteration callback if provided
                if let onIteration = onIteration {
                    await onIteration(inv.toolName, executionResult)
                }

                // Format tool result for the model
                let toolResultContent: String
                if executionResult.success {
                    toolResultContent = executionResult.output
                } else {
                    toolResultContent = "Error: \(executionResult.error ?? "Unknown error")\n\n\(executionResult.output)"
                }

                // Add assistant's tool call to conversation
                // Note: This is simplified - in a full implementation, we'd track the exact format
                conversationMessages.append(Message(
                    role: .assistant,
                    content: "Using tool: \(inv.toolName)"
                ))

                // Add tool result to conversation
                conversationMessages.append(Message(
                    role: .system,  // Use system role for tool results (simpler than tool role)
                    content: "Tool '\(inv.toolName)' result:\n\(toolResultContent)"
                ))

                // Continue loop with updated messages
                continue

            } catch {
                return .error(error.localizedDescription)
            }
        }

        return .maxIterationsReached
    }

    /// Check if agent mode should be enabled for a request
    func shouldEnableAgentMode(request: ChatCompletionRequest, serverConfig: ServerConfiguration) -> Bool {
        // Agent mode requires:
        // 1. Shell execution enabled in server config
        // 2. Tools provided in request
        // 3. At least one built-in tool in the tools list

        guard serverConfig.enableShellExecution else { return false }
        guard let tools = request.tools, !tools.isEmpty else { return false }

        // Check if any tool is a built-in tool
        let hasBuiltInTool = tools.contains { tool in
            BuiltInToolsService.shared.isBuiltInTool(tool.function.name)
        }

        return hasBuiltInTool
    }
}

// MARK: - Extensions

extension ChatCompletionRequest {
    /// Convert to internal messages for agent loop
    func toInternalAgentMessages() -> [Message] {
        return messages.map { openAIMsg in
            Message(
                role: Message.Role(rawValue: openAIMsg.role) ?? .user,
                content: openAIMsg.content ?? ""
            )
        }
    }
}
