#!/usr/bin/env python3
"""Test script for DeepSeek API"""
import os
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

def test_deepseek():
    """Test DeepSeek API using OpenAI SDK"""
    api_key = os.getenv("DEEPSEEK_API")

    if not api_key:
        print("❌ DEEPSEEK_API not found in .env")
        return False

    print("Testing DeepSeek API...")
    print(f"API Key: {api_key[:10]}...")

    try:
        client = OpenAI(api_key=api_key, base_url="https://api.deepseek.com")

        response = client.chat.completions.create(
            model="deepseek-chat",
            messages=[
                {"role": "system", "content": "You are a helpful assistant"},
                {"role": "user", "content": "Say 'test successful' and nothing else"},
            ],
            stream=False
        )

        message = response.choices[0].message.content
        print(f"✅ Success: {message}")
        return True

    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    success = test_deepseek()
    exit(0 if success else 1)
