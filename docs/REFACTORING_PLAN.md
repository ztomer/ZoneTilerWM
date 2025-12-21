# ZoneTilerWM - Code Cleanup & Streamlining Plan

**Date:** December 13, 2025
**Objective:** Improve code organization, reduce complexity, and enhance maintainability without changing functionality
**Scope:** Architecture refactoring, code cleanup, standardization

---

## Executive Summary

This document outlines a comprehensive plan to clean up and streamline the ZoneTilerWM codebase. The project is well-architected with clear separation of concerns, but there are opportunities to reduce duplication, improve consistency, and simplify complex areas. All proposed changes maintain existing functionality.

**Key Metrics:**
- Total Lines of Code: ~4,387 (18 modules)
- Largest Module: [tiler.lua](modules/tiler.lua) (582 lines)
- Average Module Size: 243 lines
- Configuration: 393 lines

---

## 1. Module Initialization Patterns

### Current State

Modules use inconsistent initialization patterns:

**Pattern A - Manual Dependency Injection** (Most modules):
```lua
function module.init(cfg, dep1, dep2, log_func)
    config = cfg
    dependency1 = dep1
    -- ...
end
```

**Pattern B - Late Binding** (window_memory, tiler):
```lua
function tiler.set_window_memory(wm)
    window_memory = wm
    -- Propagate to other modules
end
```

**Pattern C - Global Access** (debug system):
```lua
_G.zt_debug = debug
```

### Issues

