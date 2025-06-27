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
    -- Use the persistent UUID provided by Hammerspoon as the stable key.
    return screen:getUUID()
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
    local monitor_uuid = nil
    -- Find the UUID associated with the logical monitor ID
    for uuid, data in pairs(monitors.registry) do
        if data.logical_id == monitor_id then
            monitor_uuid = uuid
            break
        end
    end

    if monitor_uuid then
        -- Find the active screen object that matches the found UUID.
        -- hs.screen.find() returns the screen object or nil if not found/connected.
        return hs_screen.find(monitor_uuid)
    end

    debug_log("Could not find screen for monitor_id:", monitor_id)
    return nil -- Not found in registry or not currently connected
end

-- Reinitialize monitor registry on screen changes
function monitor_manager.reinitialize_monitors(all_screens, log_func)
    debug_log = log_func or debug_log
    debug_log("Updating monitor registry...")
    -- By not clearing the registry, we preserve logical IDs for monitors that
    -- might be temporarily disconnected. get_id will create new entries for
    -- new monitors and update existing ones for those that are still connected.
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
