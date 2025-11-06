#!/usr/bin/env python3
"""
Test OpenCode SSE streaming to diagnose spacing issues.
This connects to both /session/:id/message and /event endpoints.
"""

import requests
import json
import sys
import threading
import time

BASE_URL = "http://localhost:4096"

def create_session():
    """Create a new OpenCode session"""
    print("=" * 80)
    print("Creating Session...")
    print("=" * 80)
    
    response = requests.post(
        f"{BASE_URL}/session",
        headers={"Content-Type": "application/json"},
        json={"provider": "copilot", "model": "gpt-4o"},
        timeout=10
    )
    
    if response.status_code == 200:
        data = response.json()
        session_id = data.get("id")
        print(f"✓ Session created: {session_id}\n")
        return session_id
    else:
        print(f"✗ Failed to create session: {response.text}")
        return None


def listen_to_events(session_id, stop_event):
    """Listen to SSE events from /event endpoint"""
    print("=" * 80)
    print("Listening to SSE Events...")
    print("=" * 80)
    
    try:
        response = requests.get(
            f"{BASE_URL}/event",
            headers={"Accept": "text/event-stream"},
            stream=True,
            timeout=60
        )
        
        if response.status_code != 200:
            print(f"✗ Failed to connect to /event: {response.status_code}")
            return
        
        print("✓ Connected to SSE stream\n")
        print("--- Streaming Events ---")
        
        event_type = ""
        event_count = 0
        text_chunks = []
        
        for line in response.iter_lines():
            if stop_event.is_set():
                break
                
            if line:
                line_str = line.decode('utf-8')
                
                if line_str.startswith("event:"):
                    event_type = line_str[6:].strip()
                    event_count += 1
                    print(f"\n[Event #{event_count}: {event_type}]")
                    
                elif line_str.startswith("data:"):
                    data_str = line_str[5:].strip()
                    
                    if data_str == "[DONE]":
                        print("\n[DONE]")
                        break
                    
                    try:
                        event_data = json.loads(data_str)
                        
                        # Check for text parts
                        if event_type == "message-part":
                            part_type = event_data.get("type", "")
                            part_text = event_data.get("text", "")
                            
                            if part_type == "text" and part_text:
                                text_chunks.append(part_text)
                                # Print with visual separator to see spacing
                                print(f"CHUNK[{len(text_chunks)}]: '{part_text}'", end="")
                                
                        # Pretty print full event data for debugging
                        print(f"\n{json.dumps(event_data, indent=2)}")
                        
                    except json.JSONDecodeError:
                        print(f"Plain text: {data_str}")
        
        print("\n" + "=" * 80)
        print(f"Total chunks received: {len(text_chunks)}")
        print("Full reconstructed text:")
        print("---")
        print("".join(text_chunks))
        print("---")
        
        # Check for spacing issues
        full_text = "".join(text_chunks)
        if "HashCollision" in full_text or "hashcollision" in full_text:
            print("\n⚠️  WARNING: Text concatenation detected!")
            print("    Words are being concatenated without spaces!")
        elif "Hash Collision" in full_text:
            print("\n✓ Spacing looks correct - 'Hash Collision' found with space")
        
    except Exception as e:
        print(f"\n✗ Error listening to events: {e}")
        import traceback
        traceback.print_exc()


def send_message(session_id):
    """Send a message to test streaming"""
    print("\n" + "=" * 80)
    print("Sending Message...")
    print("=" * 80)
    
    message = "Explain hash collision in cryptography. Use the exact phrase 'Hash Collision' at the start."
    
    payload = {
        "parts": [{"type": "text", "text": message}],
        "stream": True
    }
    
    print(f"Message: {message}")
    print(f"Payload: {json.dumps(payload, indent=2)}\n")
    
    try:
        response = requests.post(
            f"{BASE_URL}/session/{session_id}/message",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=60
        )
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            print("✓ Message sent successfully")
        else:
            print(f"✗ Failed to send message: {response.text}")
            
    except Exception as e:
        print(f"✗ Error sending message: {e}")
        import traceback
        traceback.print_exc()


def main():
    print("=" * 80)
    print("OpenCode Streaming Test - Spacing Diagnosis")
    print("=" * 80)
    
    # Create session
    session_id = create_session()
    if not session_id:
        sys.exit(1)
    
    # Set up event listener in background thread
    stop_event = threading.Event()
    event_thread = threading.Thread(
        target=listen_to_events,
        args=(session_id, stop_event),
        daemon=True
    )
    event_thread.start()
    
    # Wait a bit for event connection to establish
    time.sleep(2)
    
    # Send message
    send_message(session_id)
    
    # Wait for events to complete (max 60 seconds)
    event_thread.join(timeout=60)
    stop_event.set()
    
    print("\n" + "=" * 80)
    print("Test Complete")
    print("=" * 80)


if __name__ == "__main__":
    main()
