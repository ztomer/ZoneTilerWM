-- audio_switcher.lua
-- Cycles through a predefined list of audio output devices and applies SoundSource presets.
local hs_audiodevice = hs.audiodevice
local hs_hotkey = hs.hotkey
local hs_applescript = hs.applescript
local hs_application = hs.application
local hs_timer = hs.timer

local audio_switcher = {}

-- Module state
local config = nil
local debug_log = function(...)
end
local is_soundsource_installed = false
local device_watcher = nil

-- Log all available output device names
function audio_switcher.log_devices()
    debug_log("--- Available Audio Output Devices ---")
    local all_devices = hs.audiodevice.allOutputDevices()
    for i, device in ipairs(all_devices) do
        debug_log(i .. ": '" .. device:name() .. "' (UID: " .. device:uid() .. ")")
    end
    debug_log("------------------------------------")
end

-- Set the SoundSource preset for a given device
local function set_soundsource_preset(device_name)
    if not is_soundsource_installed then
        return -- SoundSource not installed
    end

    if not (config.audio_switcher.soundsource_presets) then
        return -- No presets configured
    end

    local preset_name = config.audio_switcher.soundsource_presets[device_name]
    if preset_name then
        local script = string.format('tell application "SoundSource" to apply preset "%s"', preset_name)
        debug_log("Audio Switcher: Executing AppleScript: " .. script)
        local ok, result, raw = hs.applescript.applescript(script)
        if ok then
            debug_log("Audio Switcher: Successfully applied SoundSource preset '" .. preset_name .. "'")
        else
            debug_log("Audio Switcher: FAILED to apply SoundSource preset. Error: " .. tostring(result))
        end
    end
end

-- Set the default output device by name
local function set_output_device(device)
    if not device then
        debug_log("Audio Switcher: Cannot set a nil device.")
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
    debug_log("Audio Switcher: Toggle function called.")
    local configured_devices = config.audio_switcher.devices
    local num_devices = #configured_devices

    if num_devices < 2 then
        debug_log("Audio Switcher: At least two devices must be configured to toggle.")
        return
    end

    local all_devices = hs.audiodevice.allOutputDevices()
    local current_device = hs.audiodevice.defaultOutputDevice()
    local current_name = current_device and current_device:name() or ""

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
local function handle_device_change(change_type)
    if change_type == "systemDeviceChanged" then
        local new_device = hs.audiodevice.defaultOutputDevice()
        if new_device then
            debug_log("Audio Switcher: Default output device changed to: " .. new_device:name())
            set_soundsource_preset(new_device:name())
        end
    end
end

-- Initialize the module
function audio_switcher.init(cfg, log_fn)
    config = cfg
    debug_log = log_fn or debug_log

    -- Hotkey for manual cycling
    if config and config.audio_switcher and config.audio_switcher.devices and #config.audio_switcher.devices > 0 and
        config.audio_switcher.hotkey then
        local hotkey_config = config.audio_switcher.hotkey
        hs_hotkey.bind(hotkey_config[1], hotkey_config[2], audio_switcher.toggle)
        debug_log("Audio Switcher: Manual cycling hotkey enabled.")
    else
        debug_log("Audio Switcher: Manual cycling not configured or disabled.")
    end

    -- SoundSource preset watcher
    is_soundsource_installed = hs.application.get("SoundSource") ~= nil
    if is_soundsource_installed then
        debug_log("Audio Switcher: SoundSource installation detected.")
        if config and config.audio_switcher and config.audio_switcher.soundsource_presets then
            device_watcher = hs.audiodevice.watcher.new(handle_device_change)
            device_watcher:start()
            debug_log("Audio Switcher: SoundSource preset watcher started.")

            -- Immediately set preset for current device
            local current_device = hs.audiodevice.defaultOutputDevice()
            if current_device then
                set_soundsource_preset(current_device:name())
            end
        else
            debug_log("Audio Switcher: `soundsource_presets` not configured. Watcher not started.")
        end
    else
        debug_log("Audio Switcher: SoundSource not found. Preset functionality will be disabled.")
    end

    debug_log("Audio Switcher initialized.")
end

function audio_switcher.stop()
    if device_watcher then
        device_watcher:stop()
        device_watcher = nil
        debug_log("Audio Switcher: Watcher stopped.")
    end
end

return audio_switcher