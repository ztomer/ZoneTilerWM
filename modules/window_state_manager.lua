--- Manages the state of all tiled windows.
-- This module acts as the single source of truth for the position of each window
-- within the tiling layout. It tracks which zone and tile each window belongs to.
-- It also manages the state for Zen Mode.
-- @module window_state_manager
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

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("window_state_manager")

local window_memory_module = nil -- Reference to the window_memory module
local zone_calculator = nil

--- Records the position of a window within the tiling layout.
-- Also updates the in-memory `app_memory` to remember the last position for an application on a specific monitor.
-- @param window_id (number) The unique ID of the window.
-- @param monitor_id (string) The stable ID of the monitor the window is on.
-- @param zone_key (string) The key of the zone the window is in.
-- @param tile_index (number) The index of the tile the window occupies within the zone.
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

--- Retrieves the stored tiling position of a window.
-- @param window_id (number) The ID of the window.
-- @return (table|nil) The position table `{monitor_id, zone_key, tile_index}` or `nil` if not found.
function window_state_manager.get(window_id)
    return window_state.positions[window_id]
end

--- Retrieves the geometric frame (tile) for a given window ID.
-- @param window_id (number) The ID of the window.
-- @return (table|nil) The tile frame `{x, y, w, h}` or `nil` if the window or tile is not found.
function window_state_manager.get_tile(window_id)
    local pos = window_state_manager.get(window_id)
    if not pos then return nil end

    local zone_tiles = zone_calculator.get(pos.monitor_id, pos.zone_key)
    if not zone_tiles or not zone_tiles[pos.tile_index] then
        return nil
    end

    return zone_tiles[pos.tile_index]
end

--- Retrieves the last known position for an application on a specific monitor.
-- @param app_name (string) The name of the application.
-- @param monitor_id (string) The ID of the monitor.
-- @return (table|nil) The position table `{zone_key, tile_index}` or `nil` if not found.
function window_state_manager.get_app_memory(app_name, monitor_id)
    return window_state.app_memory[app_name] and window_state.app_memory[app_name][monitor_id]
end

--- Removes a window's state from the manager.
-- This is called when a window is destroyed.
-- @param window_id (number) The ID of the window to clean up.
function window_state_manager.cleanup(window_id)
    debug_log("Cleaning up window state for ID:", window_id)
    window_state.positions[window_id] = nil
    -- Note: App memory is not cleaned up here, it persists until overwritten or app is excluded.
end

--- Injects the `window_memory` module as a dependency.
-- @param wm (table) The initialized `window_memory` module.
function window_state_manager.set_window_memory_module(wm)
    window_memory_module = wm
    debug_log("WindowMemory module reference set in WindowStateManager")
end

--- Gets all window objects currently occupying a specific zone.
-- @param monitor_id (string) The ID of the monitor.
-- @param zone_key (string) The key of the zone.
-- @return (table) A list of `hs.window` objects.
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

--- Checks if Zen Mode is currently active.
-- @return (boolean) `true` if Zen Mode is active.
function window_state_manager.is_zen_mode_active()
    return zen_mode_active
end

--- Activates Zen Mode.
-- @param hidden_wins (table) A list of `hs.window` objects that were minimized.
-- @param focused_win (hs.window) The window that will remain visible.
function window_state_manager.activate_zen_mode(hidden_wins, focused_win)
    zen_mode_active = true
    zen_hidden_windows = hidden_wins
    zen_focused_window = focused_win
    debug_log("Zen mode activated, hiding " .. #hidden_wins .. " windows.")
end

--- Deactivates Zen Mode.
-- @return (table) The list of windows that were hidden.
-- @return (hs.window) The window that was originally focused.
function window_state_manager.deactivate_zen_mode()
    zen_mode_active = false
    local previously_hidden = zen_hidden_windows
    local previously_focused = zen_focused_window
    zen_hidden_windows = {}
    zen_focused_window = nil
    debug_log("Zen mode deactivated.")
    return previously_hidden, previously_focused
end

--- Initializes the `window_state_manager` module.
-- @param wm (table) The `window_memory` module (can be nil).
-- @param zc (table) The `zone_calculator` module.
-- @param log_func (function) The logging function to use.
function window_state_manager.init(wm, zc, log_func)
    debug_log = log_func or debug_log
    window_memory_module = wm -- Can be nil initially
    zone_calculator = zc
    debug_log("WindowStateManager initialized")
end

-- Expose internal state for external modules like window_memory if needed
window_state_manager._state = window_state

return window_state_manager