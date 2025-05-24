-- Simplified Window Memory for Tiler
local window_memory = {}
local config = require "config"
local json = require "hs.json"
local lru_cache = require "modules.lru_cache"

local tiler = nil -- Reference to tiler module

-- Create caches
local cache = {
    -- Cache for window positions by app and monitor
    positions = lru_cache.new(config.tiler.cache_size.positions or 500),
    -- Cache for recent window lookups
    window_info = lru_cache.new(config.tiler.cache_size.window_info or 200)
}

-- Debug logging
local function debug_log(...)
    if window_memory.debug then
        local args = {...}
        local message = table.concat(args, " ")
        print("[WindowMemory] " .. message)
    end
end

-- Get cache key for position storage
local function get_position_key(app_name, monitor_id)
    return app_name .. "_" .. tostring(monitor_id)
end

-- Check if app is excluded
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

-- Get cache filename
local function get_cache_filename()
    local cache_dir = window_memory.cache_dir or (os.getenv("HOME") .. "/.config/tiler")
    return cache_dir .. "/window_positions.json"
end

-- Ensure cache directory exists
local function ensure_cache_dir()
    local cache_dir = window_memory.cache_dir or (os.getenv("HOME") .. "/.config/tiler")
    os.execute("mkdir -p " .. cache_dir)
end

