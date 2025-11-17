//
//  BuiltInToolsService.swift
//  osaurus
//
//  Service for managing and executing built-in tools available to LLMs
//

import Foundation

/// Result of a built-in tool execution
struct ToolExecutionResult {
    let success: Bool
    let output: String
    let error: String?
}

/// Service for managing built-in tools
final class BuiltInToolsService {

    // MARK: - Singleton

    static let shared = BuiltInToolsService()

    private init() {}

    // MARK: - Built-in Tool Definitions

    /// Get all available built-in tools
    func getBuiltInTools() -> [Tool] {
        var tools: [Tool] = []

        // Add shell execution tool if enabled
        if ShellExecutionService.shared.isEnabled {
            tools.append(shellExecutionTool)
        }

        return tools
    }

    /// Shell execution tool definition
    private var shellExecutionTool: Tool {
        Tool(
            type: "function",
            function: ToolFunction(
                name: "execute_shell",
                description: """
                    Execute a shell command on the system. Use this to run terminal commands, \
                    check system status, read files, or perform system operations. \
                    The command will be executed with a timeout of \(Int(ShellExecutionService.shared.timeoutSeconds)) seconds.
                    """,
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object([
                            "type": .string("string"),
                            "description": .string("The shell command to execute (e.g., 'ls -la /tmp', 'git status', 'python script.py')")
                        ])
                    ]),
                    "required": .array([.string("command")])
                ])
            )
        )
    }

    // MARK: - Tool Execution

    /// Execute a built-in tool by name
    /// - Parameters:
    ///   - toolName: Name of the tool to execute
    ///   - arguments: JSON string containing tool arguments
    /// - Returns: ToolExecutionResult with output and error information
    func executeTool(name toolName: String, arguments: String) async -> ToolExecutionResult {
        switch toolName {
        case "execute_shell":
            return await executeShellTool(arguments: arguments)

        default:
            return ToolExecutionResult(
                success: false,
                output: "",
                error: "Unknown tool: \(toolName)"
            )
        }
    }

    /// Check if a tool name is a built-in tool
    func isBuiltInTool(_ toolName: String) -> Bool {
        let builtInNames = getBuiltInTools().map { $0.function.name }
        return builtInNames.contains(toolName)
    }

    // MARK: - Individual Tool Implementations

    private func executeShellTool(arguments: String) async -> ToolExecutionResult {
        // Parse arguments JSON
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String else {
            return ToolExecutionResult(
                success: false,
                output: "",
                error: "Invalid arguments for execute_shell. Expected: {\"command\": \"string\"}"
            )
        }

        // Execute the command
        do {
            let result = try await ShellExecutionService.shared.execute(command: command)

            // Format output
            var output = ""
            if !result.stdout.isEmpty {
                output += result.stdout
            }
            if !result.stderr.isEmpty {
                if !output.isEmpty { output += "\n\n" }
                output += "STDERR:\n\(result.stderr)"
            }

            if output.isEmpty {
                output = "(no output)"
            }

            // Include exit code and execution time
            output += "\n\nExit code: \(result.exitCode)"
            output += "\nExecution time: \(String(format: "%.3f", result.executionTime))s"

            return ToolExecutionResult(
                success: result.exitCode == 0,
                output: output,
                error: result.exitCode != 0 ? "Command exited with code \(result.exitCode)" : nil
            )
        } catch {
            return ToolExecutionResult(
                success: false,
                output: "",
                error: "Shell execution failed: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Request Extensions for Agent Mode

extension ChatCompletionRequest {
    /// Whether agent mode is enabled (auto-execute built-in tools)
    var agentMode: Bool {
        // Check for custom parameter in the request
        // This would need to be added to ChatCompletionRequest struct
        // For now, we'll use a heuristic: if tools are provided and include execute_shell,
        // we assume agent mode is desired
        guard let tools = tools else { return false }
        return tools.contains { $0.function.name == "execute_shell" }
    }
}
