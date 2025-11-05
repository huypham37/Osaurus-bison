# Desktop Window Implementation - Testing Guide

## ✅ What Changed

### **Main Window (After Expand)** - Now looks like Claude Desktop/VS Code:
- ✅ **Visible titlebar** with "Osaurus Chat" title
- ✅ **Standard window controls** (🔴🟡🟢 traffic lights)
- ✅ **Solid background** (not transparent/glass)
- ✅ **Unified toolbar style** (modern macOS app look)
- ✅ **Standard window behavior** (appears in Mission Control, Cmd+Tab)
- ✅ **Can be minimized** to Dock

### **Floating Panel (Cmd+;)** - Keeps glass effect:
- ✅ **Glass/transparent effect** preserved
- ✅ **Floats above other windows**
- ✅ **Quick access** design
- ✅ **Auto-closes** after 2 minutes

---

## 🧪 Quick Test Steps

### **Test 1: Floating Panel (Glass Style)**
1. Press `Cmd+;` (Command + Semicolon)
2. **Expected:** Floating panel appears with glass/transparent effect
3. **Check:** Window floats above other apps
4. Type a message: "Testing glass panel"
5. **Expected:** Glass background visible

### **Test 2: Expand to Desktop Window**
1. With floating panel open, send a message
2. Click the **"Expand"** button (blue capsule, top-right)
3. **Expected Results:**
   - ✅ Floating panel closes
   - ✅ New window opens with **visible titlebar**
   - ✅ Title shows "Osaurus Chat"
   - ✅ Traffic light buttons visible (🔴🟡🟢)
   - ✅ **Solid background** (not transparent)
   - ✅ Conversation preserved from panel
   - ✅ Window has standard macOS appearance

### **Test 3: Desktop Window Features**
1. With main window open:
   - **Minimize:** Click yellow button (🟡) → goes to Dock
   - **Resize:** Drag window corners → resizes smoothly
   - **Move:** Drag titlebar → moves window
   - **Mission Control:** Swipe up with 3 fingers → window appears
   - **Cmd+Tab:** Press Cmd+Tab → osaurus appears in app switcher
   - **Close:** Click red button (🔴) → window closes

### **Test 4: Window Persistence**
1. Resize main window to custom size (e.g., 1000x700)
2. Move window to different position
3. Close window
4. Reopen via menu bar → "Chat"
5. **Expected:** Window reopens at same size and position

### **Test 5: Multiple Windows**
1. Open floating panel (`Cmd+;`)
2. Send a message and expand to main window
3. Open another floating panel (`Cmd+;`)
4. **Expected:** Only ONE main window, new floating panel appears

---

## 🎨 Visual Comparison

### **Before (Both were glass/transparent):**
```
Floating Panel:          Main Window:
┌─────────────┐         ┌─────────────┐
│ (glass)     │         │ (glass)     │  ❌ Looked the same!
└─────────────┘         └─────────────┘
```

### **After (Proper distinction):**
```
Floating Panel:          Main Window:
┌─────────────┐         ┌─────────────────────────────┐
│ (glass)     │         │ 🔴🟡🟢 Osaurus Chat          │  ✅ Real desktop app!
└─────────────┘         ├─────────────────────────────┤
                        │ Solid background             │
                        │ Standard window              │
                        └─────────────────────────────┘
```

---

## 🔍 Files Changed

### **1. `osaurus/Core/AppDelegate.swift`** (lines 518-526)
**Changes:**
- `titleVisibility = .visible` (was `.hidden`)
- `titlebarAppearsTransparent = false` (was `true`)
- `isOpaque = true` (was `false`)
- `backgroundColor = NSColor.windowBackgroundColor` (was `.clear`)
- Added unified toolbar for modern look

### **2. `osaurus/Views/ChatView.swift`** (lines 178-181)
**Changes:**
- Conditional background: Glass for floating panel, solid for main window
- Uses `displayMode` to determine styling

---

## 📊 Success Criteria

**Pass if:**
- ✅ Floating panel has glass effect
- ✅ Main window has solid titlebar with traffic lights
- ✅ Main window has solid background (not transparent)
- ✅ Main window appears in Mission Control
- ✅ Main window appears in Cmd+Tab switcher
- ✅ Main window can be minimized to Dock
- ✅ Conversation transfers correctly on expand
- ✅ Window size/position persists

**Fail if:**
- ❌ Both windows look the same (glass effect)
- ❌ Main window has no titlebar
- ❌ Main window is transparent
- ❌ Main window doesn't appear in Mission Control
- ❌ Conversation lost during expansion

---

## 🐛 Troubleshooting

### **Issue: Main window still looks transparent**
- Check if dark mode is enabled (might affect appearance)
- Verify build succeeded with new changes
- Try clean build: `xcodebuild clean build`

### **Issue: Traffic lights not visible**
- Check `titleVisibility = .visible` is set
- Verify `titlebarAppearsTransparent = false`

### **Issue: Window not in Mission Control**
- Check app activation policy (should be `.accessory`)
- Main window should have standard `collectionBehavior`

---

## 🎯 Next Steps

After testing passes:
1. ✅ Update KANBAN.md (mark implementation complete)
2. ✅ Commit changes with descriptive message
3. ✅ Update main TEST_PLAN.md
4. Consider: Add preferences to customize window appearance
5. Consider: Add dark mode support for main window

---

**Current Status:** 🚀 Ready for Testing

**Test Date:** _______________  
**Tester:** _______________  
**Result:** ⬜️ Pass | ⬜️ Fail
