#!/usr/bin/env python3
"""
Test script for LLM Rotation Proxy
Verifies the proxy is working correctly
"""

import requests
import json
import sys


def test_health_check():
    """Test health check endpoint"""
    print("Testing health check...")
    try:
        response = requests.get("http://localhost:8000/health")
        if response.status_code == 200:
            print("✓ Health check passed")
            print(f"  Response: {response.json()}")
            return True
        else:
            print(f"✗ Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Health check failed: {e}")
        return False


def test_status():
    """Test status endpoint"""
    print("\nTesting status endpoint...")
    try:
        response = requests.get("http://localhost:8000/status")
        if response.status_code == 200:
            data = response.json()
            print("✓ Status endpoint working")
            print(f"  Total providers: {data.get('total_providers')}")
            print(f"  Available providers: {data.get('available_providers')}")

            # Show provider details
            for provider in data.get('providers', []):
                name = provider.get('name')
                priority = provider.get('priority')
                limited = provider.get('is_rate_limited')
                requests_count = provider.get('request_count')
                print(f"    - {name} (priority {priority}): {requests_count} requests, rate_limited={limited}")

            return True
        else:
            print(f"✗ Status check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Status check failed: {e}")
        return False


def test_chat_completion():
    """Test chat completion endpoint"""
    print("\nTesting chat completion...")

    payload = {
        "model": "default",
        "messages": [
            {"role": "user", "content": "Say 'test successful' and nothing else"}
        ],
        "max_tokens": 10
    }

    try:
        response = requests.post(
            "http://localhost:8000/v1/chat/completions",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=30
        )

        if response.status_code == 200:
            data = response.json()
            provider = response.headers.get('X-Provider', 'unknown')
            model = response.headers.get('X-Model', 'unknown')

            print(f"✓ Chat completion successful")
            print(f"  Provider: {provider}")
            print(f"  Model: {model}")

            if 'choices' in data and len(data['choices']) > 0:
                message = data['choices'][0].get('message', {}).get('content', '')
                print(f"  Response: {message[:100]}")

            return True
        elif response.status_code == 503:
            print(f"✗ All providers unavailable or rate limited")
            print(f"  Response: {response.json()}")
            return False
        else:
            print(f"✗ Chat completion failed: {response.status_code}")
            print(f"  Response: {response.text[:200]}")
            return False

    except Exception as e:
        print(f"✗ Chat completion failed: {e}")
        return False


def main():
    print("=" * 50)
    print("LLM Rotation Proxy Test Suite")
    print("=" * 50)

    results = []

    # Run tests
    results.append(("Health Check", test_health_check()))
    results.append(("Status Endpoint", test_status()))
    results.append(("Chat Completion", test_chat_completion()))

    # Print summary
    print("\n" + "=" * 50)
    print("Test Summary")
    print("=" * 50)

    passed = 0
    for test_name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status} - {test_name}")
        if result:
            passed += 1

    print(f"\nPassed: {passed}/{len(results)}")

    # Exit with appropriate code
    if passed == len(results):
        print("\n✓ All tests passed!")
        sys.exit(0)
    else:
        print(f"\n✗ {len(results) - passed} test(s) failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
