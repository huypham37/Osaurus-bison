#!/usr/bin/env python3
"""Test script for Cerebras API"""
import os
from dotenv import load_dotenv
from cerebras.cloud.sdk import Cerebras

load_dotenv()

def test_cerebras():
    """Test Cerebras API using SDK"""
    api_key = os.getenv("CEREBRAS_API_KEY")

    if not api_key:
        print("❌ CEREBRAS_API_KEY not found in .env")
        return False

    print("Testing Cerebras API...")
    print(f"API Key: {api_key[:10]}...")

    try:
        # Initialize the client
        client = Cerebras(api_key=api_key)
        print("Cerebras client initialized successfully!")

        # Simple test - completion
        response = client.chat.completions.create(
            messages=[
                {"role": "user", "content": "Say 'test successful' and nothing else"}
            ],
            model="qwen-3-235b-a22b-instruct-2507",
            max_tokens=10,
        )

        message = response.choices[0].message.content
        print(f"✅ Success: {message}")
        return True

    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    success = test_cerebras()
    exit(0 if success else 1)
