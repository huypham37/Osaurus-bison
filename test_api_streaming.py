#!/usr/bin/env python3
"""
Test script to diagnose streaming output issues from Osaurus API.
Tests both streaming and non-streaming responses to identify where spacing/formatting breaks.
"""

import requests
import json
import sys

# Configuration
BASE_URL = "http://localhost:4096"
MODEL = "github-copilot:claude-sonnet-4.5"

def test_non_streaming():
    """Test non-streaming API call to see raw model output"""
    print("=" * 80)
    print("TEST 1: Non-Streaming Response")
    print("=" * 80)
    
    payload = {
        "model": MODEL,
        "messages": [
            {
                "role": "user",
                "content": "Explain the birthday attack in cryptography briefly."
            }
        ],
        "stream": False,
        "temperature": 0.7,
        "max_tokens": 500
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/chat/completions",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=60
        )
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            
            print("\n--- Raw Response JSON ---")
            print(json.dumps(data, indent=2))
            
            print("\n--- Rendered Content ---")
            print(content)
            
            print("\n--- Character Analysis (first 200 chars) ---")
            print(repr(content[:200]))
            
            # Check for spacing issues
            if "birthday" in content.lower() and "attack" in content.lower():
                if "birthdayattack" in content.lower().replace(" ", "").replace("\n", ""):
                    print("\n⚠️  WARNING: Found 'birthday' and 'attack' without proper spacing!")
                else:
                    print("\n✓ Spacing appears normal between words")
        else:
            print(f"Error: {response.text}")
            
    except Exception as e:
        print(f"Error during non-streaming test: {e}")
        import traceback
        traceback.print_exc()


def test_streaming():
    """Test streaming API call to see if chunks are malformed"""
    print("\n" + "=" * 80)
    print("TEST 2: Streaming Response")
    print("=" * 80)
    
    payload = {
        "model": MODEL,
        "messages": [
            {
                "role": "user",
                "content": "Explain the birthday attack in cryptography briefly."
            }
        ],
        "stream": True,
        "temperature": 0.7,
        "max_tokens": 500
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/chat/completions",
            headers={"Content-Type": "application/json"},
            json=payload,
            stream=True,
            timeout=60
        )
        
        print(f"Status Code: {response.status_code}")
        print("\n--- Streaming Chunks (raw) ---")
        
        full_content = ""
        chunk_count = 0
        
        for line in response.iter_lines():
            if line:
                line_str = line.decode('utf-8')
                
                # Skip empty lines or data: prefix
                if line_str.startswith("data: "):
                    line_str = line_str[6:]  # Remove "data: " prefix
                
                if line_str.strip() == "[DONE]":
                    print("\n[DONE] marker received")
                    break
                
                try:
                    chunk_data = json.loads(line_str)
                    delta = chunk_data.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    
                    if content:
                        chunk_count += 1
                        full_content += content
                        
                        # Print chunk info
                        print(f"\nChunk #{chunk_count}:")
                        print(f"  Raw: {repr(content)}")
                        print(f"  Length: {len(content)}")
                        print(f"  Rendered: '{content}'")
                        
                except json.JSONDecodeError as e:
                    print(f"Failed to parse chunk: {line_str[:100]}")
                    continue
        
        print("\n--- Full Streamed Content ---")
        print(full_content)
        
        print("\n--- Character Analysis ---")
        print(repr(full_content[:200]))
        
        # Check for spacing issues
        if "birthday" in full_content.lower() and "attack" in full_content.lower():
            if "birthdayattack" in full_content.lower().replace(" ", "").replace("\n", ""):
                print("\n⚠️  WARNING: Found 'birthday' and 'attack' close together!")
                
                # Find the exact location
                lower_content = full_content.lower()
                idx = lower_content.find("birthday")
                if idx != -1:
                    snippet = full_content[max(0, idx-10):idx+30]
                    print(f"Context: {repr(snippet)}")
            else:
                print("\n✓ Spacing appears normal between words")
                
    except Exception as e:
        print(f"Error during streaming test: {e}")
        import traceback
        traceback.print_exc()


def test_token_boundaries():
    """Test if token boundaries are causing word concatenation"""
    print("\n" + "=" * 80)
    print("TEST 3: Token Boundary Analysis")
    print("=" * 80)
    
    test_phrases = [
        "Birthday attack is a cryptographic attack.",
        "Hash collisions occur when different inputs produce the same output.",
        "In SecurityAttacks exploiting birthday bounds can break systems."
    ]
    
    for phrase in test_phrases:
        print(f"\n--- Testing phrase: '{phrase}' ---")
        
        payload = {
            "model": MODEL,
            "messages": [
                {
                    "role": "user",
                    "content": f"Repeat this exactly: {phrase}"
                }
            ],
            "stream": True,
            "temperature": 0.0,  # Deterministic
            "max_tokens": 100
        }
        
        try:
            response = requests.post(
                f"{BASE_URL}/chat/completions",
                headers={"Content-Type": "application/json"},
                json=payload,
                stream=True,
                timeout=30
            )
            
            result = ""
            for line in response.iter_lines():
                if line:
                    line_str = line.decode('utf-8')
                    if line_str.startswith("data: "):
                        line_str = line_str[6:]
                    
                    if line_str.strip() == "[DONE]":
                        break
                    
                    try:
                        chunk_data = json.loads(line_str)
                        delta = chunk_data.get("choices", [{}])[0].get("delta", {})
                        content = delta.get("content", "")
                        result += content
                    except:
                        pass
            
            print(f"Result: '{result}'")
            print(f"Match: {phrase.lower() in result.lower()}")
            
        except Exception as e:
            print(f"Error: {e}")


if __name__ == "__main__":
    print("Osaurus API Streaming Diagnostic Tool")
    print("=" * 80)
    print(f"Testing against: {BASE_URL}")
    print(f"Model: {MODEL}")
    print()
    
    # Check if server is running
    try:
        response = requests.get(f"{BASE_URL}/", timeout=5)
        print(f"✓ Server is responding (health check: {response.status_code})")
    except:
        print("✗ Cannot connect to server. Is Osaurus running?")
        sys.exit(1)
    
    print()
    
    # Run tests
    test_non_streaming()
    test_streaming()
    test_token_boundaries()
    
    print("\n" + "=" * 80)
    print("Diagnostic Complete")
    print("=" * 80)
