#!/usr/bin/env python3
"""Test script for OpenRouter API"""
import requests
import os
from dotenv import load_dotenv

load_dotenv()

def test_openrouter():
    """Test OpenRouter API directly"""
    api_key = os.getenv("OPENROUTER_API")

    if not api_key:
        print("❌ OPENROUTER_API not found in .env")
        return False

    print("Testing OpenRouter API...")
    print(f"API Key: {api_key[:10]}...")

    payload = {
        "model": "minimax/minimax-m2:free",
        "messages": [
            {"role": "user", "content": "Say 'test successful' and nothing else"}
        ],
        "max_tokens": 10
    }

    try:
        response = requests.post(
            "https://openrouter.ai/api/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            },
            json=payload,
            timeout=30
        )

        print(f"Status Code: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            message = data['choices'][0]['message']['content']
            print(f"✅ Success: {message}")
            return True
        else:
            print(f"❌ Failed: {response.text}")
            return False

    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    success = test_openrouter()
    exit(0 if success else 1)
