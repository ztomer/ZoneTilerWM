# SentinelOne Performance Investigation

## Problem Statement
Extreme slowness when moving windows in ZoneTilerWM on machines with SentinelOne endpoint protection. Windows take 1-2+ seconds to move, making the tiler unusable.

## Timeline

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

## Config Settings
- `enterprise_mode = true` - enables AXEnhancedUI workaround
- `placement_strategy = "largest_free_space"` - current strategy
- `debug_logging = false` - set to true for verbose debug output

## Files Modified
- `/Users/ztomer/Projects/ZoneTilerWM/config.toml` - Added enterprise_mode, debug_logging
- `/Users/ztomer/Projects/ZoneTilerWM/modules/window_cache.lua` - NEW: Cache module for window data
- `/Users/ztomer/Projects/ZoneTilerWM/modules/placement_strategy.lua` - Fixed rotation, smart cycling, uses cache
- `/Users/ztomer/Projects/ZoneTilerWM/modules/window_actions.lua` - Removed get_windows_in_zone call, fixed args