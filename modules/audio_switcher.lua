-- audio_switcher.lua
-- Cycles through a predefined list of audio output devices and triggers a Shortcut.
local hs_audiodevice = hs.audiodevice
local hs_hotkey = hs.hotkey
local hs_application = hs.application
local hs_timer = hs.timer
local hs_applescript = hs.applescript

local audio_switcher = {}

-- Debug logging (centralized)
local debug = require('debug.init')
local debug_log = debug.create_debug_log('audio_switcher')

-- Module state
local config = nil
-- Keep a reference to the watcher in the module table to prevent garbage collection
audio_switcher.device_watcher = nil

-- Log all available output device names
function audio_switcher.log_devices()
    debug_log('--- Available Audio Output Devices ---')
    local all_devices = hs_audiodevice.allOutputDevices()
    for i, device in ipairs(all_devices) do
        debug_log(i .. ": '" .. device:name() .. "' (UID: " .. device:uid() .. ')')
    end
    debug_log('------------------------------------')
end

-- Runs the user-defined shortcut when the audio device changes.
-- Runs the user-defined shortcut when the audio device changes.
local function run_device_change_shortcut()
    if not config or not config.audio_switcher then
        return
    end

    local shortcut_name = config.audio_switcher.shortcut_callback
    if shortcut_name and shortcut_name ~= '' then
        debug_log('Audio Switcher: Triggering shortcut asynchronously via shell task: ' .. shortcut_name)

        -- Bypass Hammerspoon's broken osascript module.
        -- We spawn a background UNIX process. It runs on its own thread and reports back when done.
        local task = hs.task.new("/usr/bin/shortcuts", function(exitCode, stdOut, stdErr)
            if exitCode ~= 0 then
                debug_log("Shortcut background execution failed: " .. tostring(stdErr))
            else
                debug_log("Shortcut background execution completed.")
            end
        end, {"run", shortcut_name})

        task:start()
    end
end

-- Set the default output device by name
local function set_output_device(device)
    if not device then
        debug_log('Audio Switcher: Cannot set a nil device.')
        return
    end

    hs_timer.doAfter(0.1, function()
        local success = device:setDefaultOutputDevice()
        if success then
            debug_log("Audio Switcher: Successfully set output to '" .. device:name() .. "'")
        else
            debug_log("Audio Switcher: FAILED to set output to '" .. device:name() .. "'")
        end
    end)
end

-- Main toggle function for manual cycling
function audio_switcher.toggle()
    debug_log('Audio Switcher: Toggle function called.')
    local configured_devices = config.audio_switcher.devices
    local num_devices = #configured_devices

    if num_devices < 2 then
        debug_log('Audio Switcher: At least two devices must be configured to toggle.')
        return
    end

    local all_devices = hs_audiodevice.allOutputDevices()
    local current_device = hs_audiodevice.defaultOutputDevice()
    local current_name = current_device and current_device:name() or ''

    local current_index = -1
    for i, device_name in ipairs(configured_devices) do
        if device_name == current_name then
            current_index = i
            break
        end
    end

    local next_index
    if current_index == -1 or current_index == num_devices then
        next_index = 1
    else
        next_index = current_index + 1
    end

    local next_device_name = configured_devices[next_index]
    local next_device_obj = nil
    for _, device in ipairs(all_devices) do
        if device:name() == next_device_name then
            next_device_obj = device
            break
        end
    end

    if next_device_obj then
        debug_log("Audio Switcher: Cycling to device: '" .. next_device_name .. "'")
        set_output_device(next_device_obj)
    else
        debug_log("Audio Switcher: Could not find device object for '" .. next_device_name .. "'")
    end
end

-- Callback for device watcher
local function device_watcher_callback(...)
    debug_log('Audio Switcher: Device change detected.')
    run_device_change_shortcut()
end

-- Initialize the module
function audio_switcher.init(cfg, log_fn)
    config = cfg
    debug_log = log_fn or debug_log

    -- Hotkey for manual cycling
    if config and config.audio_switcher and config.audio_switcher.devices and #config.audio_switcher.devices > 0 and
        config.audio_switcher.hotkey then
        local hotkey_config = config.audio_switcher.hotkey

        -- Helper to resolve modifier string to actual modifier array
        local function get_mods(mod_str)
            if type(mod_str) == 'string' and config.keys and config.keys[mod_str] then
                return config.keys[mod_str]
            end
            return mod_str
        end

        local mods = get_mods(hotkey_config[1])
        local key = hotkey_config[2]

        hs_hotkey.bind(mods, key, audio_switcher.toggle)
        debug_log('Audio Switcher: Manual cycling hotkey enabled (' ..
                      (type(mods) == 'table' and table.concat(mods, '+') or tostring(mods)) .. ' + ' .. key .. ')')
    else
        debug_log('Audio Switcher: Manual cycling not configured or disabled.')
    end

    -- Device change watcher
    if config and config.audio_switcher and config.audio_switcher.shortcut_callback then
        audio_switcher.device_watcher = hs_audiodevice.watcher
        audio_switcher.device_watcher.setCallback(device_watcher_callback)
        audio_switcher.device_watcher.start()
        debug_log('Audio Switcher: Device change watcher started.')

        -- Immediately run shortcut on startup
        run_device_change_shortcut()
    else
        debug_log('Audio Switcher: `config.audio_switcher.shortcut_callback` not configured. Watcher not started.')
    end

    debug_log('Audio Switcher initialized.')
end

function audio_switcher.stop()
    if audio_switcher.device_watcher then
        audio_switcher.device_watcher.stop()
        audio_switcher.device_watcher = nil
        debug_log('Audio Switcher: Watcher stopped.')
    end
end

return audio_switcher
