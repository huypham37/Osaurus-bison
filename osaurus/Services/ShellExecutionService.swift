//
//  ShellExecutionService.swift
//  osaurus
//
//  Service for executing shell commands from LLM-generated tool calls
//

import Foundation

/// Result of a shell command execution
struct ShellExecutionResult: Codable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool
    let executionTime: TimeInterval
}

/// Errors that can occur during shell execution
enum ShellExecutionError: Error, LocalizedError {
    case commandNotFound
    case executionFailed(String)
    case timeout
    case disabled
    case invalidCommand

    var errorDescription: String? {
        switch self {
        case .commandNotFound:
            return "Command executable not found"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        case .timeout:
            return "Command execution timed out"
        case .disabled:
            return "Shell execution is disabled in configuration"
        case .invalidCommand:
            return "Invalid or empty command"
        }
    }
}

/// Service for executing shell commands safely with timeout and output capture
final class ShellExecutionService {

    // MARK: - Singleton

    static let shared = ShellExecutionService()

    private init() {}

    // MARK: - Configuration

    /// Maximum execution time in seconds (default: 30 seconds)
    var timeoutSeconds: TimeInterval = 30.0

    /// Whether shell execution is enabled (default: false for security)
    var isEnabled: Bool = false

    /// Working directory for command execution (default: user's home directory)
    var workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser

    // MARK: - Public API

    /// Execute a shell command asynchronously
    /// - Parameters:
    ///   - command: The shell command to execute (e.g., "ls -la /tmp")
    ///   - workingDir: Optional working directory (defaults to service's workingDirectory)
    ///   - timeout: Optional timeout in seconds (defaults to service's timeoutSeconds)
    /// - Returns: ShellExecutionResult containing stdout, stderr, exit code, and metadata
    /// - Throws: ShellExecutionError if execution fails
    func execute(
        command: String,
        workingDir: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ShellExecutionResult {
        // Check if enabled
        guard isEnabled else {
            throw ShellExecutionError.disabled
        }

        // Validate command
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            throw ShellExecutionError.invalidCommand
        }

        let effectiveTimeout = timeout ?? timeoutSeconds
        let effectiveWorkingDir = workingDir ?? workingDirectory
        let startTime = Date()

        // Execute command with timeout
        return try await withThrowingTaskGroup(of: ShellExecutionResult.self) { group in
            // Execution task
            group.addTask {
                try await self.executeCommand(
                    trimmedCommand,
                    workingDirectory: effectiveWorkingDir
                )
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                throw ShellExecutionError.timeout
            }

            // Return the first result (either completion or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Private Implementation

    private func executeCommand(
        _ command: String,
        workingDirectory: URL
    ) async throws -> ShellExecutionResult {
        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()

            // Use /bin/sh to execute the command
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = workingDirectory

            // Set up pipes for output capture
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Capture output data
            var stdoutData = Data()
            var stderrData = Data()

            // Read stdout
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stdoutData.append(data)
                }
            }

            // Read stderr
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stderrData.append(data)
                }
            }

            // Termination handler
            process.terminationHandler = { process in
                // Close pipes
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // Read any remaining data
                stdoutData.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                stderrData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

                // Convert to strings
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let exitCode = process.terminationStatus
                let executionTime = Date().timeIntervalSince(startTime)

                let result = ShellExecutionResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: exitCode,
                    timedOut: false,
                    executionTime: executionTime
                )

                continuation.resume(returning: result)
            }

            // Start the process
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellExecutionError.executionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Convenience Methods

    /// Execute a command and return just the stdout as a string
    func executeForOutput(_ command: String) async throws -> String {
        let result = try await execute(command: command)

        // If command failed, throw error with stderr
        guard result.exitCode == 0 else {
            throw ShellExecutionError.executionFailed(
                "Exit code \(result.exitCode): \(result.stderr)"
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if a command exists in PATH
    func commandExists(_ commandName: String) async -> Bool {
        do {
            let result = try await execute(command: "which \(commandName)")
            return result.exitCode == 0
        } catch {
            return false
        }
    }
}

// MARK: - Debug Description

extension ShellExecutionResult: CustomStringConvertible {
    var description: String {
        var parts = [String]()
        parts.append("Exit Code: \(exitCode)")
        parts.append("Execution Time: \(String(format: "%.3f", executionTime))s")
        if timedOut {
            parts.append("Status: TIMED OUT")
        }
        if !stdout.isEmpty {
            parts.append("STDOUT:\n\(stdout)")
        }
        if !stderr.isEmpty {
            parts.append("STDERR:\n\(stderr)")
        }
        return parts.joined(separator: "\n")
    }
}
