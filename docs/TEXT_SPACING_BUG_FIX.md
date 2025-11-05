# Text Spacing Bug Fix

## Problem
Words were being concatenated without spaces in the Osaurus UI when streaming responses from OpenCode API.  
Example: "Hash Collision" appeared as "HashCollision"

## Root Cause Analysis

### Investigation Results
Using `tools/test_opencode_server.py`, we confirmed that:
- ✅ OpenCode API returns **correctly spaced text**
- ✅ SSE delta chunks include leading spaces: `" Collision"`, `" occurs"`
- ❌ Bug was in **Osaurus client-side parsing**

### The Bug
**File**: `osaurus/Services/OpenCodeProxyService.swift`  
**Line**: 713 (before fix)

```swift
// BEFORE (buggy):
let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
```

This line was stripping whitespace from SSE data payloads, removing the leading spaces that separate words in streaming chunks.

**Example**:
```
SSE Event: data:  Collision occurs
           ↑ Leading space here

After .trimmingCharacters(): "Collision occurs" → "Collisionoccurs"
                             ↑ Space removed!
```

## The Fix

```swift
// AFTER (fixed):
let data = String(line.dropFirst(5))
```

Simply remove `.trimmingCharacters(in: .whitespacesAndNewlines)` from the data extraction.

### Why This Works
- SSE format: `data: <content>\n`
- After `dropFirst(5)`, we get: ` <content>` (with leading space if present)
- The leading space is **intentional** - it's part of the token/word separation
- We should preserve it, not trim it

### What We Still Trim (Correctly)
- **Line 700**: `let line = String(lineSubstring).trimmingCharacters(in: .whitespacesAndNewlines)`
  - ✅ This is correct - we trim the SSE line itself (removes trailing `\n`, etc.)
- **Line 711**: `eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)`
  - ✅ This is correct - event types don't need whitespace

## Files Changed
1. `osaurus/Services/OpenCodeProxyService.swift` - Line 713 (spacing fix)
2. `osaurus/Services/SharedConfigurationService.swift` - Line 108 (syntax fix)
3. `osaurus/Views/DirectoryPickerView.swift` - Line 110 (syntax fix)

## Testing
Run the fixed app with OpenCode server:
```bash
# Build
xcodebuild -project osaurus.xcodeproj -scheme osaurus -configuration Debug build

# Test with a prompt that reveals spacing:
# "Explain hash collision in cryptography"
# 
# Expected: "Hash Collision occurs when..."
# Before fix: "HashCollisionoccurswhen..."
# After fix: "Hash Collision occurs when..." ✅
```

## Diagnostic Tools Used
- `tools/test_opencode_server.py` - OpenCode API testing
- Streaming test confirmed API returns proper spacing
- Terminal-executor agent for automated testing

## Commit Message
```
fix: preserve whitespace in OpenCode SSE streaming responses

Remove .trimmingCharacters() from SSE data extraction to preserve
intentional leading spaces in streaming token deltas. This fixes
word concatenation bug where "Hash Collision" appeared as
"HashCollision" in the UI.

The OpenCode API correctly sends deltas with leading spaces
(e.g., " Collision"), but line 713 was stripping them during
SSE parsing, causing words to merge together.
```

---

**Status**: ✅ Fixed and built successfully  
**Date**: 2025-11-05  
**Build Result**: BUILD SUCCEEDED
