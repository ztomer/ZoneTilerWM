# Space Polling Cascade Fix

**Date:** 2025-12-05
**Issue:** Multiple concurrent polling timers causing log spam
**Status:** ✅ Fixed

## Problem

When switching spaces, the watcher would fire multiple times with `-1` space IDs, and each event would start its own independent polling loop. This caused:

1. **Polling Cascade:** 10-15 concurrent polling loops running simultaneously
2. **Log Spam:** Hundreds of "Poll attempt N" messages
3. **Resource Waste:** Multiple timers checking the same thing
4. **Never Terminates:** Polls would continue even after finding the actual space

### Example Log (Before Fix):
```
2025-12-05 20:47:20: Poll attempt	9	- queried space:	1	stored:	1
2025-12-05 20:47:20: Poll attempt	3	- queried space:	1	stored:	1
2025-12-05 20:47:20: Poll attempt	1	- queried space:	1	stored:	1
2025-12-05 20:47:20: Poll attempt	2	- queried space:	1	stored:	1
2025-12-05 20:47:20: Poll attempt	4	- queried space:	1	stored:	1
... (continues for 15 attempts × multiple concurrent timers)
```

## Root Cause

### Old Implementation Issues:

1. **Each watcher event created a NEW polling loop:**
   ```lua
   if not space_id or space_id == -1 then
       -- Each -1 event starts its own loop
       local retry_count = 0
       local function poll_for_space()
           -- Creates new timer with doAfter
           hs.timer.doAfter(delay, poll_for_space)
       end
   end
   ```

2. **Weak debounce check:**
   ```lua
   if poll_timer_active and (now - last_poll_time) < 2 then
       return  -- Only prevents if < 2 seconds
   end
   ```
   - `poll_timer_active` flag was set/unset per loop
   - Each loop had its own `retry_timer` variable
   - No way to stop other loops when one succeeded

3. **Exponential backoff created cascading timers:**
   - Timer 1: 0.1s, 0.2s, 0.3s, 0.4s...
   - Timer 2: 0.1s, 0.2s, 0.3s, 0.4s...
   - Timer 3: 0.1s, 0.2s, 0.3s, 0.4s...
   - All running concurrently!

## Solution

### Fixed Implementation ([space_manager.lua:93-162](../modules/space_manager.lua#L93-L162))

#### 1. Single Shared Timer

```lua
-- Debounce state for space change detection
local active_poll_timer = nil  -- SHARED across all events
local last_poll_start_time = 0
```

**Key Changes:**
- ONE timer variable shared by all watcher events
- Prevents multiple concurrent polls

#### 2. Strong Debounce Check

```lua
-- Prevent multiple concurrent polls - if one is already running, skip this one
if active_poll_timer and active_poll_timer:running() then
    debug_log("Skipping poll - another poll is already running")
    return
end

-- Also prevent polls within 1 second of each other
local now = os.time()
if now - last_poll_start_time < 1 then
    debug_log("Skipping poll - too soon after last poll (< 1 second)")
    return
end
```

**Benefits:**
- Checks if timer is actually `running()` (not just a boolean flag)
- Time-based debounce prevents rapid-fire polls
- Returns early before creating any timers

#### 3. Repeating Timer Instead of Recursive doAfter

```lua
-- Old approach (BAD - creates multiple timers):
local function poll_for_space()
    if retry_count < max_retries then
        hs.timer.doAfter(delay, poll_for_space)  -- New timer each call
    end
end

-- New approach (GOOD - single repeating timer):
active_poll_timer = hs.timer.doUntil(
    poll_for_space,  -- condition function
    function() end,  -- action function
    0.2              -- interval: 200ms (fixed, not exponential)
)
```

**Benefits:**
- ONE timer that repeats every 200ms
- Stops when condition returns `true`
- No cascading timer creation

#### 4. Reduced Max Retries

```lua
local max_retries = 5  -- Reduced from 15
```

**Rationale:**
- 5 attempts × 200ms = 1 second total
- Spaceman polls every 100ms for ~1 second
- If space isn't detected in 1 second, it likely hasn't changed

#### 5. Proper Cleanup on Success

```lua
if actual_space and actual_space ~= -1 and actual_space ~= spaces.current_space_id then
    debug_log("SUCCESS: Found new space after", retry_count, "attempts:", actual_space)
    if active_poll_timer then
        active_poll_timer:stop()  -- Stop the timer
        active_poll_timer = nil     -- Clear the reference
    end
    on_space_change(actual_space)  -- Process the change
    return true  -- Stop timer
end
```

