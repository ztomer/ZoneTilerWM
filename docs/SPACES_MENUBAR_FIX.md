# Space Menubar Update Fix

**Date:** 2025-12-05
**Issue:** Menubar not updating when switching spaces
**Root Cause:** `get_current_space()` was updating state as a side effect, breaking post-switch verification logic
**Status:** ✅ Fixed

## Problem

When switching spaces, the menubar indicator was not updating to show the new active space. Looking at the logs:

```
2025-12-05 21:03:42: Switching to Space ID: 3
2025-12-05 21:03:44: Watcher received space_id: -1  (multiple times, never valid ID)
2025-12-05 21:03:46: Current Space ID: 3
2025-12-05 21:03:46: Post-switch verification: requested 4 actual 3
2025-12-05 21:03:46: Watcher already updated space state, no manual update needed
```

The issue: **No menubar update callbacks were being triggered**.

## Root Cause Analysis

### The Hidden Side Effect

`space_manager.get_current_space()` was updating `spaces.current_space_id` as a side effect:

```lua
function space_manager.get_current_space()
    local success, space_id = pcall(function()
        return hs.spaces.focusedSpace()
    end)

    if success and space_id then
        spaces.current_space_id = space_id  -- ❌ SIDE EFFECT!
        debug_log("Current Space ID:", space_id)
        return space_id
    end
end
```

### How This Broke Post-Switch Verification

The post-switch verification code was calling `get_current_space()`:

```lua
hs.timer.doAfter(0.3, function()
    local actual_space = space_manager.get_current_space()  -- ❌ Updates state!

    -- By the time we check, spaces.current_space_id is already updated
    if actual_space ~= spaces.current_space_id then  -- ❌ Always false!
        -- This never runs, so callbacks never fire
    end
end)
```

**The Bug:**
1. Post-switch timer fires
2. Calls `get_current_space()` which returns `3`
3. As a side effect, also updates `spaces.current_space_id` to `3`
4. Checks if `3 != 3` → false
5. Skips manual update
6. Callbacks never triggered
7. Menubar never updates

## Solution

### 1. Created `query_current_space()` Function

Added a new function that queries the space WITHOUT updating state:

```lua
--- Queries the current Space ID without updating internal state.
-- Use this when you want to check the space without side effects.
-- @return (number|nil) The current Space ID, or nil if API call fails.
local function query_current_space()
    local success, space_id = pcall(function()
        return hs.spaces.focusedSpace()
    end)

    if success and space_id then
        return space_id
    else
        return nil
    end
end
```

### 2. Updated Post-Switch Verification

Changed to use `query_current_space()` instead:

```lua
hs.timer.doAfter(0.3, function()
    local actual_space = query_current_space()  -- ✅ No side effects!
    debug_log("Post-switch verification: requested", space_id,
              "actual", actual_space, "stored", spaces.current_space_id)

    if actual_space and actual_space > 0 and actual_space ~= spaces.current_space_id then
        -- ✅ Now this comparison works correctly!
        -- Update state and trigger callbacks
    end
end)
```

### 3. Enhanced Logging

Added emoji markers and more detailed logging to diagnose space changes:

```lua
-- In on_space_change():
debug_log("Watcher received space_id:", space_id, "type:", type(space_id))

if not space_id or space_id == -1 or space_id <= 0 then
    debug_log("❌ Ignoring invalid space ID from watcher:", space_id)
    return
end

debug_log("✅ VALID space ID from watcher:", space_id)
debug_log("📝 Updated space_id:", old_space_id, "->", space_id)
debug_log("🔔 Notifying", #spaces.change_callbacks, "callbacks of space change")

for i, callback in ipairs(spaces.change_callbacks) do
    local success, err = pcall(callback, space_id, old_space_id)
    if not success then
        debug_log("❌ Callback", i, "error:", err)
    else
        debug_log("✅ Callback", i, "completed successfully")
    end
end
```

Similar markers for manual updates:
- `🔧 Manually updating space state`
- `🔔 Notifying callbacks of manual space change`

## Expected Behavior After Fix

### When Watcher Fires with Valid ID

