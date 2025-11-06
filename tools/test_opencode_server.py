#!/usr/bin/env python3
"""
---
name: OpenCode API Tester
description: Comprehensive test suite for OpenCode server API endpoints including session management, streaming, and multi-turn conversations
version: 1.0.0
author: Osaurus Tools
requires:
  - python: ">=3.7"
  - packages:
      - requests
usage: |
  ./test_opencode_server.py [--test all|server|providers|session|message|stream|conversation]
  ./test_opencode_server.py --url http://localhost:4096 --test stream
endpoints:
  - GET /config/providers
  - POST /session
  - POST /session/:id/message
---

Test script for OpenCode server API at port 4096.
Tests OpenCode-specific endpoints: /config/providers, /session, /session/:id/message
"""

import requests
import json
import sys
import time
from typing import Dict, Any, Optional


class OpenCodeAPITester:
    def __init__(self, base_url: str = "http://localhost:4096"):
        self.base_url = base_url.rstrip('/')
        self.session_id = None
        self.headers = {"Content-Type": "application/json"}
    
    def print_section(self, title: str):
        """Print a formatted section header"""
        print("\n" + "=" * 80)
        print(f"  {title}")
        print("=" * 80)
    
    def test_server_reachable(self) -> bool:
        """Test if the server is running"""
        self.print_section("Server Connectivity")
        
        try:
            response = requests.get(f"{self.base_url}/config/providers", timeout=5)
            print(f"Status Code: {response.status_code}")
            
            if response.status_code == 200:
                print("✓ OpenCode server is reachable")
                return True
            else:
                print(f"✗ Server returned: {response.status_code}")
                print(f"Response: {response.text}")
                return False
                
        except requests.exceptions.ConnectionError as e:
            print(f"✗ Cannot connect to server at {self.base_url}")
            print(f"  Error: {e}")
            print("\n💡 Tip: Start OpenCode server with: opencode serve --port 4096")
            return False
        except Exception as e:
            print(f"✗ Unexpected error: {e}")
            return False
    
    def test_get_providers(self) -> Dict[str, Any]:
        """Test GET /config/providers endpoint"""
        self.print_section("Get Providers Configuration")
        
        try:
            response = requests.get(
                f"{self.base_url}/config/providers",
                headers=self.headers,
                timeout=10
            )
            
            print(f"Status Code: {response.status_code}")
            
            if response.status_code == 200:
                data = response.json()
                print(f"\nFull Response:\n{json.dumps(data, indent=2)}")
                
                providers = data.get("providers", [])
                default_provider = data.get("default", {})
                
                print(f"\n✓ Found {len(providers)} provider(s)")
                for provider in providers:
                    provider_id = provider.get("id", "unknown")
                    provider_name = provider.get("name", "Unknown")
                    models = provider.get("models", {})
                    print(f"\n  Provider: {provider_name} (ID: {provider_id})")
                    print(f"  Available models: {len(models)}")
                    
                    # Show first few models
                    for i, (model_id, model_info) in enumerate(list(models.items())[:3]):
                        print(f"    - {model_id}")
                        if i >= 2 and len(models) > 3:
                            print(f"    ... and {len(models) - 3} more")
                            break
                
                if default_provider:
                    print(f"\nDefault provider: {default_provider.get('provider')}:{default_provider.get('model')}")
                
                return data
            else:
                print(f"✗ Failed to get providers: {response.text}")
                return {}
                
        except Exception as e:
            print(f"✗ Error getting providers: {e}")
            import traceback
            traceback.print_exc()
            return {}
    
    def test_create_session(self) -> Optional[str]:
        """Test POST /session endpoint"""
        self.print_section("Create Chat Session")
        
        payload = {
            "provider": "copilot",
            "model": "gpt-4o"
        }
        
        try:
            print(f"Request payload:\n{json.dumps(payload, indent=2)}")
            
            response = requests.post(
                f"{self.base_url}/session",
                headers=self.headers,
                json=payload,
                timeout=10
            )
            
            print(f"\nStatus Code: {response.status_code}")
            
            if response.status_code == 200 or response.status_code == 201:
                data = response.json()
                print(f"Response:\n{json.dumps(data, indent=2)}")
                
                session_id = data.get("id")
                if session_id:
                    print(f"\n✓ Session created successfully")
                    print(f"  Session ID: {session_id}")
                    self.session_id = session_id
                    return session_id
                else:
                    print("⚠️  No session ID in response")
                    return None
            else:
                print(f"✗ Failed to create session: {response.text}")
                return None
                
        except Exception as e:
            print(f"✗ Error creating session: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def test_send_message_non_streaming(self, message: str = "explain me the birthday boud paradox.") -> bool:
        """Test POST /session/:id/message (non-streaming)"""
        self.print_section(f"Send Message (Non-Streaming)")
        
        if not self.session_id:
            print("✗ No active session. Creating one first...")
            if not self.test_create_session():
                print("✗ Failed to create session")
                return False
        
        payload = {
            "parts": [{"type": "text", "text": message}],
            "stream": False
        }
        
        try:
            print(f"Session ID: {self.session_id}")
            print(f"Request payload:\n{json.dumps(payload, indent=2)}")
            
            response = requests.post(
                f"{self.base_url}/session/{self.session_id}/message",
                headers=self.headers,
                json=payload,
                timeout=30
            )
            
            print(f"\nStatus Code: {response.status_code}")
            
            if response.status_code == 200:
                data = response.json()
                print(f"\nFull Response:\n{json.dumps(data, indent=2)}")
                
                response_text = data.get("response", data.get("message", ""))
                print(f"\n--- Assistant's Response ---")
                print(response_text)
                print("---" * 20)
                
                print("\n✓ Non-streaming message successful")
                return True
            else:
                print(f"✗ Request failed: {response.text}")
                return False
                
        except Exception as e:
            print(f"✗ Error sending message: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def test_send_message_streaming(self, message: str = "Explain me the brithday bound paradox") -> bool:
        """Test POST /session/:id/message (streaming with SSE)"""
        self.print_section("Send Message (Streaming)")
        
        if not self.session_id:
            print("✗ No active session. Creating one first...")
            if not self.test_create_session():
                print("✗ Failed to create session")
                return False
        
        payload = {
            "parts": [{"type": "text", "text": message}],
            "stream": True
        }
        
        try:
            print(f"Session ID: {self.session_id}")
            print(f"Request payload:\n{json.dumps(payload, indent=2)}")
            
            # IMPORTANT: Set Accept header to text/event-stream for SSE
            stream_headers = self.headers.copy()
            stream_headers["Accept"] = "text/event-stream"
            
            response = requests.post(
                f"{self.base_url}/session/{self.session_id}/message",
                headers=stream_headers,
                json=payload,
                stream=True,
                timeout=60
            )
            
            print(f"\nStatus Code: {response.status_code}")
            print(f"Content-Type: {response.headers.get('Content-Type', 'none')}")
            
            if response.status_code != 200:
                print(f"✗ Request failed: {response.text}")
                return False
            
            # If response is JSON instead of SSE, handle it differently
            content_type = response.headers.get('Content-Type', '')
            if 'application/json' in content_type:
                print("\n⚠️  Received JSON response instead of SSE stream")
                print("    (stream=True was set but server returned JSON)")
                data = response.json()
                
                # Extract message content from parts array (OpenCode format)
                parts = data.get('parts', [])
                message_texts = []
                part_types = []
                
                for part in parts:
                    part_type = part.get('type', 'unknown')
                    part_types.append(part_type)
                    
                    if part_type == 'text':
                        text = part.get('text', '')
                        if text:
                            message_texts.append(text)
                
                print(f"\nPart types found: {', '.join(set(part_types))}")
                print(f"Total parts: {len(parts)}")
                
                # Also try top-level fields as fallback
                if not message_texts:
                    top_level = data.get('response', data.get('message', data.get('content', '')))
                    if top_level:
                        message_texts.append(top_level)
                
                if message_texts:
                    full_message = '\n'.join(message_texts)
                    print(f"\n--- Message Content ---")
                    print(full_message)
                    print("---" * 20)
                    print(f"\nMessage length: {len(full_message)} characters")
                    print("\n✓ Message received (returned as complete JSON, not streamed)")
                    return True
                else:
                    print(f"\n⚠️  No text content found in response")
                    print(f"    Response included {len(parts)} parts of types: {', '.join(set(part_types))}")
                    
                    # Show token usage if available
                    if 'info' in data and 'tokens' in data['info']:
                        tokens = data['info']['tokens']
                        print(f"    Tokens - input: {tokens.get('input', 0)}, output: {tokens.get('output', 0)}")
                    
                    # Only show full response if verbose debugging needed
                    if len(parts) < 10:  # Don't spam if too many parts
                        print(f"\nDebug - Response structure:")
                        print(json.dumps(data, indent=2))
                    
                    return False
            
            print("\n--- Streaming Response ---")
            full_content = ""
            chunk_count = 0
            event_types = set()
            current_event = ""
            
            for line in response.iter_lines():
                if line:
                    line_str = line.decode('utf-8')
                    
                    # SSE format: "event: type" or "data: content"
                    if line_str.startswith("event:"):
                        current_event = line_str[6:].strip()
                        event_types.add(current_event)
                        continue
                    
                    if line_str.startswith("data:"):
                        data_str = line_str[5:].strip()
                        
                        if data_str == "[DONE]":
                            print("\n[DONE]")
                            break
                        
                        try:
                            chunk_data = json.loads(data_str)
                            
                            # Handle message-part events (OpenCode format)
                            if current_event == "message-part":
                                part_text = chunk_data.get("text", "")
                                if part_text:
                                    chunk_count += 1
                                    full_content += part_text
                                    print(part_text, end="", flush=True)
                            
                            # Handle delta/content formats (fallback)
                            else:
                                content = chunk_data.get("delta", chunk_data.get("content", ""))
                                if content:
                                    chunk_count += 1
                                    full_content += content
                                    print(content, end="", flush=True)
                                    
                        except json.JSONDecodeError:
                            # Plain text data
                            if data_str:
                                chunk_count += 1
                                full_content += data_str
                                print(data_str, end="", flush=True)
            
            print("\n---" * 20)
            print(f"\nReceived {chunk_count} chunks")
            print(f"Event types: {event_types}")
            print(f"Total content length: {len(full_content)} characters")
            
            if full_content:
                print("\n✓ Streaming message successful")
                return True
            else:
                print("\n⚠️  No content received")
                return False
                
        except Exception as e:
            print(f"✗ Error during streaming: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def test_conversation_flow(self) -> bool:
        """Test a multi-turn conversation"""
        self.print_section("Multi-Turn Conversation")
        
        # Create a new session
        print("Step 1: Creating session...")
        if not self.test_create_session():
            return False
        
        # First message
        print("\nStep 2: Sending first message...")
        payload1 = {
            "parts": [{"type": "text", "text": "My favorite color is blue."}],
            "stream": False
        }
        
        try:
            response1 = requests.post(
                f"{self.base_url}/session/{self.session_id}/message",
                headers=self.headers,
                json=payload1,
                timeout=20
            )
            
            if response1.status_code == 200:
                data1 = response1.json()
                msg1 = data1.get("response", data1.get("message", ""))
                print(f"Response 1: {msg1[:100]}...")
            else:
                print(f"✗ First message failed: {response1.text}")
                return False
            
            # Second message (tests context retention)
            print("\nStep 3: Sending follow-up message...")
            payload2 = {
                "parts": [{"type": "text", "text": "What color did I just say I like?"}],
                "stream": False
            }
            
            response2 = requests.post(
                f"{self.base_url}/session/{self.session_id}/message",
                headers=self.headers,
                json=payload2,
                timeout=20
            )
            
            if response2.status_code == 200:
                data2 = response2.json()
                msg2 = data2.get("response", data2.get("message", ""))
                print(f"\n--- Context Test Response ---")
                print(msg2)
                print("---" * 20)
                
                # Check if "blue" is mentioned
                if "blue" in msg2.lower():
                    print("\n✓ Context retained successfully!")
                    return True
                else:
                    print("\n⚠️  Context may not have been retained (no mention of 'blue')")
                    return False
            else:
                print(f"✗ Second message failed: {response2.text}")
                return False
                
        except Exception as e:
            print(f"✗ Error during conversation: {e}")
            return False
    
    def run_all_tests(self):
        """Run all tests in sequence"""
        print("=" * 80)
        print("  OpenCode Server API Test Suite")
        print(f"  Base URL: {self.base_url}")
        print("=" * 80)
        
        start_time = time.time()
        results = {}
        
        # Test 1: Server reachable
        results["server_reachable"] = self.test_server_reachable()
        if not results["server_reachable"]:
            print("\n✗ Server is not accessible. Stopping tests.")
            return results
        
        # Test 2: Get providers
        providers_data = self.test_get_providers()
        results["get_providers"] = bool(providers_data)
        
        # Test 3: Create session
        session_id = self.test_create_session()
        results["create_session"] = bool(session_id)
        
        if not session_id:
            print("\n⚠️  Cannot create session. Skipping message tests.")
            return results
        
        # Test 4: Non-streaming message
        results["message_non_streaming"] = self.test_send_message_non_streaming()
        
        # Test 5: Streaming message
        results["message_streaming"] = self.test_send_message_streaming()
        
        # Test 6: Conversation flow
        results["conversation_flow"] = self.test_conversation_flow()
        
        # Summary
        elapsed = time.time() - start_time
        self.print_section("Test Summary")
        
        passed = sum(1 for v in results.values() if v is True)
        failed = sum(1 for v in results.values() if v is False)
        skipped = sum(1 for v in results.values() if v is None)
        
        print(f"Total tests: {len(results)}")
        print(f"✓ Passed: {passed}")
        print(f"✗ Failed: {failed}")
        print(f"⊘ Skipped: {skipped}")
        print(f"Time elapsed: {elapsed:.2f}s")
        
        print("\nDetailed Results:")
        for test_name, result in results.items():
            status = "✓ PASS" if result is True else ("✗ FAIL" if result is False else "⊘ SKIP")
            print(f"  {test_name:25s} {status}")
        
        return results


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Test OpenCode server API")
    parser.add_argument("--url", default="http://localhost:4096", 
                       help="Base URL of OpenCode server (default: http://localhost:4096)")
    parser.add_argument("--test", 
                       choices=["all", "server", "providers", "session", "message", "stream", "conversation"],
                       default="all", 
                       help="Specific test to run")
    parser.add_argument("--message", default="Hello! How are you?",
                       help="Custom message to send (for message/stream tests)")
    
    args = parser.parse_args()
    
    tester = OpenCodeAPITester(base_url=args.url)
    
    if args.test == "all":
        tester.run_all_tests()
    elif args.test == "server":
        tester.test_server_reachable()
    elif args.test == "providers":
        tester.test_get_providers()
    elif args.test == "session":
        tester.test_create_session()
    elif args.test == "message":
        tester.test_send_message_non_streaming(args.message)
    elif args.test == "stream":
        tester.test_send_message_streaming(args.message)
    elif args.test == "conversation":
        tester.test_conversation_flow()


if __name__ == "__main__":
    main()
