# macOS Spaces Detection Research

## Overview

This document contains research findings on how to reliably detect and monitor macOS Spaces changes, based on investigation of the open-source Spaceman project and comparison with ZoneTilerWM's current implementation.

**Last Updated**: 2025-12-05

---

## Current Problem in ZoneTilerWM

### Issues Identified

1. **Space Watcher Always Returns -1**
   - `hs.spaces.watcher` consistently receives `-1` instead of actual space ID
   - Indicates the watcher fires before macOS completes the space switch
   - `hs.spaces.focusedSpace()` also returns -1 during transitions

2. **Polling After Delay Still Unreliable**
   - Even with progressive retry polling (50ms, 100ms, 150ms, etc.)
   - `get_current_space()` returns the OLD space ID, not the new one
   - Can take 200-500ms for macOS to report the correct space

3. **Multiple Watcher Events**
   - Single space switch triggers multiple watcher callbacks
   - Creates many concurrent polling timers
   - Causes excessive logging and performance overhead

---

## How Spaceman Solves It

### Repository

- **URL**: <https://github.com/ruittenb/Spaceman>
- **License**: MIT
- **Language**: Swift (native macOS app)

### 1. Space Change Detection

**Spaceman does NOT use `hs.spaces.watcher`**

Instead, it uses native macOS notifications:

```swift
// From: /Spaceman/Helpers/SpaceObserver.swift (lines 20-30)
init() {
    workspace.notificationCenter.addObserver(
        self,
        selector: #selector(updateSpaceInformation),
        name: NSWorkspace.activeSpaceDidChangeNotification,
        object: workspace)
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(updateSpaceInformation),
        name: NSNotification.Name("ButtonPressed"),
        object: nil)
}
```

**Key Points**:

- Uses **`NSWorkspace.activeSpaceDidChangeNotification`** - native macOS notification
- More reliable than Hammerspoon's wrapper
- Updates run on background queue (`workerQueue`) to avoid blocking

### 2. Getting Current Space ID

**Uses private Core Graphics Server (CGS) APIs directly:**

```swift
// From: /Spaceman/Helpers/SpaceObserver.swift
private let conn = _CGSDefaultConnection()

private func fetchDisplaySpaces() -> [NSDictionary]? {
    guard let rawDisplays = CGSCopyManagedDisplaySpaces(conn)?.takeRetainedValue() as? [NSDictionary] else {
        return nil
    }
    return rawDisplays
}

// Extract current space ID
let currentSpaceID = currentSpaces["ManagedSpaceID"] as? Int ?? -1
```

**Key CGS APIs Used**:

- **`_CGSDefaultConnection()`** - Gets Core Graphics connection
- **`CGSCopyManagedDisplaySpaces(conn)`** - Returns array of display/space dictionaries
- Each display dict contains:
  - `"Current Space"` - Dictionary with active space info
  - `"Spaces"` - Array of all spaces for that display
  - `"Display Identifier"` - UUID of the display
  - `"ManagedSpaceID"` - Integer space ID

### 3. Handling Invalid Space IDs

**Defensive programming with -1 checks:**

```swift
var activeSpaceID = -1

// ...later in loop...
let currentSpaceID = currentSpaces["ManagedSpaceID"] as? Int ?? -1
if currentSpaceID != -1 && activeSpaceID == -1 {
    activeSpaceID = currentSpaceID
}

for spaceDict in spaces {
    guard let managedInt = spaceDict["ManagedSpaceID"] as? Int else { continue }
    let managedSpaceID = String(managedInt)
    guard let spaceNumber = spaceNumberMap[managedSpaceID] else { continue }

    let isCurrentSpace = currentSpaceID == managedInt
    // ... process space
}
```

**Workarounds**:

1. Default to -1 when ManagedSpaceID is missing
2. Only set activeSpaceID once (prevent overwriting valid IDs)
3. Guard statements to skip invalid spaces
4. **Position-based fallback** when space IDs change (e.g., after reboot):

```swift
var savedInfo = updatedNames[managedSpaceID]
if savedInfo == nil {
    // ManagedSpaceID may have changed (e.g., after reboot)
    // Try to find by display + position
    if let matchedInfo = findSpaceByPosition(
        in: updatedNames,
        displayID: displayID,
        position: positionOnThisDisplay) {
        savedInfo = matchedInfo
    }
}
```

### 4. Complete Monitoring Workflow

```
1. Initialize SpaceObserver
   ↓
2. Register for NSWorkspace.activeSpaceDidChangeNotification
   ↓
3. When notification fires → updateSpaceInformation()
   ↓
4. Dispatch to background queue (workerQueue)
   ↓
5. performSpaceInformationUpdate()
   ↓
6. fetchDisplaySpaces() using CGSCopyManagedDisplaySpaces()
   ↓
7. Sort displays by user preference
   ↓
8. Build space number map
   ↓
9. Iterate through each display's spaces
   ↓
10. Create Space objects with resolved names
   ↓
11. Notify delegate on main thread
```

---

## Alternative Approach: alt-tab-macos

