# Spaces Implementation Fixes Applied

**Date:** 2025-12-05
**Status:** ✅ Fixed and Ready for Testing

## Issues Fixed

### Issue #1: Invalid Space ID -1 Saved to Storage

**Problem:** The `hs.spaces.watcher` sometimes returns `-1` as a placeholder before the actual space ID is available. This invalid ID was being saved to:
- `space_definitions.json` (created a "Space -1" entry)
- `last_active_space.txt` (stored "-1")

**Root Cause:** No validation on space IDs before persisting to disk.

**Fix Applied:**

#### 1. Added Validation Function ([space_storage.lua:48-55](../modules/space_storage.lua#L48-L55))

```lua
--- Validates a space ID to ensure it's valid.
-- @param space_id (number) The space ID to validate.
-- @return (boolean) True if the space ID is valid.
local function is_valid_space_id(space_id)
    -- Space IDs must be positive numbers
    -- -1 is an invalid placeholder returned by hs.spaces.watcher sometimes
    return type(space_id) == "number" and space_id > 0
end
```

#### 2. Filter on Save ([space_storage.lua:67-81](../modules/space_storage.lua#L67-L81))

```lua
function space_storage.save_space_definitions(definitions)
    -- ...
    -- Filter out invalid space IDs (e.g., -1)
    local serializable = {}
    local filtered_count = 0
    for space_id, definition in pairs(definitions) do
        if is_valid_space_id(space_id) then
            serializable[tostring(space_id)] = definition
        else
            debug_log("Filtered out invalid space ID:", space_id)
            filtered_count = filtered_count + 1
        end
    end
    -- ...
end
```

#### 3. Filter on Load with Auto-Cleanup ([space_storage.lua:131-148](../modules/space_storage.lua#L131-L148))

```lua
function space_storage.load_space_definitions()
    -- ...
    if success and loaded then
        -- Convert string keys back to numbers and filter invalid IDs
        local definitions = {}
        local filtered_count = 0
        for space_id_str, definition in pairs(loaded) do
            local space_id = tonumber(space_id_str)
            if space_id and is_valid_space_id(space_id) then
                definitions[space_id] = definition
            else
                debug_log("Filtered out invalid space ID during load:", space_id_str)
                filtered_count = filtered_count + 1
            end
        end

        if filtered_count > 0 then
            debug_log("Cleaned up", filtered_count, "invalid space definition(s) during load")
            -- Save the cleaned definitions back to disk
            space_storage.save_space_definitions(definitions)
        end
        -- ...
    end
end
```

**Benefits:**
- Automatically cleans up invalid definitions on load
- Prevents new invalid IDs from being saved
- Self-healing - fixes corrupt data on startup

#### 4. Validate Last Active Space ([space_storage.lua:275-297](../modules/space_storage.lua#L275-L297))

```lua
function space_storage.set_last_active_space(space_id)
    -- Validate space ID before saving
    if not is_valid_space_id(space_id) then
        debug_log("Refusing to save invalid space ID as last active:", space_id)
        return false
    end
    -- ...
end

function space_storage.get_last_active_space()
    -- ...
    local space_id = tonumber(content)
    if space_id and is_valid_space_id(space_id) then
        debug_log("Loaded last active Space:", space_id)
        return space_id
    else
        debug_log("Invalid last active Space ID, ignoring:", space_id or content)
        return nil
    end
end
```

**Benefits:**
- Prevents `-1` from being saved as last active space
- Returns `nil` if invalid ID is found (fallback to current space detection)

#### 5. Validate in Space Manager ([space_manager.lua:194-199](../modules/space_manager.lua#L194-L199))

```lua
function space_manager.ensure_space_defined(space_id)
    -- Validate space ID - reject invalid IDs like -1
    if not space_id or type(space_id) ~= "number" or space_id <= 0 then
        debug_log("Refusing to create definition for invalid space ID:", space_id)
        return
    end
    -- ...
end
```

**Benefits:**
- Prevents invalid space definitions from being created in memory
- Additional safety layer beyond storage validation