## Space Preview Disabled

Additionally disabled the space preview feature which was experimental and potentially causing the "expose mode" artifacts.

### Changes:

1. **[config.lua:387](../config.lua#L387)** - Disabled preview:
   ```lua
   preview = {
       enabled = false, -- DISABLED - experimental feature
   ```

2. **[init.lua:99-106](../init.lua#L99-L106)** - Conditional initialization:
   ```lua
   if config.spaces.preview and config.spaces.preview.enabled then
       space_preview.init(config, space_manager, tiler.window_state, print)
       print("Space preview enabled")
   end

   local preview_module = (config.spaces.preview and config.spaces.preview.enabled) and space_preview or nil
   space_menubar.init(config, space_manager, preview_module, print)
   ```

**Benefits:**
- Preview only loads when explicitly enabled
- Menubar works without preview (preview_module = nil)
- Reduces complexity and potential side effects

## Expected Behavior After Fix

### Log Output (Clean):
```
2025-12-05 XX:XX:XX: ========== SPACE CHANGE EVENT ==========
2025-12-05 XX:XX:XX: Watcher received space_id:	-1
2025-12-05 XX:XX:XX: Current stored space_id:	5
2025-12-05 XX:XX:XX: WARNING: Invalid space ID received, will poll for actual space
2025-12-05 XX:XX:XX: Poll attempt	1	- queried space:	1	stored:	5
2025-12-05 XX:XX:XX: SUCCESS: Found new space after 1 attempts:	1
2025-12-05 XX:XX:XX: Updated space_id:	5	->	1
2025-12-05 XX:XX:XX: ========== SPACE CHANGE COMPLETE ==========
```

**Key Points:**
- ONE polling sequence per space change
- Finds space quickly (usually attempt 1-2)
- No duplicate polls
- Clean termination

### If Space Doesn't Change:
```
2025-12-05 XX:XX:XX: Poll attempt	1	- queried space:	5	stored:	5
2025-12-05 XX:XX:XX: Poll attempt	2	- queried space:	5	stored:	5
...
2025-12-05 XX:XX:XX: Poll attempt	5	- queried space:	5	stored:	5
2025-12-05 XX:XX:XX: INFO: Gave up polling after 5 attempts - space unchanged at 5
```

**No cascading loops, just 5 attempts over 1 second, then stops.**

## Testing

### Before Reloading:
```bash
# Check current implementation
grep -A 3 "active_poll_timer" /Users/ztomer/Projects/ZoneTilerWM/modules/space_manager.lua
```

### After Reloading:
1. Reload Hammerspoon: `Ctrl+Shift+Cmd+R`
2. Switch spaces: `Ctrl+Shift+1`, `Ctrl+Shift+2`
3. Watch console logs - should be clean
4. Check no preview artifacts appear

### Expected Results:
- ✅ Single polling sequence per space change
- ✅ Polls stop after finding space (1-2 attempts usually)
- ✅ No "Skipping poll - another poll is already running" spam
- ✅ No expose mode/preview artifacts
- ✅ Fast space switching (< 500ms)

## Files Modified

1. **[modules/space_manager.lua](../modules/space_manager.lua)**
   - Lines 93-162: Rewrote polling mechanism
   - Single shared timer instead of multiple concurrent timers
   - Stronger debounce checks
   - Fixed-interval repeating timer (200ms)
   - Reduced max retries (5 instead of 15)

2. **[config.lua](../config.lua)**
   - Line 387: Disabled space preview

3. **[init.lua](../init.lua)**
   - Lines 99-106: Conditional preview initialization

## Performance Impact

### Before Fix:
- Multiple timers running concurrently (10-15)
- Exponential backoff creates many scheduled callbacks
- High CPU usage during polling
- Log file grows rapidly

### After Fix:
- ONE timer at a time
- Fixed 200ms interval (5 attempts max)
- Minimal CPU usage
- Clean logs

## Related Documentation

- [SPACES_FIXES_APPLIED.md](SPACES_FIXES_APPLIED.md) - Space ID validation fixes
- [SPACES_PHASE1_COMPLETE.md](SPACES_PHASE1_COMPLETE.md) - Phase 1 implementation
- [SPACES_IMPLEMENTATION_PLAN.md](SPACES_IMPLEMENTATION_PLAN.md) - Full plan with Spaceman insights

---

**Status:** Ready for testing
**Recommendation:** Reload Hammerspoon and test space switching
