# Debug System

This folder contains all debugging functionality for ZoneTilerWM, organized into a clean, modular structure.

## Overview

The debug system provides:

- **Centralized logging** with configurable levels per module
- **Keystroke monitoring** for debugging key bindings
- **Inspection utilities** for examining runtime state
- **Unified configuration** for all debug features

## Quick Start

### Accessing Debug Commands

After loading your Hammerspoon config, debug commands are available via `zt_debug`:

```lua
-- From Hammerspoon console:
zt_debug.help()                    -- Show all available commands
zt_debug.keystroke.start()         -- Start keystroke monitor
zt_debug.inspect.debug_zone("left") -- Inspect a zone
```

### Enabling Debug Logging

Edit `debug/config.lua` to enable/disable debug logging for specific modules:

```lua
debug_config.modules = {
    tiler = true,              -- Enable tiler debug logs
    window_memory = true,      -- Enable window memory debug logs
    space_manager = true,      -- Enable space manager debug logs
    -- ... more modules
}
```

Or enable/disable at runtime:

```lua
zt_debug.enable_module("focus_manager")
zt_debug.disable_module("tiler")
```

## File Structure

```
debug/
├── README.md              # This file
├── init.lua               # Main entry point
├── config.lua             # Debug configuration
├── logger.lua             # Centralized logging system
├── keystroke_monitor.lua  # Keyboard event debugging
└── inspection.lua         # State inspection utilities
```

## Modules

### init.lua

Main entry point for the debug system. Loads all debug modules and provides a unified API.

**Initialization:**

```lua
debug.init(config, tiler, zone_calculator, focus_manager, audio_switcher)
```

**Global access:**

```lua
_G.zt_debug  -- Available in Hammerspoon console
```

### config.lua

Configuration for all debug features.

**Structure:**

```lua
debug_config = {
    keystroke_monitor = { enabled = false },
    logger = { global_level = "DEBUG", ... },
    modules = { tiler = true, ... },
    performance = { enabled = false, ... }
}
```

**Customization:**

- Edit this file to change default debug settings
- Module-specific flags control debug logging per module
- Performance monitoring can track slow operations

### logger.lua

Centralized logging system with multiple log levels.

**Features:**

- Log levels: DEBUG, INFO, WARN, ERROR
- Module-specific enable/disable
- Optional timestamps and module names
- Table inspection with `hs.inspect()`

**Creating a logger:**

```lua
local logger = require("debug.logger")
local log = logger.new("my_module", true)  -- enabled

log("Debug message")
log.info("Info message")
log.warn("Warning message")
log.error("Error message")
```

**Backward compatible:**

```lua
local debug_log = logger.create_debug_log(enabled, "module_name")
debug_log("Old style logging")
```

### keystroke_monitor.lua

Monitors all keyboard events for debugging key bindings.

**Usage:**

```lua
zt_debug.keystroke.start()      -- Start monitoring
zt_debug.keystroke.stop()       -- Stop monitoring
zt_debug.keystroke.is_running() -- Check status
```

**Output example:**

```
🎹 KEYSTROKE: ctrl+shift+f1 (keycode: 122, kbd_type: 41)
🎛️  SYSTEM EVENT: key=17, keyCode=17, keyFlags=2560, keyState=down
```

**Use cases:**

- Find exact keycodes for function keys
- Debug modifier key combinations
- Identify system events (media keys, brightness, etc.)

### inspection.lua

Utilities for inspecting ZoneTilerWM runtime state.

**Available commands:**

```lua
-- Zone inspection
zt_debug.inspect.debug_zone(zone_key)
zt_debug.inspect.debug_zone_tiles([monitor_id], zone_key)
zt_debug.inspect.debug_zone_windows([monitor_id], zone_key)

-- Focus manager
zt_debug.inspect.debug_cycle_state()

-- Audio
zt_debug.inspect.log_audio_devices()

-- Help
zt_debug.inspect.help()
```

**Examples:**

```lua
-- Inspect the "left" zone on current screen
zt_debug.inspect.debug_zone("left")

-- See tile calculations for "center" zone
zt_debug.inspect.debug_zone_tiles(nil, "center")

-- Check focus cycle state
zt_debug.inspect.debug_cycle_state()
```

