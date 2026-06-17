# SentinelOne Performance Investigation

## Problem Statement
Extreme slowness when moving windows in ZoneTilerWM on machines with SentinelOne endpoint protection. Windows take 1-2+ seconds to move, making the tiler unusable.

## Timeline

### 2026-04-15: Auto-Tiler Improvements - COMPLETED

#### Issues Found
- Auto-tiler was missing tiles due to grid coordinate calculation failures with margins
- Fill gaps feature had inefficient overlap calculations
- Windows weren't optimally distributed - small windows getting stuck in large tiles while large windows had no options

#### Fixes Applied

1. **Grid-based occupancy map**: Replaced overlap ratio calculations with simple 2D boolean grid
   - Creates `grid[col][row]` boolean map based on monitor's cols×rows (e.g., 4×3)
   - Marks occupied cells based on window positions
   - Tile availability checked via O(1) grid lookup instead of O(tiles × occupied) loops

2. **Fixed tile coordinate calculation**: Replaced failing `get_grid_coords_for_tile()` with direct calculation from tile position

3. **Fill gaps optimization**:
   - Sort move_queue by current area (smallest first) so small windows get first pick
   - Track used tiles to prevent conflicts
   - Update grid when assigning tiles for subsequent windows
   - Iterate up to cols×rows times until no more improvements (max 12 for 4x3)

4. **Removed duplicate function**: Fixed syntax error from orphaned duplicate `_pass_fill_gaps` function

### 2026-04-14: Investigation & Fixes - COMPLETED

#### Root Cause Identified
- SentinelOne intercepts and slows down AXUI API calls (Accessibility API used by Hammerspoon)
- First move is fast (~0ms), subsequent moves have 2-second delays in `setFrame()` 
- Also: `get_windows_in_zone()` calls `hs.window.get(window_id)` which is slow on SentinelOne

#### Tests That Didn't Help
- AppleScript doesn't help - SentinelOne hooks more broadly than just AXUI
- AXEnhancedUI workaround only partially helps

#### Fixes Applied

1. **Removed unused slow function**: `get_windows_in_zone()` in window_state_manager was called but not used by placement_strategy - removed call from window_actions.lua

2. **Created window_cache module**: Pre-caches window frames/screens to avoid repeated `hs.window.allWindows()` calls

3. **Updated modules to use cache**: smart_placer, auto_tiler, focus_manager, layout_manager, window_memory, placement_strategy

4. **Fixed zone calculation bugs**:
   - Duplicate entries in config.toml for 2x2 layout
   - `largest_free_space` wasn't cycling properly - fixed to fallback to rotation when all tiles occupied
   - Rotation logic wasn't incrementing tile_index properly

5. **Added enterprise_mode config flag**: Enables AXEnhancedUI workaround when enabled in config.toml

6. **Added timing debug**: Helps identify bottlenecks (gated behind `debug_logging` config)

7. **Fixed function signature bug**: placement_strategy.find_best_tile takes 5 params, was passing wrong args

8. **Smart rotation for largest_free_space**: When already in target zone, cycles through tiles based on available space (tile area minus overlap with other windows)

9. **Fixed floating point matching bug**: Compare all 4 dimensions (x, y, w, h) with tolerance instead of just x, y to handle small precision differences between tile coordinates and window frame

#### Final Solution
- **Speed**: Very fast on SentinelOne machine (no more 2-second delays)
- **Rotation**: Works correctly - cycles through tiles based on available space when already in zone
- **Debug logging**: Gated behind `debug_logging = true` in `[tiler.advanced]` section of config
- **Fill gaps**: Iteratively improves tile assignment to fill empty spaces

## Config Settings
- `enterprise_mode = true` - enables AXEnhancedUI workaround
- `placement_strategy = "largest_free_space"` - current strategy
- `debug_logging = false` - set to true for verbose debug output

## Files Modified
- `/Users/ztomer/Projects/ZoneTilerWM/config.toml` - Added enterprise_mode, debug_logging
- `/Users/ztomer/Projects/ZoneTilerWM/modules/window_cache.lua` - NEW: Cache module for window data
- `/Users/ztomer/Projects/ZoneTilerWM/modules/placement_strategy.lua` - Fixed rotation, smart cycling, uses cache
- `/Users/ztomer/Projects/ZoneTilerWM/modules/window_actions.lua` - Removed get_windows_in_zone call, fixed args
- `/Users/ztomer/Projects/ZoneTilerWM/modules/auto_tiler.lua` - Grid-based fill gaps, iterative optimization

## Native port (v2) — how the same root cause is handled

The root cause is unchanged: **SentinelOne hooks, logs, and analyzes every Accessibility (AX)
call**, so the binding perf constraint is the *number* of AX round-trips an operation makes,
not CPU. The native Swift port (`native/`) addresses this structurally rather than with a
cache layer:

- **Reads use `CGWindowListCopyWindowInfo`, not AX.** `AXWindowSystem.onScreenWindows()` reads
  every window's geometry, owner, layer, and front-to-back z-order from the WindowServer in one
  call that needs **no Accessibility permission and is not on the hooked path**. All occupancy /
  z-order / enumeration (`windows(onScreen:)`) is built from it — **zero AX calls, independent
  of window count.** This eliminates the entire class of cost that forced the Lua's
  `window_cache` (where `hs.window.allWindows()` was per-window AX).
- **AX is used only to act.** AX round-trips happen for `move` / `focus` / `setMinimized` and to
  read the single focused element. So AX-call count scales with *actions*, not *windows*. A tile
  op is ~1 AX read (focused) + ~4–6 AX writes (resolve + EnhancedUI toggle + position + size);
  the occupancy scan over all other windows is free.
- **The one remaining hot knob: the `AXEnhancedUserInterface` toggle.** It runs on every move
  (1 AX read + up to 2 AX writes) because Firefox/Zen-class non-native-AX apps require it. Under
  SentinelOne those 2–3 hooked calls/move are the costliest part of a move; gating the toggle to
  known-quirky apps (by bundle id) would drop native-AX-app moves to just the two `setFrame`
  writes. Verify Firefox still moves before changing this. Tracked in `native/REVIEW.md` §1.
- **Escape hatch preserved:** `use_applescript_window_movement` selects an AppleScript /
  System-Events `WindowSystem` impl, and `enterprise_mode` forces the EnhancedUI workaround —
  same semantics as the Lua flags. (Note from 2026-04-14: AppleScript does *not* dodge
  SentinelOne, which hooks broader than AXUI; it is a compatibility fallback, not a speed-up.)