-- monitor_manager.lua
-- Manages stable logical IDs for physical monitors.
local hs_screen = hs.screen

local monitor_manager = {}

-- Module state
local monitors = {
    -- Stable monitor IDs that persist across reconnections
    registry = {}, -- monitor_key -> {system_id, name, frame, logical_id, key}
    next_logical_id = 1
}

local debug_log = function(...)
end -- Placeholder, will be set in init

-- Generate stable monitor key from screen properties
local function get_monitor_key(screen)
    local frame = screen:frame()
    local name = screen:name()
    -- Use position + resolution + name for stable identification
    return string.format("%s_%.0f_%.0f_%dx%d", name:gsub("[%s%-]", "_"), frame.x, frame.y, frame.w, frame.h)
end

-- Get or create stable monitor ID
function monitor_manager.get_id(screen)
    local key = get_monitor_key(screen)

    if not monitors.registry[key] then
        monitors.registry[key] = {
            system_id = screen:id(),
            name = screen:name(),
            frame = screen:frame(),
            logical_id = monitors.next_logical_id,
            key = key
        }
        monitors.next_logical_id = monitors.next_logical_id + 1
        debug_log("Registered new monitor:", key, "logical_id:", monitors.registry[key].logical_id)
    else
        -- Update system ID and frame in case it changed (e.g. screen arrangement, resolution)
        monitors.registry[key].system_id = screen:id()
        monitors.registry[key].frame = screen:frame()
        monitors.registry[key].name = screen:name() -- Name might change too
    end

    return monitors.registry[key].logical_id
end

-- Get screen by monitor ID
function monitor_manager.get_screen(monitor_id)
    for _, data in pairs(monitors.registry) do
        if data.logical_id == monitor_id then
            -- Find current screen with this system ID
            for _, screen_obj in ipairs(hs_screen.allScreens()) do
                if screen_obj:id() == data.system_id then
                    return screen_obj
                end
            end
            -- If not found by system_id, try to find by key
            for _, screen_obj in ipairs(hs_screen.allScreens()) do
                if get_monitor_key(screen_obj) == data.key then
                    debug_log("Found monitor", monitor_id, "by key after system_id mismatch. Updating registry.")
                    -- Update the registry with the new system_id
                    monitors.registry[data.key].system_id = screen_obj:id()
                    monitors.registry[data.key].frame = screen_obj:frame()
                    monitors.registry[data.key].name = screen_obj:name()
                    return screen_obj
                end
            end
            debug_log("Could not find screen for monitor_id:", monitor_id, "system_id:", data.system_id)
            return nil
        end
    end
    debug_log("Monitor ID not found in registry:", monitor_id)
    return nil
end

-- Reinitialize monitor registry on screen changes
function monitor_manager.reinitialize_monitors(all_screens, log_func)
    debug_log = log_func or debug_log
    debug_log("Reinitializing monitor registry...")
    monitors.registry = {} -- Clear the old registry
    monitors.next_logical_id = 1
    for _, screen_obj in ipairs(all_screens) do
        monitor_manager.get_id(screen_obj) -- Re-register all currently active monitors
    end
    debug_log("Monitor registry reinitialized.")
end

-- Initialize the module
function monitor_manager.init(log_func)
    debug_log = log_func or debug_log
    debug_log("MonitorManager initialized")
end

-- Expose internal state for external modules like window_memory if needed
monitor_manager._monitors_state = monitors

return monitor_manager