## Configuration Examples

### Enable All Debug Logging

```lua
-- In debug/config.lua
debug_config.logger.global_level = "DEBUG"

debug_config.modules = {
    tiler = true,
    window_memory = true,
    layout_manager = true,
    -- ... set all to true
}
```

### Enable Only Spaces Debugging

```lua
debug_config.modules = {
    space_manager = true,
    space_menubar = true,
    space_preview = true,
    space_storage = true,
    -- ... all others false
}
```

### Enable Keystroke Monitor on Startup

```lua
debug_config.keystroke_monitor.enabled = true
```

### Add Timestamps to Logs

```lua
debug_config.logger.include_timestamp = true
```

## Runtime Configuration

Change debug settings without editing config files:

```lua
-- Enable/disable modules
zt_debug.enable_module("tiler")
zt_debug.disable_module("window_memory")

-- Change global log level
zt_debug.logger.set_global_level(zt_debug.logger.LEVEL.INFO)

-- Toggle timestamps
zt_debug.logger.enable_timestamps()
zt_debug.logger.disable_timestamps()

-- Toggle module names
zt_debug.logger.enable_module_names()
zt_debug.logger.disable_module_names()
```

## Integration with Modules

Modules use the debug system for logging:

```lua
-- In a module
local debug = require("debug.init")
local log = debug.create_logger("my_module")

function my_function()
    log("This is a debug message")
    log.info("This is info")
    log.warn("This is a warning")
    log.error("This is an error")
end
```

## Performance Monitoring

Enable performance tracking to identify slow operations:

```lua
-- In debug/config.lua
debug_config.performance = {
    enabled = true,
    log_slow_operations = true,
    slow_operation_threshold = 0.1  -- 100ms
}
```

*Note: Performance monitoring is not yet implemented but the config structure is ready.*

## Best Practices

### Development

1. **Use appropriate log levels**
   - `log()` for detailed debug info
   - `log.info()` for important state changes
   - `log.warn()` for potential issues
   - `log.error()` for actual errors

2. **Enable only needed modules**
   - Reduces console noise
   - Easier to find relevant information
   - Better performance

3. **Use inspection commands**
   - Instead of adding temporary print statements
   - Examine state from console without code changes

### Production

1. **Disable debug logging**
   - Set module flags to `false` in `debug/config.lua`
   - Or set global level to `"NONE"`

2. **Keep inspection utilities enabled**
   - Useful for troubleshooting user issues
   - Minimal performance impact when not used

3. **Disable keystroke monitor**
   - Only needed during development
   - Has performance overhead when running

## Troubleshooting

### Debug commands not available

```lua
-- Check if debug system is loaded
print(zt_debug)  -- Should show table

-- If nil, check init.lua initialization
-- Make sure debug.init() is called
```

### No debug output

```lua
-- Check if module is enabled
zt_debug.enable_module("module_name")

-- Check global log level
zt_debug.logger.set_global_level(zt_debug.logger.LEVEL.DEBUG)
```

### Keystroke monitor not working

```lua
-- Check if it's running
print(zt_debug.keystroke.is_running())

-- Start it manually
zt_debug.keystroke.start()

-- Check Hammerspoon accessibility permissions
-- System Preferences > Security & Privacy > Accessibility
```

## Future Enhancements

Planned features for the debug system:

- [ ] Performance profiling with timing measurements
- [ ] Memory usage tracking
- [ ] Debug log file export
- [ ] Visual debug overlays
- [ ] Network request logging (if applicable)
- [ ] Crash reporting and stack traces

## Contributing

When adding new debug features:

1. Add configuration to `debug/config.lua`
2. Create a new file in `debug/` for the feature
3. Export functionality from `debug/init.lua`
4. Update this README with usage examples
5. Add appropriate log levels throughout code

## Related Documentation

- [Main README](../README.md) - Project overview
- [ARCHITECTURE](../docs/ARCHITECTURE.md) - System architecture
- [SPACES_RESEARCH](../docs/SPACES_RESEARCH.md) - Spaces implementation research

## License

Same as ZoneTilerWM - see main LICENSE file.
