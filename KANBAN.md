# Osaurus Project KANBAN

## 📋 Backlog

### Feature: Add Dedicated Window Option for AI Chat
**Priority:** Medium  
**Type:** Enhancement

**Description:**  
Currently, Osaurus provides an AI chat interface through a floating overlay panel (NSPanel) that appears on hotkey activation or button click. This feature proposes adding a **dedicated window option** for the AI chat to provide users with more flexibility in how they interact with the chat interface.

**Current Behavior:**
- Chat appears as a modal overlay panel when triggered
- Activates via global hotkey or menu bar button
- Floats above all windows (NSPanel with `.modalPanel` level)
- Auto-hides when focus is lost
- Not integrated with macOS window management (Mission Control, Stage Manager, etc.)

**Proposed Feature:**
Add a **dedicated chat window mode** that:
- Functions as a standard NSWindow (not a panel)
- Persists in the dock and window switcher
- Integrates with Mission Control and Stage Manager
- Can be minimized, maximized, and managed like regular app windows
- Remains visible alongside other applications
- Provides better multitasking support

**Benefits:**
1. **Better Multitasking** - Keep chat visible while working in other apps
2. **Workspace Integration** - Works with macOS window management features
3. **Persistent Reference** - Easier to reference chat history alongside code
4. **User Flexibility** - Users can choose between overlay (quick access) or window (persistent)
5. **Natural UX** - Familiar window behavior for users who prefer traditional windows

**Implementation Considerations:**

**Option A: Replace Overlay with Window**
- Remove panel-based overlay entirely
- Use standard NSWindow for all chat interactions
- Simpler codebase, single implementation

**Option B: Offer Both Modes**
- Keep existing overlay for quick access
- Add menu option: "Open Chat in Window"
- Let users choose their preferred mode
- More complex but maximum flexibility

**Technical Notes:**
- The chat UI (`ChatView.swift`) is already well-structured and reusable
- Would need to create a new window management method in `AppDelegate.swift`
- Should respect user preference (could add to configuration)
- Window state should be persistent (size, position)

**Questions for Discussion:**
1. Should this **replace** the overlay or be offered **alongside** it?
2. Should there be a user preference to set default behavior?
3. Should the window be resizable with saved state?
4. How should window closure behave? (Hide vs. Destroy)

**Related Files:**
- `osaurus/Core/AppDelegate.swift` (lines 377-455) - Current overlay implementation
- `osaurus/Views/ChatView.swift` - Chat UI component

---

## 🚧 In Progress

### Feature: Dual-Mode Chat System (Floating Panel + Main Window)
**Status:** Ready to implement  
**Priority:** High  
**Related Issue:** #1

**Finalized Requirements:**
1. **Floating Panel (Hotkey Cmd+;):**
   - Always creates fresh/empty chat session
   - Single instance only (closes old before creating new)
   - Auto-destroys after 2 minutes of inactivity
   - Has "Expand" button when conversation exists
   - Closes automatically when expanded to main window

2. **Main Window (Menu Bar Button):**
   - Persistent single instance
   - Reuses window if already open
   - Saves/loads window size and position
   - Standard NSWindow with full window management
   - Can receive expanded conversations from panel

**Implementation Tasks:**

#### Phase 1: AppDelegate.swift Core Changes
- [ ] **Task 1.1:** Add new properties (`mainChatWindow`, `panelInactivityTimer`)
- [ ] **Task 1.2:** Modify `toggleChatOverlay()` to always create fresh panel
- [ ] **Task 1.3:** Update `showChatOverlay()` to remove reuse logic
- [ ] **Task 1.4:** Add `startPanelInactivityTimer()` method (2-minute auto-destroy)
- [ ] **Task 1.5:** Add `resetPanelInactivityTimer()` method
- [ ] **Task 1.6:** Enhance `closeChatOverlay()` to invalidate timer
- [ ] **Task 1.7:** Add `showMainChatWindow()` method for persistent window
- [ ] **Task 1.8:** Add `expandPanelToWindow()` method for conversation transfer
- [ ] **Task 1.9:** Add `loadMainWindowFrame()` for window persistence
- [ ] **Task 1.10:** Add `saveMainWindowFrame()` for window persistence
- [ ] **Task 1.11:** Update `windowWillClose()` delegate to handle main window

#### Phase 2: ChatView.swift Enhancements
- [ ] **Task 2.1:** Add `ChatDisplayMode` enum (floatingPanel, mainWindow)
- [ ] **Task 2.2:** Update `ChatSession` init to accept initial conversation
- [ ] **Task 2.3:** Update `ChatView` init to accept display mode and initial conversation
- [ ] **Task 2.4:** Add "Expand" button to header (only for floating panel mode)
- [ ] **Task 2.5:** Add activity tracking (.onChange) to reset inactivity timer
- [ ] **Task 2.6:** Add AppDelegate method stubs for timer reset

#### Phase 3: ContentView.swift Updates
- [ ] **Task 3.1:** Update chat button to call `showMainChatWindow()` instead of `showChatOverlay()`

#### Phase 4: Testing & Validation
- [ ] **Task 4.1:** Test hotkey creates fresh panel each time
- [ ] **Task 4.2:** Test single panel constraint (closes old when new opens)
- [ ] **Task 4.3:** Test 2-minute auto-destroy timer
- [ ] **Task 4.4:** Test inactivity timer resets on user activity
- [ ] **Task 4.5:** Test "Expand" button transfers conversation correctly
- [ ] **Task 4.6:** Test main window persistence (size/position)
- [ ] **Task 4.7:** Test main window reuses single instance
- [ ] **Task 4.8:** Test panel closes automatically after expansion
- [ ] **Task 4.9:** Test menu bar button opens main window
- [ ] **Task 4.10:** Test both modes can coexist independently

**Files to Modify:**
- `osaurus/Core/AppDelegate.swift` (lines 24, 377-455+)
- `osaurus/Views/ChatView.swift` (lines 14-137, 139+, 245+)
- `osaurus/Views/ContentView.swift` (line 219-221)

---

## ✅ Done

### Fix: Immediate Floating Panel Expansion Animation
**Completed:** 2025-11-02  
**Priority:** High  
**Related Issue:** Panel expansion UX improvement

**Problem:**
- Floating panel waited for AI response before expanding to main window
- Created jarring intermediate state where expanded window showed "thinking..." in awkward layout
- Users experienced delay and visual glitch during transition

**Solution Implemented:**
- Panel now expands **immediately** when user hits send (no waiting)
- User message is saved instantly, then smooth 400ms morph animation triggers
- Main window detects conversation ending with user message and auto-streams AI response
- Result: Seamless animation → main window → response appears naturally

**Technical Changes:**
- Modified `handleMinimalEntrySend()` in `ChatView.swift` to skip streaming in panel
- Added `.onAppear` logic in main window to auto-send when loaded with pending user message
- Preserved existing morph animation (panel fade-out + main window grow + cross-fade)
- Timing: 400ms animation + 100ms render delay = smooth transition

**Commits:**
- `08a74ff` - Implement immediate floating panel expansion without waiting for AI response
- `c79be52` - Fix duplicate message bug in floating panel expansion

---

## 🧊 On Hold

---

## 📝 Notes

- This KANBAN tracks features, bugs, and tasks for the Osaurus project
- Move items between columns as work progresses
- Add new items to Backlog and prioritize accordingly