**Repository**: <https://github.com/lwouis/alt-tab-macos>

**More modern CGS API usage:**

```swift
// From: /src/logic/Spaces.swift
if let mainScreen = NSScreen.main,
   let uuid = mainScreen.uuid() {
    currentSpaceId = CGSManagedDisplayGetCurrentSpace(CGS_CONNECTION, uuid)
}
```

**CGS API Declarations** (from `/src/api-wrappers/private-apis/SkyLight.framework.swift`):

```swift
typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: CGSConnectionID, _ displayUuid: ScreenUuid) -> CGSSpaceID

let CGS_CONNECTION = CGSMainConnectionID()
```

The `@_silgen_name` attribute tells Swift to look for these C symbols at link time.

---

## Key Differences: Hammerspoon vs Native

| Feature | Hammerspoon (`hs.spaces`) | Spaceman (Native) |
|---------|---------------------------|-------------------|
| **Space Change Detection** | `hs.spaces.watcher` (unreliable) | `NSWorkspace.activeSpaceDidChangeNotification` |
| **Get Current Space** | `hs.spaces.focusedSpace()` (returns -1) | `CGSCopyManagedDisplaySpaces()` direct |
| **Space ID Reliability** | Often returns -1 during transitions | Returns actual ManagedSpaceID |
| **Timing** | Fires before space switch completes | Fires after space switch completes |
| **Background Processing** | No built-in async support | Uses `DispatchQueue` |
| **Fallback Handling** | None | Position-based fallback for ID changes |

---

## Recommendations for ZoneTilerWM

### Short-term Fixes (Hammerspoon-based)

1. **Increase polling delay and retries**
   - Current: 100ms, 200ms, 300ms... (15 attempts)
   - Try: 200ms, 400ms, 600ms... (20 attempts)
   - macOS needs ~500ms to fully complete space switch

2. **Debounce watcher events more aggressively**
   - Current: 2-second debounce window
   - Try: Only allow one poll per space switch
   - Track last successful space ID, ignore redundant events

3. **Force callback on initialization**
   - Even if space didn't change, update menubar
   - Ensures UI reflects current state

### Long-term Solutions

1. **Explore Hammerspoon's lower-level APIs**
   - Check if `hs._asm.undocumented.spaces` exists
   - May provide direct access to CGS APIs
   - Could bypass unreliable watcher

2. **Native Extension**
   - Write Swift extension using `NSWorkspace` notifications
   - Bridge to Hammerspoon via IPC or shared file
   - Most reliable but adds complexity

3. **Alternative Detection**
   - Poll `hs.spaces.focusedSpace()` on a timer
   - Compare with last known space
   - Less efficient but avoids watcher entirely

---

## Resources

### CGS API Documentation

- [CGSInternal Header Files](https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h)
- [Hammerspoon Undocumented Spaces](https://github.com/asmagill/hs._asm.undocumented.spaces/blob/master/CGSSpace.h)

### Related Projects

- [Spaceman (ruittenb)](https://github.com/ruittenb/Spaceman) - MIT License
- [alt-tab-macos](https://github.com/lwouis/alt-tab-macos) - GPL-3.0
- [yabai](https://github.com/koekeishiya/yabai) - Window manager with Spaces support

### Hammerspoon Documentation

- [hs.spaces](https://www.hammerspoon.org/docs/hs.spaces.html) - Official Spaces API
- [hs.spaces.watcher](https://www.hammerspoon.org/docs/hs.spaces.watcher.html) - Space change notifications

---

## Current Implementation Status

### What's Implemented

- Progressive retry polling with exponential backoff
- Debouncing to prevent multiple concurrent polls
- Enhanced logging for diagnosis
- Menubar bracket update on space change
- Timer-based hover detection for preview

### What's Not Working

- Watcher still receives -1 consistently
- Polling often times out (space ID doesn't change within 1.5s)
- Menubar brackets don't update reliably
- Need more aggressive debouncing or alternative approach

### Next Steps

1. Try longer polling delays (200ms increments instead of 100ms)
2. Investigate Hammerspoon undocumented APIs for direct CGS access
3. Consider timer-based polling as fallback (check space every 500ms)
4. Document findings and propose native extension if Hammerspoon approach fails

---

## Appendix: Hammerspoon Spaces API

### Available Functions

```lua
hs.spaces.focusedSpace()          -- Returns current space ID (or -1)
hs.spaces.allSpaces()             -- Returns table of all spaces by screen
hs.spaces.gotoSpace(spaceId)      -- Switch to specific space
hs.spaces.windowsForSpace(spaceId) -- Get windows in a space
hs.spaces.spaceType(spaceId)      -- Returns space type (user/fullscreen)
```

### Space Watcher

```lua
watcher = hs.spaces.watcher.new(function(spaceId)
    -- Called when space changes
    -- Problem: spaceId is consistently -1
end)
watcher:start()
```

### Known Issues

- `focusedSpace()` returns -1 during space transitions
- Watcher callback receives -1 instead of actual space ID
- No reliable way to know when space switch is complete
- Timing varies by system (200-500ms typical)
