-- window_state_manager.lua
-- Tracks the tiler-specific state of windows and remembers app positions.
local hs_window = hs.window

local window_state_manager = {}

-- Module state
local window_state = {
    -- window_id -> {monitor_id, zone_key, tile_index}
    positions = {},

    -- app_name -> monitor_id -> {zone_key, tile_index}
    app_memory = {}
}

local window_memory_module = nil -- Reference to the window_memory module
local debug_log = function(...)
end -- Placeholder, will be set in init

-- Set window position
function window_state_manager.set(window_id, monitor_id, zone_key, tile_index)
    window_state.positions[window_id] = {
        monitor_id = monitor_id,
        zone_key = zone_key,
        tile_index = tile_index
    }
    -- App memory update
    local window = hs_window.get(window_id)
    if window then
        local app_name = window:application():name()
        if not window_state.app_memory[app_name] then
            window_state.app_memory[app_name] = {}
        end
        window_state.app_memory[app_name][monitor_id] = {
            zone_key = zone_key,
            tile_index = tile_index
        }

        -- Notify window_memory if available
        if window_memory_module and window_memory_module.on_window_positioned then
            window_memory_module.on_window_positioned(window, monitor_id, zone_key, tile_index)
        end
    end
end

-- Get window position
function window_state_manager.get(window_id)
    return window_state.positions[window_id]
end

-- Get remembered position for app on monitor
function window_state_manager.get_app_memory(app_name, monitor_id)
    return window_state.app_memory[app_name] and window_state.app_memory[app_name][monitor_id]
end

-- Clean up window state
function window_state_manager.cleanup(window_id)
    debug_log("Cleaning up window state for ID:", window_id)
    window_state.positions[window_id] = nil
    -- Note: App memory is not cleaned up here, it persists until overwritten or app is excluded.
end

-- Set the window_memory module reference
function window_state_manager.set_window_memory_module(wm)
    window_memory_module = wm
    debug_log("WindowMemory module reference set in WindowStateManager")
end

-- Initialize the module
function window_state_manager.init(wm, log_func)
    debug_log = log_func or debug_log
    window_memory_module = wm -- Can be nil initially
    debug_log("WindowStateManager initialized")
end

-- Expose internal state for external modules like window_memory if needed
window_state_manager._state = window_state

return window_state_manager
