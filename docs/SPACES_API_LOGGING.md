# Space API Call Logging

**Date:** 2025-12-05
**Purpose:** Comprehensive logging of all hs.spaces API calls to diagnose space switching issues
**Status:** ✅ Implemented

## Problem Being Diagnosed

From the user's logs, we observed:

1. **Menubar updates correctly** (fixed by query_current_space())
2. **Watcher NEVER fires with valid space IDs** (only `-1`)
3. **macOS doesn't always switch to requested space:**
   ```
   Post-switch verification: requested 4 actual 5 stored 1
   Post-switch verification: requested 1 actual 5 stored 5
   Post-switch verification: requested 3 actual 4 stored 5
   ```

The `gotoSpace()` call reports success, but macOS ends up in a different space than requested!

## Root Cause Hypothesis

**Rapid space switching confuses macOS:**
- User presses `Ctrl+Shift+2` (go to space 3)
- `gotoSpace(3)` is called
- macOS starts animating to space 3
- User presses `Ctrl+Shift+3` (go to space 4)
- `gotoSpace(4)` is called while animation is in progress
- macOS gets confused, ends up in space 4 or 5 instead of 3

**Alternative hypothesis:**
- The space IDs we're passing to `gotoSpace()` might not be the spaces we think they are
- macOS might be renumbering spaces dynamically

## New Logging Added

### 1. API Call Tracking

Every hs.spaces API call now logs:
- `🔍 API CALL: function_name(args)`
- `🔍 API RESULT: function_name() returned result`
- `🔍 API ERROR: function_name() failed: error`

### 2. Space Mismatch Detection

After every space switch, we check if we ended up where we requested:
```lua
if actual_space and actual_space ~= space_id then
    debug_log("⚠️⚠️⚠️ SPACE MISMATCH! Requested space", space_id, "but actually at space", actual_space)
end
```

### 3. Complete API Coverage

All three main API calls are now logged:

**hs.spaces.focusedSpace():**
```
🔍 API CALL: hs.spaces.focusedSpace()
🔍 API RESULT: hs.spaces.focusedSpace() returned 3
```

**hs.spaces.allSpaces():**
```
🔍 API CALL: hs.spaces.allSpaces()
🔍 API RESULT: hs.spaces.allSpaces() returned 6 total spaces
```

**hs.spaces.gotoSpace(space_id):**
```
🔍 API CALL: hs.spaces.gotoSpace(3)
🔍 API RESULT: hs.spaces.gotoSpace() returned true (true=success)
```

## Expected Log Output

### Normal Space Switch (Works Correctly)

```
🔵 HOTKEY: Ctrl+Shift+2 pressed
🔍 API CALL: hs.spaces.allSpaces()
🔍 API RESULT: hs.spaces.allSpaces() returned 6 total spaces
Switching to Space 2 (Space ID: 3)
========== SPACE SWITCH REQUEST ==========
🔍 API CALL: hs.spaces.gotoSpace(3)
🔍 API RESULT: hs.spaces.gotoSpace() returned true (true=success)
Successfully switched to Space: 3
========== SPACE SWITCH REQUEST COMPLETE ==========
🔍 API CALL: hs.spaces.focusedSpace()
🔍 API RESULT: hs.spaces.focusedSpace() returned 3
Post-switch verification: requested 3 actual 3 stored 1
🔧 Manually updating space state
✅ Callback 1 completed successfully
```

### Space Mismatch (Bug!)

```
🔵 HOTKEY: Ctrl+Shift+4 pressed
🔍 API CALL: hs.spaces.allSpaces()
🔍 API RESULT: hs.spaces.allSpaces() returned 6 total spaces
Switching to Space 4 (Space ID: 5)
========== SPACE SWITCH REQUEST ==========
🔍 API CALL: hs.spaces.gotoSpace(5)
🔍 API RESULT: hs.spaces.gotoSpace() returned true (true=success)
Successfully switched to Space: 5
========== SPACE SWITCH REQUEST COMPLETE ==========
🔍 API CALL: hs.spaces.focusedSpace()
🔍 API RESULT: hs.spaces.focusedSpace() returned 4
⚠️⚠️⚠️ SPACE MISMATCH! Requested space 5 but actually at space 4
Post-switch verification: requested 5 actual 4 stored 1
🔧 Manually updating space state to 4
```

## What This Will Tell Us

### Question 1: Is the problem with our space ID mapping?

If we see:
```
Switching to Space 2 (Space ID: 3)
🔍 API CALL: hs.spaces.gotoSpace(3)
⚠️⚠️⚠️ SPACE MISMATCH! Requested space 3 but actually at space 4
```

Then the problem is: **Our space ID mapping is wrong**. The sorted space list doesn't match what macOS thinks.

### Question 2: Does rapid switching cause the problem?

If we see:
```
⚠️ RAPID SPACE SWITCH detected! Time since last: 0 seconds
🔍 API CALL: hs.spaces.gotoSpace(3)
[300ms later]
⚠️⚠️⚠️ SPACE MISMATCH! Requested space 3 but actually at space 5
```

Then the problem is: **Rapid switching confuses macOS**. We need stronger throttling or better handling.

### Question 3: Is allSpaces() returning inconsistent data?

If we see:
```
🔍 API RESULT: hs.spaces.allSpaces() returned 6 total spaces
[switch happens]
🔍 API RESULT: hs.spaces.allSpaces() returned 8 total spaces
```

Then the problem is: **macOS is changing space configuration dynamically** (fullscreen apps create temporary spaces).

### Question 4: Does gotoSpace() lie about success?

If we see:
```
🔍 API CALL: hs.spaces.gotoSpace(3)
🔍 API RESULT: hs.spaces.gotoSpace() returned true (true=success)
[but focusedSpace() still returns old space]
```

Then the problem is: **gotoSpace() returns success before the switch completes**. We need a longer delay or polling.

## Files Modified

**[modules/space_manager.lua](../modules/space_manager.lua)**

1. **Lines 62-74:** Added logging to `query_current_space()`
2. **Lines 79-95:** Added logging to `get_all_spaces()` with space count
3. **Lines 119-125:** Added logging to `gotoSpace()` call
4. **Lines 131-137:** Added space mismatch detection and warning

## Next Steps

1. **Reload Hammerspoon** with these new logs
2. **Test space switching** - both slow and rapid
3. **Analyze logs** to determine which hypothesis is correct:
   - Wrong space ID mapping?
   - Rapid switching confuses macOS?
   - Inconsistent allSpaces() data?
   - gotoSpace() returns too early?

4. **Based on findings**, implement appropriate fix:
   - Fix space ID mapping logic
   - Increase throttling delay
   - Cache allSpaces() result per switch
   - Increase post-switch verification delay

## Related Documentation

- [SPACES_MENUBAR_FIX.md](SPACES_MENUBAR_FIX.md) - Fixed menubar updates
- [SPACES_RAPID_SWITCH_FIX.md](SPACES_RAPID_SWITCH_FIX.md) - Throttling implementation
- [SPACES_READY.md](SPACES_READY.md) - Complete feature documentation

---

**Status:** ✅ Ready for testing
**Recommendation:** Reload Hammerspoon and test space switching, watch for `⚠️⚠️⚠️ SPACE MISMATCH` warnings