### Manual Cleanup Applied

#### Cleaned Files:

1. **space_definitions.json** - Removed `-1` entry
   - Before: 8 definitions (including invalid -1)
   - After: 7 valid definitions (1, 3, 4, 5, 10, 48, 73)

2. **last_active_space.txt** - Changed from `-1` to `1`
   - Before: `-1`
   - After: `1` (valid space)

## Testing Instructions

### 1. Reload Hammerspoon

Press **Ctrl+Shift+Cmd+R** or run in Hammerspoon console:
```lua
hs.reload()
```

### 2. Verify No More -1 IDs

Run the test script:
```lua
dofile(os.getenv("HOME") .. "/Projects/ZoneTilerWM/test_spaces.lua")
```

Expected output:
- ✓ No "-1" space in definitions
- ✓ Current space is a valid positive number
- ✓ All space IDs are positive

### 3. Test Space Switching

Try switching spaces:
```
Ctrl+Shift+1 → Switch to Space 1
Ctrl+Shift+2 → Switch to Space 2
```

### 4. Check Storage Files

After switching spaces:
```bash
cat ~/.config/ZoneTilerWM/space_definitions.json | grep '"-1"'
# Should return nothing

cat ~/.config/ZoneTilerWM/last_active_space.txt
# Should show a positive number
```

## Expected Behavior

### Before Fix:
```json
{
  "-1": {
    "macos_space_id": -1,
    "name": "Space -1",
    ...
  },
  "1": { ... },
  ...
}
```

### After Fix:
```json
{
  "1": {
    "macos_space_id": 1,
    "name": "Space 1",
    ...
  },
  "3": { ... },
  ...
}
```

## What Happens Now

1. **On Startup:**
   - Loads space definitions
   - Filters out any invalid IDs (including -1)
   - Auto-saves cleaned definitions

2. **During Space Changes:**
   - Watcher receives -1 → triggers polling fallback
   - Polling finds actual space ID
   - Only valid IDs are saved to storage

3. **On Manual Definition:**
   - `ensure_space_defined(-1)` → rejected, logs warning
   - No definition created, no storage write

## Verification Checklist

After reloading Hammerspoon:

- [ ] No errors in Hammerspoon console
- [ ] Menubar shows current space number (not -1)
- [ ] `space_definitions.json` has no "-1" entry
- [ ] `last_active_space.txt` contains valid space number
- [ ] Space switching works (Ctrl+Shift+1-9)
- [ ] Debug logs show "Filtered out invalid space ID: -1" (if watcher fires with -1)
- [ ] No new -1 definitions are created

## Files Modified

1. [modules/space_storage.lua](../modules/space_storage.lua)
   - Added `is_valid_space_id()` validation function
   - Updated `save_space_definitions()` to filter invalid IDs
   - Updated `load_space_definitions()` with auto-cleanup
   - Updated `set_last_active_space()` to validate before save
   - Updated `get_last_active_space()` to validate on load

2. [modules/space_manager.lua](../modules/space_manager.lua)
   - Updated `ensure_space_defined()` to validate space IDs

3. Manual cleanup:
   - `~/.config/ZoneTilerWM/space_definitions.json` - Removed -1 entry
   - `~/.config/ZoneTilerWM/last_active_space.txt` - Set to valid space ID

## Impact

### Positive:
- ✅ No more invalid -1 space definitions
- ✅ Storage files stay clean
- ✅ Self-healing on startup
- ✅ Better debug logging
- ✅ Prevents future corruption

### No Breaking Changes:
- ✅ Backward compatible
- ✅ Existing valid spaces unaffected
- ✅ Auto-migration on load

## Related Documentation

- [SPACES_PHASE1_COMPLETE.md](SPACES_PHASE1_COMPLETE.md) - Phase 1 implementation summary
- [SPACES_IMPLEMENTATION_PLAN.md](SPACES_IMPLEMENTATION_PLAN.md) - Full implementation plan with Spaceman insights

---

**Status:** Ready for testing
**Next Steps:** Reload Hammerspoon and verify fixes
