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

local zen_mode_active = false
local zen_hidden_windows = {}
local zen_focused_window = nil

local window_memory_module = nil -- Reference to the window_memory module
local debug_log = function(...)
end -- Placeholder, will be set in init

local zone_calculator = nil

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

-- Get tile for window
function window_state_manager.get_tile(window_id)
    local pos = window_state_manager.get(window_id)
    if not pos then return nil end

    local zone_tiles = zone_calculator.get(pos.monitor_id, pos.zone_key)
    if not zone_tiles or not zone_tiles[pos.tile_index] then
        return nil
    end

    return zone_tiles[pos.tile_index]
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

-- Get all windows in a specific zone
function window_state_manager.get_windows_in_zone(monitor_id, zone_key)
    local windows_in_zone = {}
    for window_id, pos in pairs(window_state.positions) do
        if pos.monitor_id == monitor_id and pos.zone_key == zone_key then
            local win = hs.window.get(window_id)
            if win then
                table.insert(windows_in_zone, win)
            end
        end
    end
    return windows_in_zone
end

function window_state_manager.is_zen_mode_active()
    return zen_mode_active
end

function window_state_manager.activate_zen_mode(hidden_wins, focused_win)
    zen_mode_active = true
    zen_hidden_windows = hidden_wins
    zen_focused_window = focused_win
    debug_log("Zen mode activated, hiding " .. #hidden_wins .. " windows.")
end

function window_state_manager.deactivate_zen_mode()
    zen_mode_active = false
    local previously_hidden = zen_hidden_windows
    local previously_focused = zen_focused_window
    zen_hidden_windows = {}
    zen_focused_window = nil
    debug_log("Zen mode deactivated.")
    return previously_hidden, previously_focused
end

-- Initialize the module
function window_state_manager.init(wm, zc, log_func)
    debug_log = log_func or debug_log
    window_memory_module = wm -- Can be nil initially
    zone_calculator = zc
    debug_log("WindowStateManager initialized")
end

-- Expose internal state for external modules like window_memory if needed
window_state_manager._state = window_state

return window_state_manager