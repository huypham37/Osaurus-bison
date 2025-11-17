#!/usr/bin/env python3
"""
Shell Execution Demo for Osaurus

This script demonstrates how to use the shell execution agent feature.

Prerequisites:
1. Osaurus server running on localhost:1337
2. Shell execution enabled in server configuration
3. A compatible model loaded (e.g., llama-3.2-3b-instruct-4bit)

Usage:
    python3 examples/shell_execution_demo.py
"""

from openai import OpenAI
import json
import sys


def create_client():
    """Create OpenAI client pointing to local Osaurus server"""
    return OpenAI(
        base_url="http://localhost:1337/v1",
        api_key="not-needed"  # Osaurus doesn't require API keys
    )


def get_shell_tool():
    """Define the execute_shell tool"""
    return {
        "type": "function",
        "function": {
            "name": "execute_shell",
            "description": (
                "Execute a shell command on the system. Use this to run terminal commands, "
                "check system status, read files, or perform system operations."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The shell command to execute (e.g., 'ls -la /tmp', 'git status')"
                    }
                },
                "required": ["command"]
            }
        }
    }


def demo_basic_execution(client):
    """Demo 1: Basic command execution"""
    print("\n" + "="*70)
    print("DEMO 1: Basic Shell Command Execution")
    print("="*70)

    response = client.chat.completions.create(
        model="llama-3.2-3b-instruct-4bit",
        messages=[
            {
                "role": "user",
                "content": "List the files in the current directory using ls -la"
            }
        ],
        tools=[get_shell_tool()]
    )

    print(f"\nModel Response:")
    print(response.choices[0].message.content)
    print(f"\nFinish Reason: {response.choices[0].finish_reason}")


def demo_system_info(client):
    """Demo 2: Gathering system information"""
    print("\n" + "="*70)
    print("DEMO 2: System Information Gathering")
    print("="*70)

    response = client.chat.completions.create(
        model="llama-3.2-3b-instruct-4bit",
        messages=[
            {
                "role": "user",
                "content": "What's the current date and time on the system?"
            }
        ],
        tools=[get_shell_tool()]
    )

    print(f"\nModel Response:")
    print(response.choices[0].message.content)


def demo_multi_step(client):
    """Demo 3: Multi-step conversation with shell access"""
    print("\n" + "="*70)
    print("DEMO 3: Multi-Step Conversation")
    print("="*70)

    messages = [
        {
            "role": "system",
            "content": (
                "You are a helpful assistant with access to shell commands. "
                "When asked about the system, use shell commands to find accurate information."
            )
        },
        {
            "role": "user",
            "content": "Tell me about this system - OS, hostname, and current user"
        }
    ]

    response = client.chat.completions.create(
        model="llama-3.2-3b-instruct-4bit",
        messages=messages,
        tools=[get_shell_tool()]
    )

    print(f"\nModel Response:")
    print(response.choices[0].message.content)

    # Continue conversation
    messages.append({
        "role": "assistant",
        "content": response.choices[0].message.content
    })
    messages.append({
        "role": "user",
        "content": "Now tell me how much disk space is available"
    })

    response = client.chat.completions.create(
        model="llama-3.2-3b-instruct-4bit",
        messages=messages,
        tools=[get_shell_tool()]
    )

    print(f"\nFollow-up Response:")
    print(response.choices[0].message.content)


def demo_git_operations(client):
    """Demo 4: Git repository operations"""
    print("\n" + "="*70)
    print("DEMO 4: Git Repository Operations")
    print("="*70)

    response = client.chat.completions.create(
        model="llama-3.2-3b-instruct-4bit",
        messages=[
            {
                "role": "user",
                "content": "Check the git status of the current directory"
            }
        ],
        tools=[get_shell_tool()]
    )

    print(f"\nModel Response:")
    print(response.choices[0].message.content)


def demo_error_handling(client):
    """Demo 5: Error handling for failed commands"""
    print("\n" + "="*70)
    print("DEMO 5: Error Handling")
    print("="*70)

    response = client.chat.completions.create(
        model="llama-3.2-3b-instruct-4bit",
        messages=[
            {
                "role": "user",
                "content": "Try to list files in /nonexistent/directory"
            }
        ],
        tools=[get_shell_tool()]
    )

    print(f"\nModel Response:")
    print(response.choices[0].message.content)


def demo_interactive_agent(client):
    """Demo 6: Interactive agent conversation"""
    print("\n" + "="*70)
    print("DEMO 6: Interactive Agent")
    print("="*70)
    print("Type 'quit' to exit\n")

    messages = [
        {
            "role": "system",
            "content": (
                "You are a helpful system administration assistant. "
                "You have access to shell commands. When users ask questions about the system, "
                "use shell commands to find accurate, real-time information. "
                "Always explain what you're doing."
            )
        }
    ]

    while True:
        try:
            user_input = input("You: ").strip()
            if not user_input:
                continue
            if user_input.lower() in ['quit', 'exit', 'q']:
                print("Goodbye!")
                break

            messages.append({
                "role": "user",
                "content": user_input
            })

            response = client.chat.completions.create(
                model="llama-3.2-3b-instruct-4bit",
                messages=messages,
                tools=[get_shell_tool()]
            )

            assistant_message = response.choices[0].message.content
            messages.append({
                "role": "assistant",
                "content": assistant_message
            })

            print(f"\nAssistant: {assistant_message}\n")

        except KeyboardInterrupt:
            print("\n\nGoodbye!")
            break
        except Exception as e:
            print(f"\nError: {e}")


def check_server_health(client):
    """Check if Osaurus server is running and accessible"""
    try:
        # Try to list models
        models = client.models.list()
        print(f"✓ Connected to Osaurus server")
        print(f"✓ Available models: {len(models.data)}")
        if models.data:
            print(f"  First model: {models.data[0].id}")
        return True
    except Exception as e:
        print(f"✗ Failed to connect to Osaurus server: {e}")
        print(f"\nMake sure:")
        print(f"  1. Osaurus is running (osaurus serve)")
        print(f"  2. Server is listening on http://localhost:1337")
        print(f"  3. Shell execution is enabled in configuration")
        return False


def main():
    """Run all demos"""
    print("="*70)
    print("OSAURUS SHELL EXECUTION DEMO")
    print("="*70)

    # Create client
    client = create_client()

    # Check server health
    if not check_server_health(client):
        sys.exit(1)

    # Run demos
    try:
        demo_basic_execution(client)
        demo_system_info(client)
        demo_multi_step(client)
        demo_git_operations(client)
        demo_error_handling(client)

        # Interactive demo (optional)
        print("\n" + "="*70)
        run_interactive = input("Run interactive agent demo? (y/n): ").strip().lower()
        if run_interactive == 'y':
            demo_interactive_agent(client)

    except Exception as e:
        print(f"\n❌ Error running demos: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    print("\n" + "="*70)
    print("DEMOS COMPLETED")
    print("="*70)


if __name__ == "__main__":
    main()
