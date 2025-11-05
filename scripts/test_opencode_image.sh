#!/bin/bash

# Test OpenCode image message API
# This script tests if OpenCode can properly handle image messages

set -e

OPENCODE_URL="http://127.0.0.1:4096"
IMAGE_PATH="/Users/mac/01-CodeLab/02-github-repo/Osaurus-bison/assets/Screenshot 2025-11-04 at 05.56.24.png"

echo "======================================"
echo "OpenCode Image Message API Test"
echo "======================================"
echo ""

# Step 1: Create a session
echo "📝 Step 1: Creating session..."
SESSION_RESPONSE=$(curl -s -X POST "$OPENCODE_URL/session" \
  -H "Content-Type: application/json" \
  -d '{}')

SESSION_ID=$(echo "$SESSION_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$SESSION_ID" ]; then
    echo "❌ Failed to create session"
    echo "Response: $SESSION_RESPONSE"
    exit 1
fi

echo "✅ Session created: $SESSION_ID"
echo ""

# Step 2: Encode image to base64
echo "📷 Step 2: Encoding image to base64..."
IMAGE_BASE64=$(base64 -i "$IMAGE_PATH")
IMAGE_SIZE=$(echo -n "$IMAGE_BASE64" | wc -c | tr -d ' ')
echo "✅ Image encoded: $IMAGE_SIZE bytes"
echo ""

# Step 3: Send message with image
echo "📤 Step 3: Sending message with image to OpenCode..."
MESSAGE_REQUEST=$(cat <<EOF
{
  "model": {
    "providerID": "github-copilot",
    "modelID": "claude-sonnet-4.5"
  },
  "parts": [
    {
      "type": "text",
      "text": "What's in this image? Please describe it."
    },
    {
      "type": "file",
      "mime": "image/png",
      "filename": "test-image.png",
      "url": "data:image/png;base64,$IMAGE_BASE64"
    }
  ],
  "noReply": false
}
EOF
)

echo "Request size: $(echo "$MESSAGE_REQUEST" | wc -c | tr -d ' ') bytes"
echo ""

# Send the request and save response
MESSAGE_RESPONSE=$(curl -s -X POST "$OPENCODE_URL/session/$SESSION_ID/message" \
  -H "Content-Type: application/json" \
  -d "$MESSAGE_REQUEST")

echo "📥 Response received:"
echo "$MESSAGE_RESPONSE" | jq '.' 2>/dev/null || echo "$MESSAGE_RESPONSE"
echo ""

# Extract assistant message ID
ASSISTANT_MSG_ID=$(echo "$MESSAGE_RESPONSE" | grep -o '"id":"msg_[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$ASSISTANT_MSG_ID" ]; then
    echo "❌ Failed to get assistant message ID"
    exit 1
fi

echo "✅ Assistant message created: $ASSISTANT_MSG_ID"
echo ""

# Step 4: Listen to SSE events
echo "🎧 Step 4: Listening to SSE events (10 seconds)..."
echo "Connecting to: $OPENCODE_URL/event"
echo ""

timeout 10 curl -s -N "$OPENCODE_URL/event" \
  -H "Accept: text/event-stream" | while IFS= read -r line; do
    if [[ "$line" == data:* ]]; then
        EVENT_DATA="${line#data: }"
        EVENT_TYPE=$(echo "$EVENT_DATA" | jq -r '.type' 2>/dev/null)
        
        case "$EVENT_TYPE" in
            "message.part.updated")
                PART_TYPE=$(echo "$EVENT_DATA" | jq -r '.properties.part.type' 2>/dev/null)
                PART_TEXT=$(echo "$EVENT_DATA" | jq -r '.properties.part.text' 2>/dev/null)
                PART_MSG_ID=$(echo "$EVENT_DATA" | jq -r '.properties.part.messageID' 2>/dev/null)
                
                if [ "$PART_MSG_ID" = "$ASSISTANT_MSG_ID" ]; then
                    echo "💬 [TEXT DELTA] Type: $PART_TYPE"
                    if [ "$PART_TEXT" != "null" ] && [ -n "$PART_TEXT" ]; then
                        echo "   Content: ${PART_TEXT:0:100}..."
                    else
                        echo "   ⚠️  No text content!"
                    fi
                fi
                ;;
            "message.updated")
                MSG_ID=$(echo "$EVENT_DATA" | jq -r '.properties.info.id' 2>/dev/null)
                ROLE=$(echo "$EVENT_DATA" | jq -r '.properties.info.role' 2>/dev/null)
                COMPLETED=$(echo "$EVENT_DATA" | jq -r '.properties.info.time.completed' 2>/dev/null)
                
                if [ "$MSG_ID" = "$ASSISTANT_MSG_ID" ]; then
                    echo "📊 [MESSAGE UPDATE] Role: $ROLE, Completed: $COMPLETED"
                fi
                ;;
            "session.idle")
                echo "💤 [SESSION IDLE] Generation complete"
                break
                ;;
            *)
                echo "🔔 [EVENT] Type: $EVENT_TYPE"
                ;;
        esac
    fi
done

echo ""
echo "======================================"
echo "Test Complete"
echo "======================================"