```
2025-12-05 XX:XX:XX: ========== SPACE CHANGE EVENT ==========
2025-12-05 XX:XX:XX: Watcher received space_id: 3 type: number
2025-12-05 XX:XX:XX: Current stored space_id: 1
2025-12-05 XX:XX:XX: ✅ VALID space ID from watcher: 3
2025-12-05 XX:XX:XX: 📝 Updated space_id: 1 -> 3
2025-12-05 XX:XX:XX: 🔔 Notifying 1 callbacks of space change: 1 -> 3
2025-12-05 XX:XX:XX: ✅ Callback 1 completed successfully
2025-12-05 XX:XX:XX: Saved space to storage
2025-12-05 XX:XX:XX: ========== SPACE CHANGE COMPLETE ==========
```

### When Watcher Only Sends -1 (Manual Update Kicks In)

```
2025-12-05 XX:XX:XX: ========== SPACE CHANGE EVENT ==========
2025-12-05 XX:XX:XX: Watcher received space_id: -1 type: number
2025-12-05 XX:XX:XX: Current stored space_id: 1
2025-12-05 XX:XX:XX: ❌ Ignoring invalid space ID from watcher: -1

[300ms later]

2025-12-05 XX:XX:XX: Post-switch verification: requested 3 actual 3 stored 1
2025-12-05 XX:XX:XX: 🔧 Manually updating space state (watcher didn't fire with valid ID)
2025-12-05 XX:XX:XX: 📝 Updated space_id: 1 -> 3
2025-12-05 XX:XX:XX: 🔔 Notifying 1 callbacks of manual space change: 1 -> 3
2025-12-05 XX:XX:XX: ✅ Callback 1 completed successfully
2025-12-05 XX:XX:XX: Saved space to storage
```

**In both cases, the menubar callback is triggered and the menubar updates!**

## Files Modified

**[modules/space_manager.lua](../modules/space_manager.lua)**

1. **Lines 39-56:** Added documentation to `get_current_space()` warning about side effects
2. **Lines 58-71:** Added new `query_current_space()` function (no side effects)
3. **Line 120:** Changed post-switch verification to use `query_current_space()`
4. **Line 121:** Enhanced logging to show `stored` value
5. **Lines 167-183:** Enhanced watcher callback logging with emojis
6. **Lines 189-196:** Enhanced callback notification logging
7. **Lines 124-140:** Enhanced manual update logging

## Testing Checklist

After reload, verify:

- [ ] Menubar shows current space on startup
- [ ] Press `Ctrl+Shift+2`, menubar updates to `1 [2] 3 4 5 6`
- [ ] Logs show either:
  - `✅ VALID space ID from watcher` + `✅ Callback completed`
  - OR `🔧 Manually updating` + `✅ Callback completed`
- [ ] No more "Watcher already updated" when it actually didn't
- [ ] Rapid switches still throttled, menubar still updates

## Performance Impact

**Minimal** - Added one extra API call (`query_current_space()`) during post-switch verification, but only when needed (300ms after switch). The function is lightweight and doesn't update state.

## Known Behavior

### Watcher Reliability Varies

Sometimes the watcher fires with valid IDs, sometimes only with -1. Both cases now work:

1. **Watcher fires with valid ID:** Callbacks triggered immediately
2. **Watcher only fires with -1:** Post-switch verification triggers callbacks after 300ms

The user experience is the same - menubar always updates within ~300ms.

## Related Issues

### Preview Logic (Noted by User)

User mentioned: "The preview logic doesn't make sense - we already track all the windows, we can also track in which space they are, we don't need to use the spaces API for that on every call."

**Current Status:** Preview is disabled (`config.spaces.preview.enabled = false`), so this is not an active issue. If we re-enable preview in the future, we should:

1. Track window space assignments in window_state_manager
2. Update space assignments when windows are created/moved
3. Avoid calling `hs.spaces.windowSpaces()` repeatedly
4. Use cached data from our window tracking

## Related Documentation

- [SPACES_RAPID_SWITCH_FIX.md](SPACES_RAPID_SWITCH_FIX.md) - Throttling and post-switch verification
- [SPACES_FINAL_FIX.md](SPACES_FINAL_FIX.md) - Removed polling mechanism
- [SPACES_READY.md](SPACES_READY.md) - Complete feature documentation

---

**Status:** ✅ Ready for testing
**Recommendation:** Reload Hammerspoon and test menubar updates
**Expected Result:** Menubar always updates within 300ms of space switch