-- Load positions from disk
local function load_positions()
    local filename = get_cache_filename()
    local file = io.open(filename, "r")
    if not file then
        debug_log("No existing cache file")
        return {}
    end

    local content = file:read("*all")
    file:close()

    local success, data = pcall(function()
        return json.decode(content)
    end)

    if success and data then
        debug_log("Loaded", #(data.positions or {}), "cached positions")
        return data.positions or {}
    else
        debug_log("Failed to parse cache file")
        return {}
    end
end

-- Save positions to disk
local function save_positions(positions)
    ensure_cache_dir()
    local filename = get_cache_filename()

    local data = {
        timestamp = os.time(),
        positions = positions
    }

    local json_str = json.encode(data)
    local file = io.open(filename, "w")
    if file then
        file:write(json_str)
        file:close()
        debug_log("Saved", #positions, "positions to cache")
        return true
    else
        debug_log("Failed to save cache file")
        return false
    end
end

-- Remember window position
function window_memory.remember_window(window)
    if not window or not window:isStandard() then
        return false
    end

    local app_name = window:application():name()
    if is_excluded_app(app_name) then
        return false
    end

    local window_id = window:id()
    local position = tiler.get_window_position and tiler.get_window_position(window_id)
    if not position then
        debug_log("Window not in any zone:", app_name)
        return false
    end

    -- Create cache key
    local cache_key = get_position_key(app_name, position.monitor_id)

    -- Store in cache
    local cached_data = {
        zone_key = position.zone_key,
        tile_index = position.tile_index,
        timestamp = os.time()
    }

    cache.positions:set(cache_key, cached_data)

    -- Also update in-memory positions for persistence
    if not window_memory.positions[app_name] then
        window_memory.positions[app_name] = {}
    end
    window_memory.positions[app_name][position.monitor_id] = cached_data

    debug_log("Remembered position for", app_name, "monitor:", position.monitor_id, "zone:", position.zone_key, "tile:",
        position.tile_index)

    return true
end

-- Get remembered position
function window_memory.get_position(app_name, monitor_id)
    local cache_key = get_position_key(app_name, monitor_id)

    -- Try cache first
    local cached = cache.positions:get(cache_key)
    if cached then
        debug_log("Cache hit for", app_name, "on monitor", monitor_id)
        return cached
    end

    -- Fall back to persistent storage
    if window_memory.positions[app_name] then
        local position = window_memory.positions[app_name][monitor_id]
        if position then
            -- Populate cache for next time
            cache.positions:set(cache_key, position)
            return position
        end
    end

    return nil
end

-- Apply remembered position to window
function window_memory.restore_window(window)
    if not window or not window:isStandard() then
        return false
    end

    local app_name = window:application():name()
    if is_excluded_app(app_name) then
        return false
    end

    local screen = window:screen()
    local monitor_id = tiler.get_monitor_id and tiler.get_monitor_id(screen)
    if not monitor_id then
        debug_log("Could not get monitor ID for screen")
        return false
    end

    -- Check for remembered position on this monitor
    local remembered = window_memory.get_position(app_name, monitor_id)
    if remembered then
        debug_log("Restoring", app_name, "to zone:", remembered.zone_key, "tile:", remembered.tile_index)
        if tiler.move_window_to_position then
            return tiler.move_window_to_position(window:id(), monitor_id, remembered.zone_key, remembered.tile_index)
        else
            debug_log("tiler.move_window_to_position not available")
            return false
        end
    end

    -- Try default zone for this app
    if config.window_memory and config.window_memory.app_zones and config.window_memory.app_zones[app_name] then
        local default_zone = config.window_memory.app_zones[app_name]
        debug_log("Using default zone for", app_name, ":", default_zone)
        if tiler.move_window_to_zone then
            return tiler.move_window_to_zone(default_zone)
        else
            debug_log("tiler.move_window_to_zone not available")
            return false
        end
    end

    return false
end

-- Handle new window creation
function window_memory.handle_window_created(window)
    if not window or not window:isStandard() then
        return
    end

    local app_name = window:application():name()
    if is_excluded_app(app_name) then
        return
    end

    debug_log("New window created:", app_name)

    -- Small delay to let window settle
    hs.timer.doAfter(0.1, function()
        if not window:isStandard() then
            return
        end

        -- Try to restore position
        if not window_memory.restore_window(window) then
            -- No remembered position, use auto-tile fallback if configured
            if config.window_memory and config.window_memory.auto_tile_fallback then
                local default_zone = config.window_memory.default_zone or "0"
                debug_log("Auto-tiling", app_name, "to default zone:", default_zone)
                if tiler.move_window_to_zone then
                    tiler.move_window_to_zone(default_zone)
                end
            end
        end

        -- Remember the final position
        hs.timer.doAfter(0.2, function()
            window_memory.remember_window(window)
        end)
    end)
end

-- Handle window moved (with debouncing)
local move_timers = {}
function window_memory.handle_window_moved(window)
    if not window or not window:isStandard() then
        return
    end

    local window_id = window:id()

    -- Cancel existing timer
    if move_timers[window_id] then
        move_timers[window_id]:stop()
    end

    -- Set new timer to remember position after movement stops
    move_timers[window_id] = hs.timer.doAfter(0.5, function()
        window_memory.remember_window(window)
        move_timers[window_id] = nil
    end)
end

-- Save all current window positions
function window_memory.save_all_positions()
    debug_log("Saving all window positions")
    local count = 0

    for _, window in ipairs(hs.window.allWindows()) do
        if window:isStandard() and window_memory.remember_window(window) then
            count = count + 1
        end
    end

    -- Save to disk
    local positions_array = {}
    for app_name, monitors in pairs(window_memory.positions) do
        for monitor_id, position in pairs(monitors) do
            table.insert(positions_array, {
                app_name = app_name,
                monitor_id = monitor_id,
                zone_key = position.zone_key,
                tile_index = position.tile_index,
                timestamp = position.timestamp
            })
        end
    end

    save_positions(positions_array)
    debug_log("Saved positions for", count, "windows")

    return count
end

-- Restore all remembered positions
function window_memory.restore_all_positions()
    debug_log("Restoring all window positions")
    local count = 0

    for _, window in ipairs(hs.window.allWindows()) do
        if window:isStandard() and window_memory.restore_window(window) then
            count = count + 1
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

    -- Capture hotkey
    if config.window_memory.hotkeys.capture then
        local key = config.window_memory.hotkeys.capture[1]
        local mods = config.window_memory.hotkeys.capture[2]
        if key and mods then
            hs.hotkey.bind(mods, key, function()
                local count = window_memory.save_all_positions()
                hs.alert.show("Captured " .. count .. " window positions")
            end)
            debug_log("Set up capture hotkey:", table.concat(mods, "+") .. "+" .. key)
        end
    end

    -- Restore hotkey
    if config.window_memory.hotkeys.restore then
        local key = config.window_memory.hotkeys.restore[1]
        local mods = config.window_memory.hotkeys.restore[2]
        if key and mods then
            hs.hotkey.bind(mods, key, function()
                local count = window_memory.restore_all_positions()
                hs.alert.show("Restored " .. count .. " window positions")
            end)
            debug_log("Set up restore hotkey:", table.concat(mods, "+") .. "+" .. key)
        end
    end
end

-- Initialize window memory
function window_memory.init(tiler_module)
    tiler = tiler_module

    -- Load configuration
    window_memory.debug = config.window_memory and config.window_memory.debug or false
    window_memory.cache_dir = config.window_memory and config.window_memory.cache_dir or
                                  (os.getenv("HOME") .. "/.config/tiler")

    -- Initialize positions cache
    window_memory.positions = {}

    -- Load cached positions from disk
    local cached_positions = load_positions()
    for _, pos in ipairs(cached_positions) do
        if not window_memory.positions[pos.app_name] then
            window_memory.positions[pos.app_name] = {}
        end
        window_memory.positions[pos.app_name][pos.monitor_id] = {
            zone_key = pos.zone_key,
            tile_index = pos.tile_index,
            timestamp = pos.timestamp
        }
    end

    debug_log("Loaded", #cached_positions, "cached positions")

    -- Set up window watchers
    local window_watcher = hs.window.filter.new()
    window_watcher:subscribe(hs.window.filter.windowCreated, window_memory.handle_window_created)
    window_watcher:subscribe(hs.window.filter.windowMoved, window_memory.handle_window_moved)

    -- Set up shutdown callback to save positions
    local existing_callback = hs.shutdownCallback
    hs.shutdownCallback = function()
        window_memory.save_all_positions()
        if existing_callback then
            existing_callback()
        end
    end

    -- Log cache stats periodically if debug is enabled
    if window_memory.debug then
        hs.timer.doEvery(300, function() -- Every 5 minutes
            local stats = cache.positions:stats()
            debug_log(string.format("Cache stats: %d items, %.1f%% hit rate (%d hits, %d misses)", stats.size,
                stats.hit_ratio * 100, stats.hits, stats.misses))
        end)
    end

    debug_log("Window memory initialized")
    return window_memory
end

return window_memory
