# OpenCode API Spacing Diagnosis - Results

**Date:** November 5, 2025  
**Issue:** Words concatenating without spaces in Osaurus UI  
**Test:** OpenCode streaming API analysis

---

## 🎯 KEY FINDING

**✅ THE API IS CORRECT** - OpenCode returns properly spaced text  
**❌ THE BUG IS IN OSAURUS** - Client-side parsing/display issue

---

## Test Results

### 1. Non-Streaming Test
```bash
python3 test_opencode_server.py --test message --message "Explain hash collision..."
```

**Result:** ✅ SUCCESS
- Response includes: `"Hash Collision occurs when two different inputs..."`
- Spacing is **CORRECT** between all words

### 2. Streaming Test  
```bash
python3 test_opencode_streaming.py
```

**Result:** ✅ SUCCESS - Spaces present in SSE chunks

**Example SSE Events:**
```json
{
  "type": "message.part.updated",
  "properties": {
    "delta": " Collision occurs when..."
             ↑ SPACE HERE!
  }
}
```

**Chunk Sequence:**
```
Chunk 1: "Hash"
Chunk 2: " Collision occurs when two different inputs produce the same hash"
          ↑ Leading space present!
Chunk 3: " output. In cryptography, this is a critical"
          ↑ Leading space present!
```

---

## 📊 Evidence: API Returns Spaces

### From SSE Stream:
```json
{
  "delta": "Hash"
}
{
  "delta": " Collision occurs when two different inputs produce the same hash"
}
{  
  "delta": " output. In cryptography, this is a critical"
}
{
  "delta": " concern because hash functions are designed to be one-way an"
}
```

**Every chunk after the first has a leading space!**

---

## 🔍 Where to Look in Osaurus

### 1. `OpenCodeProxyService.swift` (~line 450-550)
**Method:** `listenToEvents(sessionID:continuation:)`

**Check for:**
```swift
// ❌ BAD - stripping spaces:
let delta = eventData["delta"] as? String
continuation.yield(delta.trimmingCharacters(in: .whitespaces))

// ❌ BAD - filtering spaces:
let delta = eventData["delta"] as? String
continuation.yield(delta.filter { !$0.isWhitespace })

// ✅ GOOD - preserve spaces:
let delta = eventData["delta"] as? String
continuation.yield(delta)
```

### 2. `ChatView.swift` or message display code

**Check for:**
- String concatenation that strips whitespace
- Markdown parsing that collapses spaces
- AttributedString formatting issues
- Font rendering issues with monospace/proportional fonts

### 3. Common Issues

```swift
// ❌ This might remove spaces:
Text(message.content.replacingOccurrences(of: " ", with: ""))

// ❌ This might collapse whitespace:
Text(message.content.components(separatedBy: .whitespaces).joined())

// ❌ This removes leading/trailing spaces from each chunk:
continuation.yield(chunk.trimmingCharacters(in: .whitespaces))
```

---

## 🧪 How to Verify Fix

1. Run Osaurus with OpenCode backend
2. Send message: "Explain hash collision. Use 'Hash Collision' at start."
3. Watch streaming response
4. Verify "Hash Collision" appears with space, not "HashCollision"

---

## 📁 Test Files Created

- `test_opencode_streaming.py` - SSE streaming test
- `spacing_diagnosis.txt` - Detailed technical report
- `SPACING_BUG_DIAGNOSIS.md` - This summary (you are here)

---

## 🏁 Conclusion

**The OpenCode API is working correctly.** Both streaming and non-streaming responses contain proper spacing between words. The text concatenation bug is occurring somewhere in the Osaurus client code between:

1. Receiving the SSE delta chunks from `/event` endpoint
2. Displaying the text in the UI

Focus debugging efforts on `OpenCodeProxyService.swift` (SSE parsing) and the chat message display components.
