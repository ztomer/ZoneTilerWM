--- Keystroke Debug Monitor
-- Comprehensive keyboard event logging for debugging key bindings and function keys
--
-- This module monitors all keyboard events including:
-- - Regular keystrokes with modifiers
-- - System events (media keys, brightness, etc.)
-- - Function keys in both standard and special modes
--
-- Usage:
--   local keystroke_monitor = require("debug.keystroke_monitor")
--   keystroke_monitor.start()
--   keystroke_monitor.stop()
local keystroke_monitor = {}

-- State
local keystroke_tap = nil
local is_running = false

--- Starts the keystroke debug monitor
-- Captures all keyboard events and prints formatted output
function keystroke_monitor.start()
    if is_running then
        print("⚠️  Keystroke monitor is already running")
        return
    end

    -- Monitor multiple event types to catch function keys in both modes
    local event_types = {hs.eventtap.event.types.keyDown, hs.eventtap.event.types.systemDefined,
                         hs.eventtap.event.types.NSSystemDefined}

    keystroke_tap = hs.eventtap.new(event_types, function(event)
        local event_type = event:getType()

        -- Handle regular key events
        if event_type == hs.eventtap.event.types.keyDown then
            local flags = event:getFlags()
            local keycode = event:getKeyCode()
            local key = hs.keycodes.map[keycode]

            -- Get keyboard type
            local kbd_type = event:getProperty(hs.eventtap.event.properties.keyboardEventKeyboardType)

            -- Build modifier string
            local mods = {}
            if flags.ctrl then
                table.insert(mods, "ctrl")
            end
            if flags.shift then
                table.insert(mods, "shift")
            end
            if flags.alt then
                table.insert(mods, "alt")
            end
            if flags.cmd then
                table.insert(mods, "cmd")
            end
            if flags.fn then
                table.insert(mods, "fn")
            end

            local mod_str = #mods > 0 and (table.concat(mods, "+") .. "+") or ""
            local key_str = key or "unknown"

            print(string.format("🎹 KEYSTROKE: %s%s (keycode: %d, kbd_type: %s)", mod_str, key_str, keycode,
                tostring(kbd_type)))

            -- Handle system events (media keys, brightness, etc.)
        elseif event_type == hs.eventtap.event.types.systemDefined or event_type ==
            hs.eventtap.event.types.NSSystemDefined then

            -- Try to extract system event details
            local data = event:systemKey()
            if data then
                local key_str = tostring(data.key or "nil")
                local keycode_str = tostring(data.keyCode or "nil")
                local keyflags_str = tostring(data.keyFlags or "nil")
                local keystate_str = data.down and "down" or "up"

                -- Also check event flags to see if modifiers are present
                local flags = event:getFlags()
                local mods = {}
                if flags.ctrl then
                    table.insert(mods, "ctrl")
                end
                if flags.shift then
                    table.insert(mods, "shift")
                end
                if flags.alt then
                    table.insert(mods, "alt")
                end
                if flags.cmd then
                    table.insert(mods, "cmd")
                end
                if flags.fn then
                    table.insert(mods, "fn")
                end
                local mod_str = #mods > 0 and (" mods=" .. table.concat(mods, "+")) or ""

                print(string.format("🎛️  SYSTEM EVENT: type=%d, key=%s, keyCode=%s, keyFlags=%s, keyState=%s%s",
                    event_type, key_str, keycode_str, keyflags_str, keystate_str, mod_str))
            else
                print(string.format("🎛️  SYSTEM EVENT: type=%d (no data)", event_type))
            end
        end

        -- Don't block the keystroke
        return false
    end)

    keystroke_tap:start()
    is_running = true
    print("✓ Keystroke debug monitor started (monitoring all keystrokes)")
end

--- Stops the keystroke debug monitor
function keystroke_monitor.stop()
    if not is_running then
        print("⚠️  Keystroke monitor is not running")
        return
    end

    if keystroke_tap then
        keystroke_tap:stop()
        keystroke_tap = nil
    end

    is_running = false
    print("✓ Keystroke debug monitor stopped")
end

--- Returns whether the monitor is currently running
-- @return (boolean) true if running, false otherwise
function keystroke_monitor.is_running()
    return is_running
end

return keystroke_monitor
