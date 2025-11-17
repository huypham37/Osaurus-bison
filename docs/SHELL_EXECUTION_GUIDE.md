# Shell Execution Guide

> Guide for using the shell execution agent feature in Osaurus

**Added in:** v1.x
**Security Level:** 🔴 HIGH RISK - Use with caution

---

## Table of Contents

1. [Overview](#overview)
2. [Security Considerations](#security-considerations)
3. [Configuration](#configuration)
4. [Usage](#usage)
5. [Examples](#examples)
6. [API Reference](#api-reference)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The shell execution feature allows LLMs to execute shell commands on your system through a built-in tool called `execute_shell`. When enabled, the model can request shell command execution, Osaurus will automatically execute them, and return the results.

### Key Features

- **Automatic Execution**: When the model requests a shell command, Osaurus executes it automatically
- **Timeout Protection**: Commands have configurable timeout limits (default: 30 seconds)
- **Output Capture**: Both stdout and stderr are captured and returned
- **Exit Code Tracking**: Command exit codes are included in results
- **Execution Time**: Measures how long commands take to execute

### Architecture

```
┌─────────────────┐
│   LLM Request   │
│  with tools     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│  AsyncHTTPHandler       │
│  - Detects tool call    │
│  - Checks if built-in   │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  BuiltInToolsService    │
│  - Validates args       │
│  - Routes to executor   │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  ShellExecutionService  │
│  - Spawns Process       │
│  - Captures output      │
│  - Enforces timeout     │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  Return result to LLM   │
│  - stdout/stderr        │
│  - exit code            │
│  - execution time       │
└─────────────────────────┘
```

---

## Security Considerations

⚠️ **WARNING**: Enabling shell execution allows the LLM to run ANY shell command on your system. This is extremely powerful and potentially dangerous.

### Risks

1. **Data Deletion**: Commands like `rm -rf /` could delete your entire system
2. **Data Exfiltration**: Commands could upload your files to remote servers
3. **System Compromise**: Commands could install malware or create backdoors
4. **Network Attacks**: Commands could be used to attack other systems
5. **Privilege Escalation**: If Osaurus runs with elevated privileges, so do the commands

### Best Practices

✅ **DO**:
- Only enable shell execution when absolutely necessary
- Run Osaurus with minimal user privileges (never as root)
- Use it in sandboxed environments (VMs, containers)
- Monitor the commands being executed
- Set appropriate timeout limits
- Keep your system and Osaurus updated

❌ **DON'T**:
- Enable shell execution on production servers
- Run Osaurus as root/administrator
- Use it with untrusted LLM models or prompts
- Leave it enabled when not actively needed
- Execute commands from untrusted sources

---

## Configuration

### Server Configuration

Shell execution is controlled by two settings in `ServerConfiguration`:

```swift
// Enable/disable shell execution (default: false)
public var enableShellExecution: Bool = false

// Timeout in seconds (default: 30.0)
public var shellExecutionTimeout: TimeInterval = 30.0
```

### Configuration File

Edit `~/Library/Application Support/com.dinoki.osaurus/ServerConfiguration.json`:

```json
{
  "port": 1337,
  "enableShellExecution": true,
  "shellExecutionTimeout": 30.0,
  "exposeToNetwork": false,
  ...
}
```

### Environment Variables

You can also override settings via environment variables:

```bash
# Enable shell execution
export OSU_SHELL_EXECUTION=1

# Set timeout (in seconds)
export OSU_SHELL_TIMEOUT=60
```

### Programmatic Configuration

From Swift code:

```swift
// Configure before starting server
var config = ServerConfiguration.default
config.enableShellExecution = true
config.shellExecutionTimeout = 60.0

// Apply to server
serverController.configuration = config
await serverController.startServer()
```

---

## Usage

### Basic Workflow

1. **Enable shell execution** in server configuration
2. **Include the `execute_shell` tool** in your API request
3. **Ask the model** to perform tasks requiring shell commands
4. **Model decides** when to use the shell
5. **Osaurus executes** the command automatically
6. **Result is returned** to the model
7. **Model continues** with the information

### API Request Format

#### Using OpenAI-compatible API

```bash
curl -X POST http://localhost:1337/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.2-3b-instruct-4bit",
    "messages": [
      {
        "role": "user",
        "content": "What is the current directory and list its files?"
      }
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "execute_shell",
          "description": "Execute a shell command on the system",
          "parameters": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string",
                "description": "The shell command to execute"
              }
            },
            "required": ["command"]
          }
        }
      }
    ]
  }'
```

#### Using Python OpenAI SDK

```python
from openai import OpenAI

# Point to your local Osaurus server
client = OpenAI(
    base_url="http://localhost:1337/v1",
    api_key="not-needed"  # Osaurus doesn't require API keys
)

# Define the shell execution tool
tools = [
    {
        "type": "function",
        "function": {
            "name": "execute_shell",
            "description": "Execute a shell command on the system",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The shell command to execute"
                    }
                },
                "required": ["command"]
            }
        }
    }
]

# Make a request
response = client.chat.completions.create(
    model="llama-3.2-3b-instruct-4bit",
    messages=[
        {"role": "user", "content": "What files are in the current directory?"}
    ],
    tools=tools
)

print(response.choices[0].message.content)
```

---

## Examples

### Example 1: List Directory Contents

**Request**:
```json
{
  "model": "llama-3.2-3b-instruct-4bit",
  "messages": [
    {"role": "user", "content": "List all files in /tmp"}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "execute_shell",
        "description": "Execute a shell command",
        "parameters": {
          "type": "object",
          "properties": {
            "command": {"type": "string"}
          },
          "required": ["command"]
        }
      }
    }
  ]
}
```

**Model Executes**: `ls -la /tmp`

**Response**:
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "Tool 'execute_shell' executed successfully:\n\ntotal 8\ndrwxrwxrwt  5 root  wheel  160 Nov 17 10:30 .\ndrwxr-xr-x 20 root  wheel  640 Nov 15 09:00 ..\n...\n\nExit code: 0\nExecution time: 0.012s"
    }
  }]
}
```

### Example 2: Check System Information

**Python**:
```python
response = client.chat.completions.create(
    model="llama-3.2-3b-instruct-4bit",
    messages=[
        {"role": "user", "content": "What's the current system uptime and load?"}
    ],
    tools=tools
)
```

**Model Executes**: `uptime`

**Result**:
```
Tool 'execute_shell' executed successfully:

10:30  up 5 days,  2:15, 3 users, load averages: 1.52 1.48 1.45

Exit code: 0
Execution time: 0.008s
```

### Example 3: Git Repository Status

```python
response = client.chat.completions.create(
    model="llama-3.2-3b-instruct-4bit",
    messages=[
        {"role": "user", "content": "What's the status of this git repository?"}
    ],
    tools=tools
)
```

**Model Executes**: `git status`

### Example 4: Process Information

```python
response = client.chat.completions.create(
    model="llama-3.2-3b-instruct-4bit",
    messages=[
        {"role": "user", "content": "How many Python processes are running?"}
    ],
    tools=tools
)
```

**Model Executes**: `ps aux | grep python | wc -l`

---

## API Reference

### Tool Definition

**Name**: `execute_shell`

**Parameters**:
- `command` (string, required): The shell command to execute

**Returns**: A text response containing:
- Standard output (stdout)
- Standard error (stderr) if present
- Exit code
- Execution time in seconds

### ShellExecutionService

**Location**: `osaurus/Services/ShellExecutionService.swift`

#### Properties

```swift
var timeoutSeconds: TimeInterval  // Default: 30.0
var isEnabled: Bool               // Default: false
var workingDirectory: URL         // Default: user's home
```

#### Methods

```swift
// Execute a command
func execute(
    command: String,
    workingDir: URL? = nil,
    timeout: TimeInterval? = nil
) async throws -> ShellExecutionResult

// Execute and return just stdout
func executeForOutput(_ command: String) async throws -> String

// Check if a command exists
func commandExists(_ commandName: String) async -> Bool
```

#### ShellExecutionResult

```swift
struct ShellExecutionResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool
    let executionTime: TimeInterval
}
```

#### Errors

```swift
enum ShellExecutionError: Error {
    case commandNotFound
    case executionFailed(String)
    case timeout
    case disabled
    case invalidCommand
}
```

### BuiltInToolsService

**Location**: `osaurus/Services/BuiltInToolsService.swift`

```swift
// Get all built-in tools
func getBuiltInTools() -> [Tool]

// Execute a tool by name
func executeTool(
    name: String,
    arguments: String
) async -> ToolExecutionResult

// Check if tool is built-in
func isBuiltInTool(_ toolName: String) -> Bool
```

---

## Troubleshooting

### Command Not Executing

**Problem**: Model requests shell execution but nothing happens

**Solutions**:
1. Check that `enableShellExecution` is `true` in configuration
2. Verify the server was restarted after changing configuration
3. Check server logs for error messages
4. Ensure the tool is included in the API request

### Timeout Errors

**Problem**: Commands timing out before completion

**Solutions**:
1. Increase `shellExecutionTimeout` in configuration
2. Optimize the command to run faster
3. Break long operations into smaller commands
4. Check if the command is hanging (waiting for input)

### Permission Denied

**Problem**: Commands fail with permission errors

**Solutions**:
1. Ensure Osaurus has necessary file system permissions
2. Don't try to access protected system files
3. Consider running specific operations with proper permissions
4. Use `chmod`/`chown` if appropriate (carefully!)

### Command Not Found

**Problem**: Shell commands fail with "command not found"

**Solutions**:
1. Use full path to executable: `/usr/bin/python` not `python`
2. Check if command is in PATH
3. Verify the command exists on the system
4. Try executing manually first to debug

### Unexpected Output

**Problem**: Command output is not what's expected

**Solutions**:
1. Test the command manually in terminal first
2. Check for stderr output in addition to stdout
3. Verify exit code (0 = success, non-zero = error)
4. Consider environment differences (PATH, HOME, etc.)

---

## Integration Examples

### Jupyter Notebook Style Agent

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:1337/v1", api_key="none")

def create_code_agent():
    """Create an agent that can execute shell commands"""
    tools = [{
        "type": "function",
        "function": {
            "name": "execute_shell",
            "description": "Execute shell commands for system operations",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string"}
                },
                "required": ["command"]
            }
        }
    }]

    return tools

# Use the agent
tools = create_code_agent()
response = client.chat.completions.create(
    model="llama-3.2-3b-instruct-4bit",
    messages=[
        {
            "role": "system",
            "content": "You are a helpful coding assistant with access to shell commands."
        },
        {
            "role": "user",
            "content": "Create a new directory called 'test_project' and show me its path"
        }
    ],
    tools=tools
)

print(response.choices[0].message.content)
```

### DevOps Helper

```python
def devops_agent(task: str):
    """Agent for DevOps tasks"""
    tools = create_code_agent()

    system_prompt = """You are a DevOps assistant. You can execute shell commands to:
    - Check system status
    - Monitor processes
    - Review logs
    - Check disk usage
    - View network connections

    Always explain what you're doing before executing commands."""

    response = client.chat.completions.create(
        model="llama-3.2-3b-instruct-4bit",
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": task}
        ],
        tools=tools
    )

    return response.choices[0].message.content

# Use it
result = devops_agent("Check the current disk usage and list the largest directories")
print(result)
```

---

## Future Enhancements

Potential improvements for future versions:

- [ ] Command whitelisting/blacklisting
- [ ] Working directory per-request
- [ ] Environment variable injection
- [ ] Interactive command support (stdin)
- [ ] Streaming command output
- [ ] Command history and auditing
- [ ] Sandbox mode (restricted command set)
- [ ] Multi-step agent loops (execute → analyze → execute)
- [ ] Shell session persistence across requests

---

## Resources

- **Main Documentation**: `/README.md`
- **Service Code**: `osaurus/Services/ShellExecutionService.swift`
- **Built-in Tools**: `osaurus/Services/BuiltInToolsService.swift`
- **Handler Integration**: `osaurus/Networking/AsyncHTTPHandler.swift`
- **Configuration**: `osaurus/Models/ServerConfiguration.swift`

---

**Last Updated**: 2025-11-17
**Version**: 1.0
**Maintainer**: Osaurus Contributors