1. **Inconsistent dependency injection**: Some modules receive dependencies via `init()`, others via dedicated setters
2. **Circular dependency workarounds**: `window_memory` ↔ `tiler` requires manual setter injection
3. **Init call ordering complexity**: Modules must be initialized in specific order (documented in [init.lua:63-103](init.lua#L63-L103))
4. **Duplicate parameter passing**: Same dependencies passed to multiple modules

### Recommended Changes

#### 1.1 Standardize Initialization Interface

Create a consistent initialization signature for all modules:

```lua
-- Standard init pattern for all modules
function module.init(dependencies)
    -- dependencies = {
    --   config = config,
    --   monitor_manager = monitor_manager,
    --   debug_log = debug_log,
    --   ... other deps
    -- }
end
```

**Benefits:**
- Single pattern across all modules
- Easier to add/remove dependencies
- Self-documenting through named parameters
- Eliminates positional parameter errors

**Modules to Update:**
- [tiler.lua:492-565](modules/tiler.lua#L492-L565)
- [window_actions.lua:507-516](modules/window_actions.lua#L507-L516)
- [zone_calculator.lua:455-462](modules/zone_calculator.lua#L455-L462)
- [focus_manager.lua:396-403](modules/focus_manager.lua#L396-L403)
- [smart_placer.lua:131-139](modules/smart_placer.lua#L131-L139)
- All other modules with `init()` functions

#### 1.2 Remove Circular Dependencies

**Current circular dependency:**
```
tiler ──requires──> window_memory
window_memory ──requires (via setter)──> tiler
```

**Solution:** Introduce an event system or callback registration:

```lua
-- In window_memory.lua
function window_memory.init(dependencies)
    -- Register for events instead of holding tiler reference
    dependencies.event_bus:on('window_positioned', on_window_positioned)
end
```

**Alternative:** Extract shared state into `window_state_manager` (already partially done)

**Files to Modify:**
- [init.lua:80-82](init.lua#L80-L82) - Remove `window_memory.init(tiler)` pattern
- [modules/tiler.lua:572-581](modules/tiler.lua#L572-L581) - Remove `set_window_memory()` setter
- [modules/window_memory.lua](modules/window_memory.lua) - Refactor to use callbacks/events

#### 1.3 Create Initialization Helper

Add a module loader to [init.lua](init.lua) to simplify dependency wiring:

```lua
-- New: modules/module_loader.lua
local function initialize_all(config, debug_system)
    local deps = {
        config = config,
        debug = debug_system,
    }

    -- Initialize in dependency order
    deps.monitor_manager = require("modules.monitor_manager").init(deps)
    deps.zone_calculator = require("modules.zone_calculator").init(deps)
    -- ... etc

    return deps
end
```

---

## 2. Configuration Management

### Current State

Configuration is centralized in [config.lua](config.lua) (393 lines) with 12 major sections:

```lua
config.keys                 -- Line 17-23
config.audio_switcher       -- Line 26-33
config.app_switcher         -- Line 36-47
config.appCuts             -- Line 50-66
config.hyperAppCuts        -- Line 68-86
config.system_hotkeys      -- Line 89-93
config.pomodoro            -- Line 96-112
config.tiler               -- Line 115-351 (236 lines!)
config.window_handling     -- Line 354-356
config.window_memory       -- Line 358-387
config.layout_manager      -- Line 389-391
```

### Issues

1. **Monolithic config file**: 393 lines with deeply nested structures
2. **Section size imbalance**: `config.tiler` is 236 lines (60% of file)
3. **Mixed concerns**: UI hotkeys, business logic settings, and data structures all in one place
4. **Hardcoded app names**: Scattered throughout (lines 38, 51-66, 69-86, 374-375, 381-386)
5. **Duplicate screen detection logic**: Both pattern-based and size-based config (lines 139-181)

### Recommended Changes

#### 2.1 Split Configuration by Domain

Break [config.lua](config.lua) into focused config files:

```
config/
├── init.lua                    -- Main loader, exports consolidated config
├── keys.lua                    -- All keyboard bindings
├── tiler/
│   ├── grids.lua              -- Grid specifications (lines 185-210)
│   ├── layouts.lua            -- Layout definitions (lines 230-318)
│   ├── screen_detection.lua   -- Screen detection rules (lines 137-182)
│   └── settings.lua           -- General tiler settings
├── apps.lua                   -- App shortcuts and mappings
├── features.lua               -- Pomodoro, audio, system hotkeys
└── persistence.lua            -- Window memory, layout manager
```

**Benefits:**
- Each file under 100 lines
- Clear ownership and discoverability
- Easier to test individual config sections
- Reduces merge conflicts

#### 2.2 Normalize Layout Definitions

Current layout definitions use inconsistent tile arrays:

```lua
["4x3"] = {
    ["y"] = {"a1:a2", "a1", "a1:b2"},      -- 3 tiles
    ["h"] = {"a1:b3", "a1:a3", "a1:c3", "a2"},  -- 4 tiles
    ["0"] = {"b2:c2", "a1:d3", "center"}   -- Mixed: grid + named
},
["2x2"] = {
    ["y"] = {"a1", "a1:a2", "a1:b1"},      -- Same zone, different grids
    ["0"] = {"center", "a1:b2", "a1:b1"}   -- Different order/priority
}
```

**Issues:**
- Tile order determines placement priority but isn't documented
- Mixed coordinate systems (grid coords + named positions)
- Duplicate zone keys across layouts with different meanings

**Solution:** Add metadata to layout definitions:

```lua
layouts = {
    ["4x3"] = {
        ["y"] = {
            primary = "a1:a2",           -- Default tile for zone
            alternates = {"a1", "a1:b2"}, -- Fallback tiles
            description = "Top-left zone"
        }
    }
}
```

#### 2.3 Extract Hardcoded Values

Move magic numbers and app lists to named constants:

**Current** ([config.lua](config.lua)):
```lua
overlap_threshold = 0.5,        -- Line 330
cell_size = 50,                -- Line 324
margins.size = 5,              -- Line 131
settle_delay_sec = 2.0,        -- Line 361
work_period_sec = 52 * 60,     -- Line 98
```

**Improved:**
```lua
-- config/constants.lua
DEFAULTS = {
    WINDOW_OVERLAP_THRESHOLD = 0.5,
    SMART_PLACEMENT_CELL_SIZE_PX = 50,
    MARGIN_SIZE_PX = 5,
    POSITION_SETTLE_DELAY_SEC = 2.0,
    POMODORO_WORK_MINUTES = 52,
    POMODORO_REST_MINUTES = 17,
}
```

---

## 3. Error Handling & Validation

### Current State

Error handling is inconsistent across modules:

**Pattern A - Silent Failure:**
```lua
-- window_actions.lua:206-208
if not window or not window:isStandard() then
    debug_log("move_window_to_zone: Invalid window");
    return false
end
```

**Pattern B - Debug Log Only:**
```lua
-- zone_calculator.lua:128
debug_log("Could not create tile for coords:", coords, "on screen", screen:name())
return nil
```

**Pattern C - Console Print:**
```lua
-- zone_calculator.lua:310
print("Zone '" .. zone_key .. "' not found on monitor " .. monitor_id)
```

**Pattern D - Alert + Print:**
```lua
-- init.lua:69-70
hs.alert.show("Config Error: " .. err, 5)
print("Config Error: " .. err)
```

### Issues

1. **Inconsistent logging**: Mix of `debug_log()`, `print()`, and `hs.alert.show()`
2. **No error severity levels**: All errors treated the same
3. **Missing user feedback**: Critical errors only logged, not displayed
4. **Validation timing**: Config validated at runtime, not load time
5. **Silent failures**: Many functions return `false` without explaining why

### Recommended Changes

#### 3.1 Standardize Error Reporting

Create error handling utilities:

```lua
-- modules/error_handler.lua
local error_handler = {}

function error_handler.critical(message, details)
    -- Log, alert user, and halt execution
    debug_log("CRITICAL: " .. message, details)
    hs.alert.show("Critical Error: " .. message, 10)
    error(message)
end

function error_handler.recoverable(message, details)
    -- Log and alert, but continue
    debug_log("ERROR: " .. message, details)
    hs.alert.show(message, 3)
end

function error_handler.warn(message, details)
    -- Log only, no user interruption
    debug_log("WARN: " .. message, details)
end
```

**Usage:**
```lua
-- Before
if not window then
    debug_log("No window");
    return false
end

-- After
if not window then
    return error_handler.recoverable("Cannot move window: No focused window", {
        caller = "move_window_to_zone"
    })
end
```

#### 3.2 Improve Validation Feedback

Current config validation in [modules/config_validator.lua](modules/config_validator.lua) only checks structure, not values.

**Add semantic validation:**
- Grid sizes are positive integers
- Hotkey modifiers are valid
- Screen detection patterns compile as regex
- File paths exist and are writable
- App names in exclusion lists are non-empty

**Provide detailed error messages:**
```lua
-- Before
return false, "Invalid config"

-- After
return false, "config.tiler.grids['4x3'].cols must be a positive integer, got: " .. type(value)
```

#### 3.3 Fail-Fast Validation

Move validation earlier in initialization:

**Current:** [init.lua:67-72](init.lua#L67-L72)
```lua
local valid, err = config_validator.validate(config)
if not valid then
    hs.alert.show("Config Error: " .. err, 5)
    return -- Stop initialization
end
```

**Improved:**
```lua
-- Validate immediately on require()
local config = require("config")
local validator = require("modules.config_validator")

-- Fail immediately if config is invalid
assert(validator.validate(config))

-- Continue with initialization
```

---

## 4. Code Duplication

### Identified Duplication

#### 4.1 Frame Application Logic

**Locations:**
- [window_actions.lua:120-135](modules/window_actions.lua#L120-L135) - `apply_frame()`
- [window_actions.lua:145-178](modules/window_actions.lua#L145-L178) - `apply_frame_to_problem_app()`

**Common code (~60% overlap):**
```lua
local saved_duration = hs_window.animationDuration
hs_window.animationDuration = 0
local success = window:setFrame(valid_frame)
hs_window.animationDuration = saved_duration
```

**Refactor:** Extract animation disabling wrapper:
```lua
local function with_animation_disabled(fn)
    local saved = hs_window.animationDuration
    hs_window.animationDuration = 0
    local result = fn()
    hs_window.animationDuration = saved
    return result
end

function apply_frame(window, frame, force_screen_obj)
    -- Preparation logic...
    return with_animation_disabled(function()
        return window:setFrame(valid_frame)
    end)
end
```

#### 4.2 Screen/Monitor ID Retrieval

**Locations:**
- [tiler.lua:122](modules/tiler.lua#L122) - `monitor_manager.get_id(screen)`
- [window_actions.lua:217](modules/window_actions.lua#L217) - `monitor_manager.get_id(screen_obj)`
- [focus_manager.lua:169](modules/focus_manager.lua#L169) - `monitor_manager.get_id(current_screen_obj)`
- [smart_placer.lua:60](modules/smart_placer.lua#L60) - `monitor_manager.get_id(screen)`

**Pattern:** Always called with `window:screen()` result

**Refactor:** Add convenience method to window_state_manager:
```lua
function window_state_manager.get_monitor_id_for_window(window)
    local screen = window:screen()
    if not screen then return nil end
    return monitor_manager.get_id(screen)
end
```

#### 4.3 Window Validation

**Locations:**
- [tiler.lua:52-56](modules/tiler.lua#L52-L56)
- [window_actions.lua:206-209](modules/window_actions.lua#L206-L209)
- [window_actions.lua:278-281](modules/window_actions.lua#L278-L281)
- [window_actions.lua:315-318](modules/window_actions.lua#L315-L318)
- [smart_placer.lua:30-32](modules/smart_placer.lua#L30-L32)
- [focus_manager.lua:157-161](modules/focus_manager.lua#L157-L161)

**Pattern:** Check if window is valid, standard, and not minimized

**Refactor:** Create utility function:
```lua
-- modules/window_utils.lua
function window_utils.is_tileable(window)
    return window
        and window:isStandard()
        and not window:isMinimized()
end
```

#### 4.4 Placement Attempt Pattern

**Locations:**
- [tiler.lua:164-180](modules/tiler.lua#L164-L180) - Try remembered position
- [tiler.lua:185-206](modules/tiler.lua#L185-L206) - Try configured zones
- [window_actions.lua:366-377](modules/window_actions.lua#L366-L377) - Try remembered position
- [window_actions.lua:380-392](modules/window_actions.lua#L380-L392) - Try same zone

**Pattern:** Attempt multiple placement strategies in sequence

**Refactor:** Create placement pipeline:
```lua
-- modules/placement_pipeline.lua
function placement_pipeline.try_strategies(window, monitor_id, strategies)
    for _, strategy in ipairs(strategies) do
        if strategy(window, monitor_id) then
            return true
        end
    end
    return false
end

-- Usage
placement_pipeline.try_strategies(window, monitor_id, {
    strategies.from_memory,
    strategies.from_app_config,
    strategies.from_default_zone,
    strategies.smart_placement
})
```

---

## 5. Complex Functions

### 5.1 tiler.attempt_reposition_existing_window()

**Location:** [tiler.lua:139-218](modules/tiler.lua#L139-L218)
**Size:** 80 lines
**Complexity:** High (4 placement strategies with nested conditionals)

**Issues:**
- Multiple responsibilities (validation, placement, fallback)
- Deep nesting (4 levels)
- Strategy logic mixed with validation

**Refactor:**
```lua
function tiler.attempt_reposition_existing_window(window)
    if not validate_window_for_repositioning(window) then
        return
    end

    local context = create_reposition_context(window)

    placement_pipeline.execute({
        placement_strategies.from_memory,
        placement_strategies.from_app_zone,
        placement_strategies.from_default_zone,
        placement_strategies.smart_placement
    }, context)
end
```

### 5.2 focus_manager.cycle_windows_in_zone()

**Location:** [focus_manager.lua:156-332](modules/focus_manager.lua#L156-L332)
**Size:** 177 lines
**Complexity:** Very High (cycle rebuild logic, window collection, focus advancement)

**Issues:**
- Single function handles cycle rebuild, validation, and focus change
- Nested conditionals for rebuild detection (6 levels deep)
- Mixes state management with business logic

**Refactor:**
```lua
function focus_manager.cycle_windows_in_zone(focused_window, target_zone_key)
    local context = create_focus_context(focused_window, target_zone_key)

    if cycle_needs_rebuild(context) then
        rebuild_cycle(context)
    end

    return advance_focus_to_next_window(context)
end

-- Separate functions:
-- - create_focus_context()
-- - cycle_needs_rebuild()
-- - rebuild_cycle()
-- - advance_focus_to_next_window()
```

### 5.3 window_actions.move_window_to_monitor()

**Location:** [window_actions.lua:314-440](modules/window_actions.lua#L314-L440)
**Size:** 127 lines
**Complexity:** High (4 fallback strategies, special app handling)

**Issues:**
- Strategy selection mixed with execution
- Duplicate AX handling code (lines 412-434)
- Hard to test individual strategies

**Refactor:**
```lua
function window_actions.move_window_to_monitor(window, direction)
    local target_screen = get_target_screen(window, direction)
    if not target_screen then return false end

    return move_strategies.execute_in_order({
        move_strategies.to_remembered_position,
        move_strategies.to_equivalent_zone,
        move_strategies.to_default_zone,
        move_strategies.to_screen_only
    }, window, target_screen)
end
```

---

## 6. Naming Conventions

### Current State

Naming is mostly consistent but has variations:

**Module-level state variables:**
- ✅ Good: `local config = nil` (consistent across all modules)
- ✅ Good: `local debug_log` (centralized debug pattern)
- ❌ Inconsistent: `local hs_window` vs `local hs_screen` vs `hs_hotkey` (some modules prefix, others don't)

**Function naming:**
- ✅ Good: `snake_case` used throughout
- ❌ Inconsistent: `get_layout_config` vs `getWindows` (Hammerspoon API uses camelCase)
- ❌ Verbose: `attempt_reposition_existing_window` (41 chars)

**Variable naming:**
- ✅ Good: Descriptive names like `zone_tiles_for_this_zone`
- ❌ Inconsistent: `cfcm` shorthand (line 176) vs full names elsewhere
- ❌ Abbreviations: `cfg`, `mm`, `zc`, `wsm`, `ps` used in init signatures

### Recommended Changes

#### 6.1 Standardize Hammerspoon API Caching

**Current pattern (inconsistent):**
```lua
-- Some modules
local hs_window = hs.window
local hs_screen = hs.screen

-- Other modules
-- No caching, direct calls to hs.window
```

**Standardized:**
```lua
-- At top of every module that uses hs APIs
local hs = {
    window = hs.window,
    screen = hs.screen,
    hotkey = hs.hotkey,
    timer = hs.timer,
}
```

#### 6.2 Reduce Function Name Verbosity

Apply "verb_noun" pattern consistently:

```lua
-- Before
attempt_reposition_existing_window()
create_tile_from_grid_coords()
get_layout_config()

-- After
reposition_window()
tile_from_coords()
get_layout()
```

#### 6.3 Use Full Names in Init Signatures

**Current:**
```lua
function module.init(cfg, mm, zc, wsm, ps, log_func)
```

**Improved:**
```lua
function module.init(dependencies)
    -- Or if keeping positional:
function module.init(config, monitor_manager, zone_calculator, window_state_manager, placement_strategy, debug_log)
```

---

## 7. State Management

### Current State

State is distributed across multiple modules:

**Window Position State:**
- [window_state_manager.lua](modules/window_state_manager.lua) - In-memory positions (session)
- [window_memory.lua](modules/window_memory.lua) - Persistent positions (cross-session)

**Focus State:**
- [focus_manager.lua:24-30](modules/focus_manager.lua#L24-L30) - Focus cycle state
- [window_state_manager.lua:19-21](modules/window_state_manager.lua#L19-L21) - Zen mode state

**Layout State:**
- [zone_calculator.lua:45-49](modules/zone_calculator.lua#L45-L49) - Zone definitions
- [zone_calculator.lua:43](modules/zone_calculator.lua#L43) - Layout cache
- [resize_manager.lua](modules/resize_manager.lua) - Grid offsets

### Issues

1. **State ownership unclear**: Who owns app_memory? window_state_manager has it, but window_memory uses it
2. **Duplicate state**: `window_state.positions` and `window_memory` cache overlap
3. **State exposed via `._state`**: [window_state_manager.lua:165](modules/window_state_manager.lua#L165)
4. **No single source of truth**: Window position tracked in 3 places

### Recommended Changes

#### 7.1 Clarify State Ownership

**Define clear boundaries:**

```
window_state_manager    → Session state (current window positions)
window_memory          → Historical state (learned preferences)
zone_calculator        → Computed state (geometry, cached)
```

**Remove state leakage:**
```lua
-- Before
window_state_manager._state = window_state  -- Line 165

-- After
-- Remove this, expose only through public API
```

#### 7.2 Consolidate Window Position Tracking

**Current:**
- `window_state.positions[window_id]` - Current position
- `window_state.app_memory[app_name][monitor_id]` - Per-app memory
- `window_memory` persistent cache - Learned positions

**Simplified:**
```lua
-- window_state_manager: Only current positions
positions[window_id] = {monitor_id, zone_key, tile_index}

-- window_memory: Only learned preferences (no duplication)
preferences[app_name][monitor_id] = {zone_key, tile_index, confidence}
```

Remove `app_memory` from window_state_manager (lines 15-16, 43-52), delegate to window_memory.

#### 7.3 Centralize Zen Mode State

**Current:** Zen mode state in [window_state_manager.lua:19-21](modules/window_state_manager.lua#L19-L21)

**Issue:** Not related to window position state, adds mixed responsibility

**Solution:** Move to dedicated module or tiler.lua:
```lua
-- modules/zen_mode.lua
local zen_mode = {
    active = false,
    hidden_windows = {},
    focused_window = nil
}

function zen_mode.toggle(focused_window)
    -- Implementation from window_actions.lua:446-497
end
```

---

## 8. Debug System

### Current State

Debug system is well-organized in [debug/](debug/) directory:

```
debug/
├── init.lua              -- Entry point, exposes zt_debug
├── config.lua           -- Module-level logging flags
├── logger.lua           -- Centralized logging
├── keystroke_monitor.lua -- Keyboard debugging
└── inspection.lua       -- State inspection
```

### Issues

1. **Debug config separate from main config**: [debug/config.lua](debug/config.lua) vs [config.lua](config.lua)
2. **Module registration required**: Each module calls `debug.create_debug_log("module_name")`
3. **No log rotation**: Logs grow indefinitely
4. **Console-only output**: No file logging option

### Recommended Changes

#### 8.1 Integrate Debug Config

Merge debug settings into main config:

```lua
-- config.lua
config.debug = {
    enabled = true,
    modules = {
        tiler = true,
        window_actions = false,
        -- ...
    },
    log_to_file = false,
    log_path = "~/.config/ZoneTilerWM/logs"
}
```

Remove [debug/config.lua](debug/config.lua), read from `config.debug`.

#### 8.2 Auto-register Debug Loggers

**Current:**
```lua
local debug = require "debug.init"
local debug_log = debug.create_debug_log("tiler")
```

**Simplified:**
```lua
local debug_log = require("debug").for_module(_NAME or "tiler")
```

Benefits:
- Automatic module name detection
- Less boilerplate
- Consistent across all modules

#### 8.3 Add Log Output Options

```lua
-- debug/logger.lua
function logger.configure(options)
    logger.outputs = {
        console = options.console or true,
        file = options.file or false,
        alert = options.alert or false,  -- For critical errors
    }
end
```

---

## 9. Testing Infrastructure

### Current State

Test suite exists in [tests/](tests/) directory:

```
tests/
├── test_runner.lua           -- Test harness
├── test_storage.lua          -- Storage tests
├── test_window_memory.lua    -- Window memory tests
├── test_config_validator.lua -- Config validation tests
└── mock_hs.lua              -- Hammerspoon API mocks
```

### Issues

1. **Limited coverage**: Only 3 modules tested (storage, window_memory, config_validator)
2. **No CI integration**: Tests must be run manually
3. **Mock maintenance**: [mock_hs.lua](tests/mock_hs.lua) requires updates when Hammerspoon API changes
4. **No test organization**: All tests in single directory

### Recommended Changes

#### 9.1 Expand Test Coverage

**Priority modules to test:**
- zone_calculator (geometry calculations)
- placement_strategy (tile selection logic)
- window_state_manager (state tracking)
- monitor_manager (UUID management)

**Create test directory structure:**
```
tests/
├── unit/              -- Pure logic tests
│   ├── zone_calculator_test.lua
│   ├── placement_strategy_test.lua
│   └── ...
├── integration/       -- Multi-module tests
│   └── window_placement_test.lua
├── fixtures/          -- Test data
│   └── sample_configs.lua
├── mocks/             -- Mock objects
│   └── hammerspoon.lua
└── test_runner.lua
```

#### 9.2 Add Test Utilities

```lua
-- tests/test_utils.lua
function test_utils.create_mock_window(props)
    return {
        id = props.id or 1,
        isStandard = function() return true end,
        isMinimized = function() return false end,
        screen = function() return props.screen end,
        -- ...
    }
end

function test_utils.create_mock_screen(props)
    return {
        name = function() return props.name or "Test Screen" end,
        frame = function() return props.frame or {x=0, y=0, w=1920, h=1080} end,
        -- ...
    }
end
```

#### 9.3 Document Test Running

Add [tests/README.md](tests/README.md):

```markdown
# Running Tests

## All Tests
```bash
cd ~/.hammerspoon
lua tests/test_runner.lua
```

## Single Test
```bash
lua tests/test_storage.lua
```

## Expected Output
- ✓ Passing tests: Green checkmarks
- ✗ Failing tests: Red X with details
```

---

## 10. Documentation

### Current State

Documentation exists in [docs/](docs/) directory:

```
docs/
├── ARCHITECTURE.md          -- System design
├── CONTRIBUTING.md          -- Development guide
├── keyboard_shortcuts.md    -- Keyboard reference
├── SPACES_RESEARCH.md       -- macOS Spaces notes
├── GEMINI.md               -- AI assistant guide
└── README.md               -- Docs index
```

### Issues

1. **Inline docs inconsistent**: Some modules heavily commented, others minimal
2. **API docs missing**: No function signature documentation format
3. **Examples scattered**: Code examples in comments, not extractable
4. **Outdated sections**: Some docs reference old patterns

### Recommended Changes

#### 10.1 Standardize Inline Documentation

Use LDoc-compatible format consistently:

```lua
--- Moves a window to a specified zone.
-- This function validates the window, calculates the best tile using
-- the placement strategy, and applies the frame to the window.
--
-- @param window hs.window The window object to move
-- @param zone_key string The target zone identifier (e.g., "h", "j", "k")
-- @return boolean True if successful, false otherwise
-- @usage tiler.move_window_to_zone(win, "h")
function window_actions.move_window_to_zone(window, zone_key)
    -- Implementation
end
```

**Benefits:**
- Extractable documentation (can generate HTML/markdown)
- IDE integration (auto-completion hints)
- Consistent format across all modules

#### 10.2 Add Module-Level Documentation

Each module should have header documentation:

```lua
--- Window Actions Module
-- @module window_actions
-- @description Core window manipulation functions for applying frames,
-- moving windows between monitors, and handling special applications.
-- @dependencies monitor_manager, zone_calculator, window_state_manager
-- @author ZoneTilerWM
```

#### 10.3 Create API Reference

Generate API reference from inline docs:

```
docs/
├── api/
│   ├── tiler.md
│   ├── window_actions.md
│   ├── zone_calculator.md
│   └── ...
└── generate_api_docs.lua   -- Script to extract docs
```

---

## 11. Performance Optimizations

### Current State

Performance is generally good, but there are optimization opportunities:

**Identified Hotspots:**
1. [focus_manager.lua:84-88](modules/focus_manager.lua#L84-L88) - Iterates all windows for every zone check
2. [zone_calculator.lua:339-399](modules/zone_calculator.lua#L339-L399) - Recalculates tiles on every call (cache helps but could be better)
3. [smart_placer.lua:63-69](modules/smart_placer.lua#L63-L69) - Creates window filter on every placement attempt

### Recommended Changes

#### 11.1 Cache Window Lists

**Current:**
```lua
-- focus_manager.lua:84
for _, win in ipairs(hs_window.allWindows()) do
    -- Called every cycle
end
```

**Optimized:**
```lua
-- Create persistent filter
local window_cache = hs.window.filter.new():setDefaultFilter({
    allowScreens = true,
    rejectTitles = {""},
})

-- Use cached list
for _, win in ipairs(window_cache:getWindows()) do
    -- Faster
end
```

#### 11.2 Lazy Zone Initialization

**Current:** Zones calculated immediately on screen change
**Optimized:** Calculate zones only when first accessed per monitor

```lua
function zone_calculator.get(monitor_id, zone_key)
    if not zones.by_monitor[monitor_id] then
        -- Lazy init
        local screen = monitor_manager.get_screen(monitor_id)
        if screen then
            zone_calculator.create_for_monitor(monitor_id, screen)
        end
    end
    return zones.by_monitor[monitor_id][zone_key]
end
```

#### 11.3 Reduce Geometry Recalculations

**Current:** Tile frames recalculated on every window move
**Optimized:** Invalidate cache only when screen/grid changes

```lua
-- Add cache invalidation tracking
local geometry_cache_version = 0

function zone_calculator.clear_all()
    zones.by_monitor = {}
    geometry_cache_version = geometry_cache_version + 1
end

-- Check cache version before recalc
```

---

## 12. File Organization

### Current Structure

```
ZoneTilerWM/
├── init.lua                    -- Entry point
├── config.lua                  -- Monolithic config
├── modules/                    -- All business logic (18 files)
├── debug/                      -- Debug system (5 files)
├── tests/                      -- Test suite (5 files)
└── docs/                       -- Documentation (6 files)
```

### Issues

1. **Flat modules directory**: 18 files with no subcategories
2. **Mixed concerns in modules/**: Core tiling logic + utilities + features
3. **No src/ directory**: Common Lua convention not followed

### Recommended Changes

#### 12.1 Organize Modules by Domain

```
ZoneTilerWM/
├── init.lua
├── config/                     -- Broken-down config
│   ├── init.lua
│   ├── keys.lua
│   ├── tiler/
│   └── ...
├── src/                        -- Main source
│   ├── core/                   -- Core tiling engine
│   │   ├── tiler.lua
│   │   ├── window_actions.lua
│   │   ├── zone_calculator.lua
│   │   ├── monitor_manager.lua
│   │   └── window_state_manager.lua
│   ├── focus/                  -- Focus management
│   │   ├── focus_manager.lua
│   │   └── focus_cycle.lua     -- Extracted from focus_manager
│   ├── placement/              -- Window placement
│   │   ├── smart_placer.lua
│   │   ├── placement_strategy.lua
│   │   └── placement_pipeline.lua  -- New
│   ├── persistence/            -- State persistence
│   │   ├── window_memory.lua
│   │   ├── layout_manager.lua
│   │   └── storage.lua
│   ├── features/               -- Optional features
│   │   ├── pomodoro.lua
│   │   ├── app_switcher.lua
│   │   ├── audio_switcher.lua
│   │   └── zen_mode.lua        -- Extracted
│   ├── ui/                     -- UI components
│   │   ├── grid_overlay.lua
│   │   └── resize_manager.lua
│   └── utils/                  -- Utilities
│       ├── lru_cache.lua
│       ├── config_validator.lua
│       ├── error_handler.lua   -- New
│       └── window_utils.lua    -- New
├── debug/
├── tests/
└── docs/
```

**Migration path:**
1. Create new directory structure
2. Move files one domain at a time
3. Update require() paths
4. Test after each domain migration

#### 12.2 Create Index Files

Add index files for easier imports:

```lua
-- src/core/init.lua
return {
    tiler = require("src.core.tiler"),
    window_actions = require("src.core.window_actions"),
    zone_calculator = require("src.core.zone_calculator"),
    -- ...
}

-- Usage in init.lua
local core = require("src.core")
core.tiler.start()
```

---

## 13. Implementation Priority

### Phase 1 - Quick Wins (Low Risk, High Impact)

**Week 1:**
1. ✅ Standardize error handling (Section 3.1)
2. ✅ Extract common utilities (Section 4.3, 4.2)
3. ✅ Add naming conventions (Section 6)
4. ✅ Improve inline documentation (Section 10.1)

**Estimated Effort:** 8-12 hours
**Risk:** Low (additive changes, no breaking changes)

### Phase 2 - Structural Improvements (Medium Risk)

**Week 2-3:**
1. ✅ Split configuration files (Section 2.1)
2. ✅ Refactor complex functions (Section 5)
3. ✅ Consolidate state management (Section 7.2)
4. ✅ Standardize module initialization (Section 1.1)

**Estimated Effort:** 20-30 hours
**Risk:** Medium (requires testing, potential for regressions)

### Phase 3 - Architecture Changes (Higher Risk)

**Week 4-5:**
1. ✅ Reorganize file structure (Section 12.1)
2. ✅ Remove circular dependencies (Section 1.2)
3. ✅ Expand test coverage (Section 9.1)
4. ✅ Performance optimizations (Section 11)

**Estimated Effort:** 30-40 hours
**Risk:** Higher (major refactoring, comprehensive testing needed)

### Phase 4 - Polish & Documentation

**Week 6:**
1. ✅ Generate API documentation (Section 10.3)
2. ✅ Add integration tests (Section 9.1)
3. ✅ Update all documentation
4. ✅ Code review and final cleanup

**Estimated Effort:** 10-15 hours
**Risk:** Low (documentation and polish)

---

## 14. Testing Strategy

### Pre-Refactoring

1. **Create baseline tests**: Write tests for current behavior before changes
2. **Document current behavior**: Record expected outputs for key scenarios
3. **Snapshot testing**: Capture current config parsing results

### During Refactoring

1. **Test after each section**: Don't accumulate untested changes
2. **Manual testing checklist**:
   - [ ] Window placement to all zones works
   - [ ] Focus cycling works in all zones
   - [ ] Monitor switching preserves window positions
   - [ ] Screen change repositions windows correctly
   - [ ] Config reload works without errors
   - [ ] All hotkeys function correctly

### Post-Refactoring

1. **Regression testing**: Verify all baseline tests still pass
2. **Performance testing**: Measure before/after performance
3. **Soak testing**: Run for 24+ hours under normal usage

---

## 15. Risk Mitigation

### Backup Strategy

```bash
# Before starting refactoring
git tag pre-refactoring-backup
git push origin pre-refactoring-backup

# Create refactoring branch
git checkout -b refactoring/cleanup-$(date +%Y%m%d)
```

### Incremental Approach

- ✅ One section at a time
- ✅ Commit after each completed section
- ✅ Tag stable points for rollback
- ✅ Keep main branch stable

### Rollback Plan

If issues arise:
```bash
# Revert to last stable point
git checkout pre-refactoring-backup

# Or revert specific commits
git revert <commit-hash>
```

---

## 16. Success Metrics

### Code Quality Metrics

**Before Refactoring:**
- Total LOC: ~4,387
- Average function length: ~25 lines
- Max function complexity: 177 lines ([focus_manager.lua:156-332](modules/focus_manager.lua#L156-L332))
- Test coverage: ~15% (3 modules)

**After Refactoring (Goals):**
- Total LOC: ~4,000 (-10% through deduplication)
- Average function length: <20 lines
- Max function complexity: <80 lines
- Test coverage: >50% (9+ modules)

### Maintainability Metrics

- ✅ All modules use same initialization pattern
- ✅ All modules have inline documentation
- ✅ No functions longer than 100 lines
- ✅ No circular dependencies
- ✅ Config split into <100 line files

### Performance Metrics

- ✅ Window placement: <50ms (current ~30ms)
- ✅ Focus cycling: <30ms (current ~40ms)
- ✅ Config reload: <200ms (current ~150ms)

---

## 17. Summary of Key Recommendations

### Must Do (Critical)

1. **Standardize initialization** (Section 1.1) - Reduces confusion and errors
2. **Split config.lua** (Section 2.1) - Improves maintainability
3. **Extract utilities** (Section 4) - Reduces duplication
4. **Refactor complex functions** (Section 5) - Improves testability

### Should Do (High Value)

5. **Improve error handling** (Section 3) - Better user experience
6. **Consolidate state** (Section 7) - Clearer ownership
7. **Expand tests** (Section 9.1) - Confidence in changes
8. **Standardize documentation** (Section 10.1) - Easier onboarding

### Nice to Have (Lower Priority)

9. **Reorganize files** (Section 12.1) - Better organization
10. **Performance optimizations** (Section 11) - Already fast enough
11. **Remove circular deps** (Section 1.2) - Current pattern works
12. **Generate API docs** (Section 10.3) - Long-term benefit

---

## 18. Conclusion

The ZoneTilerWM codebase is well-architected with good separation of concerns. The proposed refactoring focuses on:

1. **Consistency**: Standardizing patterns across all modules
2. **Simplicity**: Reducing complexity and duplication
3. **Clarity**: Improving naming, documentation, and organization
4. **Testability**: Making code easier to test and verify

All changes maintain existing functionality while improving code quality and maintainability. The incremental approach ensures stability throughout the refactoring process.

**Estimated Total Effort:** 70-100 hours over 6 weeks
**Expected Benefits:**
- 10% reduction in code size
- 3x improvement in test coverage
- Improved onboarding time for new developers
- Easier to add new features
- Reduced maintenance burden

---

## Appendix A: Module Dependency Graph

```
Current Dependencies:

init.lua
├── config.lua
├── debug/init.lua
├── modules/pomodoor.lua
├── modules/tiler.lua
│   ├── modules/monitor_manager.lua
│   ├── modules/zone_calculator.lua
│   │   └── modules/lru_cache.lua
│   ├── modules/window_state_manager.lua
│   ├── modules/smart_placer.lua
│   ├── modules/focus_manager.lua
│   ├── modules/window_actions.lua
│   │   └── modules/placement_strategy.lua
│   └── modules/grid_overlay.lua
├── modules/app_switcher.lua
├── modules/window_memory.lua
│   └── modules/storage.lua
├── modules/audio_switcher.lua
└── modules/layout_manager.lua
```

## Appendix B: File Size Distribution

```
Largest Files (>300 lines):
1. tiler.lua                 - 582 lines
2. window_actions.lua        - 525 lines
3. zone_calculator.lua       - 463 lines
4. window_memory.lua         - 456 lines
5. focus_manager.lua         - 405 lines
6. config.lua               - 393 lines
7. lru_cache.lua            - 303 lines

Medium Files (150-300 lines):
8. pomodoor.lua             - 233 lines
9. placement_strategy.lua   - 186 lines
10. window_state_manager.lua - 166 lines
11. app_switcher.lua        - 159 lines
12. audio_switcher.lua      - 158 lines
13. layout_manager.lua      - 151 lines

Small Files (<150 lines):
14. smart_placer.lua        - 140 lines
15. grid_overlay.lua        - 116 lines
16. monitor_manager.lua     - 110 lines
17. storage.lua             - 92 lines
18. resize_manager.lua      - 82 lines
19. config_validator.lua    - 60 lines
```

## Appendix C: Configuration Sections

```
config.lua Structure (393 lines):

Section                    Lines    % of File
----------------------------------------
config.tiler              236      60%
config.window_memory       30       8%
config.appCuts            17       4%
config.hyperAppCuts       18       5%
config.pomodoro           17       4%
config.app_switcher       12       3%
config.audio_switcher      8       2%
config.keys                7       2%
config.system_hotkeys      5       1%
config.window_handling     3       1%
config.layout_manager      3       1%
Other (comments, etc.)    37       9%
```

---

*Document Version: 1.0*
*Last Updated: December 13, 2025*
*Author: Architectural Analysis*
