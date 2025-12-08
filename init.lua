-- Hammerspoon configuration
local config = require "config"
local config_validator = require "modules.config_validator"

-- Load modules
local pom = require "modules.pomodoor"
local tiler = require "modules.tiler"
local appSwitcher = require "modules.app_switcher"
local window_memory = require "modules.window_memory"
local audio_switcher = require "modules.audio_switcher"
local layout_manager = require "modules.layout_manager"

-- Get key combinations from config
local mash = config.keys.mash
local mash_app = config.keys.mash_app
local mash_shift = config.keys.mash_shift
local HYPER = config.keys.HYPER

--[[
  Initializes custom keybindings
]]
local function init_custom_binding()
    -- Window hints shortcut
    hs.hotkey.bind(HYPER, '-', hs.hints.windowHints)

    -- Pomodoro bindings - using function wrappers to avoid errors
    hs.hotkey.bind(mash, '9', function()
        pom.enable()
    end)
    hs.hotkey.bind(mash, '0', function()
        pom.disable()
    end)
    hs.hotkey.bind(mash_shift, '0', function()
        pom.reset_work()
    end)

    -- Activity Monitor shortcut
    hs.hotkey.bind(HYPER, "=", function()
        appSwitcher.toggle_app("Activity Monitor")
    end)

    -- Hot reload configuration
    hs.hotkey.bind(mash_shift, "R", function()
        hs.reload()
        hs.alert.show("Config reloaded!")
    end)
end

--[[
  Debug keystroke monitor - logs ALL keystrokes with modifiers and keyboard type
  Uncomment the function call in init() to enable debugging
]]
--[[
local function init_keystroke_debug()
    -- Monitor multiple event types to catch function keys in both modes
    local event_types = {
        hs.eventtap.event.types.keyDown,
        hs.eventtap.event.types.systemDefined,
        hs.eventtap.event.types.NSSystemDefined
    }

    local keystroke_tap = hs.eventtap.new(event_types, function(event)
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
            if flags.ctrl then table.insert(mods, "ctrl") end
            if flags.shift then table.insert(mods, "shift") end
            if flags.alt then table.insert(mods, "alt") end
            if flags.cmd then table.insert(mods, "cmd") end
            if flags.fn then table.insert(mods, "fn") end

            local mod_str = #mods > 0 and (table.concat(mods, "+") .. "+") or ""
            local key_str = key or "unknown"

            print(string.format("🎹 KEYSTROKE: %s%s (keycode: %d, kbd_type: %s)",
                mod_str, key_str, keycode, tostring(kbd_type)))

        -- Handle system events (media keys, brightness, etc.)
        elseif event_type == hs.eventtap.event.types.systemDefined or
               event_type == hs.eventtap.event.types.NSSystemDefined then

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
                if flags.ctrl then table.insert(mods, "ctrl") end
                if flags.shift then table.insert(mods, "shift") end
                if flags.alt then table.insert(mods, "alt") end
                if flags.cmd then table.insert(mods, "cmd") end
                if flags.fn then table.insert(mods, "fn") end
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
    print("✓ Keystroke debug monitor started (monitoring all keystrokes)")
end
--]]

--[[
  Main initialization function
]]
local function init()
    print("-------------- Loading Hammerspoon config --------------")

    -- Validate configuration
    local valid, err = config_validator.validate(config)
    if not valid then
        hs.alert.show("Config Error: " .. err, 5)
        print("Config Error: " .. err)
        return -- Stop initialization
    end

    -- Disable animation for speed
    hs.window.animationDuration = 0

    -- Load Spoons
    -- hs.loadSpoon("RoundedCorners")
    -- spoon.RoundedCorners:start()

    -- Initialize simplified tiler
    tiler.start()

    if config.window_memory and config.window_memory.enabled then
        window_memory.init(tiler)
        window_memory.setup_hotkeys() -- Optional, for manual capture/restore
    end

    if config.layout_manager and config.layout_manager.enabled then
        layout_manager.init(tiler)
    end

    -- Initialize app switching
    appSwitcher.init_bindings(config.appCuts, config.hyperAppCuts, mash_app, HYPER)

    -- Initialize audio switcher
    audio_switcher.init(config, print)

    -- Initialize custom keybindings
    init_custom_binding()

    -- Enable keystroke debug monitor (uncomment to debug key events)
    -- init_keystroke_debug()

    print("Hammerspoon configuration loaded successfully!")
end

-- Start the configuration
init()
