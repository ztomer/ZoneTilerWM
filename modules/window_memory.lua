-- window_memory.lua
-- Simple window position memory: load on startup, save on shutdown, auto-position new windows
---@module window_memory
local window_memory = {}
local config = require "modules.config"
local storage = require "modules.storage"

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("window_memory")

-- Module state
local tiler = nil -- Set during initialization
local positions = {} -- app_name -> monitor_id -> {zone_key, tile_index}
local preferences = {} -- app_name -> monitor_id -> zone_key -> tile_index -> count
local pending_learning = {} -- window_id -> { timer, data = {app_name, monitor_id, zone_key, tile_index} }
local save_timer = nil

-- Check if app should be excluded from memory
---@param app_name string
---@return boolean
local function is_excluded_app(app_name)
    if not config.window_memory or not config.window_memory.excluded_apps then
        return false
    end
    for _, excluded in ipairs(config.window_memory.excluded_apps) do
        if app_name == excluded then
            return true
        end
    end
    return false
end

-- Load positions from disk
local function load_positions()
    local data = storage.load("window_positions")

    if data and data.positions then
        -- Convert array back to nested structure
        for _, pos in ipairs(data.positions) do
            if not positions[pos.app_name] then
                positions[pos.app_name] = {}
            end
            positions[pos.app_name][pos.monitor_id] = {
                zone_key = pos.zone_key,
                tile_index = pos.tile_index
            }
        end
        debug_log("Loaded", #data.positions, "cached last positions")

        if data.preferences then
            for _, pref in ipairs(data.preferences) do
                if not preferences[pref.app_name] then
                    preferences[pref.app_name] = {}
                end
                if not preferences[pref.app_name][pref.monitor_id] then
                    preferences[pref.app_name][pref.monitor_id] = {}
                end
                if not preferences[pref.app_name][pref.monitor_id][pref.zone_key] then
                    preferences[pref.app_name][pref.monitor_id][pref.zone_key] = {}
                end
                -- Handle backward compatibility (simple count) vs new stats object
                if type(pref.data) == "table" then
                    preferences[pref.app_name][pref.monitor_id][pref.zone_key][pref.tile_index] = pref.data
                else
                    preferences[pref.app_name][pref.monitor_id][pref.zone_key][pref.tile_index] = {
                        count = pref.count or pref.data or 0,
                        mean_ar = 0,
                        mean_area = 0
                    }
                end
            end
            debug_log("Loaded", #data.preferences, "cached preferences")
        else
            debug_log("No preferences found in cache file")
        end
    else
        debug_log("No valid cache data found")
    end
end

-- Capture the current state of all tiled windows into the `positions` memory table
local function capture_current_positions()

    -- Clear existing positions and rebuild from current state
    positions = {}

    -- Collect current positions from tiler's window state.
    -- Use get_all_visible_info() so we can read app_name from the cache instead of
    -- hitting the AX API via window:application():name() for every window.
    local window_cache = require("modules.window_cache")
    local all_info = window_cache.get_all_visible_info()
    for _, info in ipairs(all_info) do
        local app_name = info.app_name
        if app_name and not is_excluded_app(app_name) then
            local window_id = info.window:id()
            local pos = tiler.window_state.get(window_id)
            if pos and pos.zone_key and pos.tile_index then
                if not positions[app_name] then
                    positions[app_name] = {}
                end
                positions[app_name][pos.monitor_id] = {
                    zone_key = pos.zone_key,
                    tile_index = pos.tile_index
                }
            end
        end
    end

end

-- Save the current `positions` and `preferences` tables to disk
local function save_memory_to_disk()
    -- Convert to array for JSON
    local positions_array = {}
    for app_name, monitors in pairs(positions) do
        for monitor_id, position in pairs(monitors) do
            table.insert(positions_array, {
                app_name = app_name,
                monitor_id = monitor_id,
                zone_key = position.zone_key,
                tile_index = position.tile_index
            })
        end
    end

    -- Convert preferences to array for JSON
    local preferences_array = {}
    for app_name, monitors in pairs(preferences) do
        for monitor_id, zones in pairs(monitors) do
            for zone_key, tiles in pairs(zones) do
                for tile_index, stats in pairs(tiles) do
                    local entry = {
                        app_name = app_name,
                        monitor_id = monitor_id,
                        zone_key = zone_key,
                        tile_index = tile_index
                    }
                    if type(stats) == "table" then
                        entry.data = stats
                    else
                        entry.count = stats -- Legacy fallback
                    end
                    table.insert(preferences_array, entry)
                end
            end
        end
    end

    -- Save to disk using storage module
    local data = {
        positions = positions_array,
        preferences = preferences_array
    }

    local success, err = storage.save("window_positions", data)
    if success then
        debug_log("Saved", #positions_array, "last positions and", #preferences_array, "preferences to disk")
    else
        debug_log("Failed to save cache file:", err)
    end
end

-- The main save function, which captures and then saves. Used for manual hotkey and shutdown.
local function capture_and_save_positions()
    debug_log("Capturing and saving all window positions...")
    capture_current_positions()
    save_memory_to_disk()
end

-- Get remembered position for app on current monitor
---@param app_name string
---@param monitor_id string
---@return table|nil position {zone_key, tile_index}
function window_memory.get_remembered_position(app_name, monitor_id)
    if is_excluded_app(app_name) then
        return nil
    end

    -- Check for position on the specified monitor
    if positions[app_name] and positions[app_name][monitor_id] then
        return positions[app_name][monitor_id]
    end

    return nil
end

-- Get the most frequently used tile for an app in a specific zone
---@param app_name string
---@param monitor_id string
---@param zone_key string
---@return number|nil tile_index
function window_memory.get_preferred_tile(app_name, monitor_id, zone_key)
    if not preferences[app_name] or not preferences[app_name][monitor_id] or
        not preferences[app_name][monitor_id][zone_key] then
        return nil
    end

    local tile_prefs = preferences[app_name][monitor_id][zone_key]
    local best_tile = nil
    local max_count = -1

    -- Sorted iteration so ties break deterministically (smallest key string wins).
    local tkeys = {}
    for tile_index in pairs(tile_prefs) do tkeys[#tkeys + 1] = tile_index end
    table.sort(tkeys, function(a, b) return tostring(a) < tostring(b) end)
    for _, tile_index in ipairs(tkeys) do
        local stats = tile_prefs[tile_index]
        local count = (type(stats) == "table" and stats.count) or stats
        if count > max_count then
            max_count = count
            best_tile = tile_index
        end
    end

    if best_tile then
        debug_log("Found preferred tile for", app_name, "in zone", zone_key, "on monitor", monitor_id, ": tile",
            best_tile, "(count:", max_count, ")")
    end

    return best_tile
end

-- Get the most frequently used zone for an app on a specific monitor
---@param app_name string
---@param monitor_id string
---@return string|nil zone_key
function window_memory.get_preferred_zone(app_name, monitor_id)
    if not preferences[app_name] or not preferences[app_name][monitor_id] then
        return nil
    end

    local monitor_prefs = preferences[app_name][monitor_id]
    local best_zone = nil
    local max_total_count = -1

    -- Sorted iteration so ties break deterministically (smallest zone key wins).
    local zkeys = {}
    for zone_key in pairs(monitor_prefs) do zkeys[#zkeys + 1] = zone_key end
    table.sort(zkeys)
    for _, zone_key in ipairs(zkeys) do
        local tiles_prefs = monitor_prefs[zone_key]
        local current_zone_total_count = 0
        for _, stats in pairs(tiles_prefs) do
            local count = (type(stats) == "table" and stats.count) or stats
            current_zone_total_count = current_zone_total_count + count
        end

        if current_zone_total_count > max_total_count then
            max_total_count = current_zone_total_count
            best_zone = zone_key
        end
    end

    if best_zone then
        debug_log("Found preferred zone for", app_name, "on monitor", monitor_id, ": zone", best_zone, "(total count:",
            max_total_count, ")")
    end
    return best_zone
end

-- Get a list of preferred positions sorted by frequency (descending)
---@param app_name string
---@param monitor_id string
---@return table list of {zone_key, tile_index, count}
function window_memory.get_ranked_preferences(app_name, monitor_id)
    if not preferences[app_name] or not preferences[app_name][monitor_id] then
        return {}
    end

    local ranked = {}
    local monitor_prefs = preferences[app_name][monitor_id]

    -- Flatten the stats into a list
    for zone_key, tiles_prefs in pairs(monitor_prefs) do
        for tile_index, stats in pairs(tiles_prefs) do
            local count = (type(stats) == "table" and stats.count) or stats
            local mean_ar = (type(stats) == "table" and stats.mean_ar) or 0
            local mean_area = (type(stats) == "table" and stats.mean_area) or 0
            table.insert(ranked, {
                zone_key = zone_key,
                tile_index = tile_index,
                count = count,
                mean_ar = mean_ar,
                mean_area = mean_area
            })
        end
    end

    -- Sort by count descending; total order (zone, then tile string) so ties are
    -- deterministic and portable (table.sort is unstable).
    table.sort(ranked, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.zone_key ~= b.zone_key then return a.zone_key < b.zone_key end
        return tostring(a.tile_index) < tostring(b.tile_index)
    end)

    return ranked
end

-- Commits a learned position after a window has "settled"
local function commit_learned_position(app_name, monitor_id, zone_key, tile_index, win_frame, screen_frame)
    if not preferences[app_name] then
        preferences[app_name] = {}
    end
    if not preferences[app_name][monitor_id] then
        preferences[app_name][monitor_id] = {}
    end
    if not preferences[app_name][monitor_id][zone_key] then
        preferences[app_name][monitor_id][zone_key] = {}
    end

    local stats = preferences[app_name][monitor_id][zone_key][tile_index]

    -- Initialize if new or legacy number
    if not stats or type(stats) ~= "table" then
        stats = {
            count = (tonumber(stats) or 0),
            mean_ar = 0,
            mean_area = 0
        }
    end

    -- Calculate new geometrics
    local new_ar = 0
    local new_area_ratio = 0

    if win_frame and win_frame.w > 0 and win_frame.h > 0 and screen_frame and screen_frame.w > 0 then
        new_ar = win_frame.w / win_frame.h
        new_area_ratio = (win_frame.w * win_frame.h) / (screen_frame.w * screen_frame.h)
    end

    -- Update running averages
    local n = stats.count
    stats.mean_ar = ((stats.mean_ar * n) + new_ar) / (n + 1)
    stats.mean_area = ((stats.mean_area * n) + new_area_ratio) / (n + 1)
    stats.count = n + 1

    preferences[app_name][monitor_id][zone_key][tile_index] = stats

    debug_log("Learned (settled)", app_name, "on", monitor_id, zone_key .. ":" .. tile_index,
        string.format("(Count: %d, AR: %.2f, Area: %.2f)", stats.count, stats.mean_ar, stats.mean_area))
end

-- Called by tiler when a window is positioned
---@param window hs.window
---@param monitor_id string
---@param zone_key string
---@param tile_index number
function window_memory.on_window_positioned(window, monitor_id, zone_key, tile_index)
    if not window or not window:isStandard() then
        return
    end

    local app_name = window:application():name()
    if is_excluded_app(app_name) then
        return
    end

    -- Immediately store the last known position for instant recall (e.g., moving between monitors)
    if not positions[app_name] then
        positions[app_name] = {}
    end
    positions[app_name][monitor_id] = {
        zone_key = zone_key,
        tile_index = tile_index
    }
    debug_log("Remembered last position for", app_name, "on monitor", monitor_id, "zone:", zone_key, "tile:", tile_index)

    -- --- DELAYED LEARNING LOGIC ---
    local window_id = window:id()

    -- If there's a pending learning timer for this window, cancel it. This prevents learning intermediate cycle positions.
    if pending_learning[window_id] and pending_learning[window_id].timer then
        pending_learning[window_id].timer:stop()
        pending_learning[window_id].timer = nil
    end

    -- Set up a new pending learning event.
    pending_learning[window_id] = {
        data = {
            app_name = app_name,
            monitor_id = monitor_id,
            zone_key = zone_key,
            tile_index = tile_index,
            win_frame = window:frame(),
            screen_frame = window:screen():frame()
        }
    }

    -- Start a new timer. When it fires, it will commit the learning.
    local settle_delay = config.window_memory.settle_delay_sec or 2.0
    if settle_delay > 0 then
        pending_learning[window_id].timer = hs.timer.doAfter(settle_delay, function()
            local learn_data = pending_learning[window_id] and pending_learning[window_id].data
            if learn_data then
                commit_learned_position(learn_data.app_name, learn_data.monitor_id, learn_data.zone_key,
                    learn_data.tile_index, learn_data.win_frame, learn_data.screen_frame)
                pending_learning[window_id] = nil
            end
        end)
    end
end

-- Check if window should be positioned (called by tiler)
---@param window hs.window
---@return boolean
function window_memory.should_position_window(window)
    if not window or not window:isStandard() then
        return false
    end

    local app_name = window:application():name()
    return not is_excluded_app(app_name)
end

-- Save all window positions (for hotkey)
---@return number count
function window_memory.save_all_positions()
    debug_log("Manually capturing and saving all window positions")
    capture_and_save_positions()
    local count = 0
    for app_name, monitors in pairs(positions) do
        for _, _ in pairs(monitors) do
            count = count + 1
        end
    end
    debug_log("Saved positions for", count, "app/monitor combinations")
    return count
end

-- Restore all remembered positions (for hotkey)
---@return number count
function window_memory.restore_all_positions()
    debug_log("Restoring all window positions")
    local count = 0

    -- Use cached info entries to avoid per-window AX calls for app_name and screen.
    -- We still need the live hs.screen object (for tiler.monitors.get_id) — look it
    -- up once by cached screen_id rather than calling window:screen() repeatedly.
    local window_cache = require("modules.window_cache")
    local all_info = window_cache.get_all_visible_info()
    for _, info in ipairs(all_info) do
        local app_name = info.app_name
        if app_name and not is_excluded_app(app_name) then
            local window = info.window
            local screen = window:screen() -- required: monitor_manager.get_id needs the hs.screen object
            if screen then
                local monitor_id = tiler.monitors.get_id(screen)
                local remembered = window_memory.get_remembered_position(app_name, monitor_id)

                if remembered then
                    debug_log("Restoring", app_name, "to zone:", remembered.zone_key, "tile:", remembered.tile_index)
                    if tiler.position_window_from_memory(window, monitor_id, remembered.zone_key, remembered.tile_index) then
                        count = count + 1
                    end
                end
            end
        end
    end

    debug_log("Restored positions for", count, "windows")
    return count
end

-- Set up hotkeys
function window_memory.setup_hotkeys()
    if not config.window_memory or not config.window_memory.hotkeys then
        debug_log("No hotkey configuration found")
        return
    end

    -- Helper to resolve modifier string to actual modifier array
    local function get_mods(mod_str)
        if type(mod_str) == "string" and config.keys and config.keys[mod_str] then
            return config.keys[mod_str]
        end
        return mod_str
    end

    -- Capture hotkey
    if config.window_memory.hotkeys.capture then
        local mods = get_mods(config.window_memory.hotkeys.capture[1])
        local key = config.window_memory.hotkeys.capture[2]
        if key and mods then
            hs.hotkey.bind(mods, key, function()
                local count = window_memory.save_all_positions()
                hs.alert.show("Captured " .. count .. " window positions")
            end)
            debug_log("Set up capture hotkey")
        end
    end

    -- Restore hotkey
    if config.window_memory.hotkeys.restore then
        local mods = get_mods(config.window_memory.hotkeys.restore[1])
        local key = config.window_memory.hotkeys.restore[2]
        if key and mods then
            hs.hotkey.bind(mods, key, function()
                local count = window_memory.restore_all_positions()
                hs.alert.show("Restored " .. count .. " window positions")
            end)
            debug_log("Set up restore hotkey")
        end
    end
end

-- Initialize window memory system
function window_memory.init(cfg)
    -- Update configs
    if cfg.window_memory.settle_delay_sec == nil then
        cfg.window_memory.settle_delay_sec = 2.0
    end
    if cfg.window_memory.save_interval_sec == nil then
        cfg.window_memory.save_interval_sec = 0
    end

    if cfg.window_memory.cache_dir then
        storage.init({
            dir = cfg.window_memory.cache_dir
        })
    else
        storage.init()
    end

    -- Notice: tiler.set_window_memory is DELETED. No more upward dependencies.

    load_positions()

    local save_interval = cfg.window_memory.save_interval_sec
    if save_interval > 0 then
        if save_timer then
            save_timer:stop()
        end
        save_timer = hs.timer.doEvery(save_interval, save_memory_to_disk)
    end

    local existing_callback = hs.shutdownCallback
    hs.shutdownCallback = function()
        capture_and_save_positions()
        if existing_callback then
            existing_callback()
        end
    end

    debug_log("Window memory system initialized")
    return window_memory
end

-- Test/diagnostic seam: serialize the current in-memory state directly (no live
-- window capture). Used by the differential oracle to inspect learned state.
window_memory._save_to_disk = save_memory_to_disk

return window_memory
