-- window_memory.lua
-- Simple window position memory: load on startup, save on shutdown, auto-position new windows
local window_memory = {}
local config = require "config"
local json = require "hs.json"

-- Module state
local tiler = nil -- Set during initialization
local positions = {} -- app_name -> monitor_id -> {zone_key, tile_index}
local preferences = {} -- app_name -> monitor_id -> zone_key -> tile_index -> count
local pending_learning = {} -- window_id -> { timer, data = {app_name, monitor_id, zone_key, tile_index} }

-- Debug logging
local function debug_log(...)
    if window_memory.debug then
        local args = {...}
        print("[WindowMemory] " .. table.concat(args, " "))
    end
end

-- Check if app should be excluded from memory
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
    local cache_dir = config.window_memory and config.window_memory.cache_dir or (os.getenv("HOME") .. "/.config/tiler")
    return cache_dir .. "/window_positions.json"
end

-- Ensure cache directory exists
local function ensure_cache_dir()
    local cache_dir = config.window_memory and config.window_memory.cache_dir or (os.getenv("HOME") .. "/.config/tiler")
    os.execute("mkdir -p " .. cache_dir)
end

-- Load positions from disk
local function load_positions()
    local filename = get_cache_filename()
    local file = io.open(filename, "r")
    if not file then
        debug_log("No existing cache file found")
        return
    end

    local content = file:read("*all")
    file:close()

    local success, data = pcall(function()
        return json.decode(content)
    end)

    if success and data and data.positions then
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
                preferences[pref.app_name][pref.monitor_id][pref.zone_key][pref.tile_index] = pref.count
            end
            debug_log("Loaded", #data.preferences, "cached preferences")
        else
            debug_log("No preferences found in cache file")
        end
    else
        debug_log("Failed to parse cache file")
    end
end

-- Save current window positions to disk
local function save_positions()
    debug_log("Saving all window positions...")

    -- Clear existing positions and rebuild from current state
    positions = {}

    -- Collect current positions from tiler's window state
    for _, window in ipairs(hs.window.allWindows()) do
        if window:isStandard() and not window:isMinimized() then
            local app_name = window:application():name()
            if not is_excluded_app(app_name) then
                local window_id = window:id()
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
                for tile_index, count in pairs(tiles) do
                    table.insert(preferences_array, {
                        app_name = app_name,
                        monitor_id = monitor_id,
                        zone_key = zone_key,
                        tile_index = tile_index,
                        count = count
                    })
                end
            end
        end
    end

    -- Save to disk
    ensure_cache_dir()
    local filename = get_cache_filename()
    local data = {
        timestamp = os.time(),
        positions = positions_array,
        preferences = preferences_array
    }

    local json_str = json.encode(data)
    local file = io.open(filename, "w")
    if file then
        file:write(json_str)
        file:close()
        debug_log("Saved", #positions_array, "positions and", #preferences_array, "preferences to disk")
    else
        debug_log("Failed to save cache file")
    end
end

-- Get remembered position for app on current monitor
function window_memory.get_remembered_position(app_name, monitor_id)
    if is_excluded_app(app_name) then
        return nil
    end

    -- Check for position on current monitor first
    if positions[app_name] and positions[app_name][monitor_id] then
        return positions[app_name][monitor_id]
    end

    -- Check for position on any monitor as fallback
    if positions[app_name] then
        for _, position in pairs(positions[app_name]) do
            return position -- Return first found position
        end
    end

    return nil
end

-- Get the most frequently used tile for an app in a specific zone
function window_memory.get_preferred_tile(app_name, monitor_id, zone_key)
    if not preferences[app_name] or not preferences[app_name][monitor_id] or
        not preferences[app_name][monitor_id][zone_key] then
        return nil
    end

    local tile_prefs = preferences[app_name][monitor_id][zone_key]
    local best_tile = nil
    local max_count = -1

    for tile_index, count in pairs(tile_prefs) do
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
function window_memory.get_preferred_zone(app_name, monitor_id)
    if not preferences[app_name] or not preferences[app_name][monitor_id] then
        return nil
    end

    local monitor_prefs = preferences[app_name][monitor_id]
    local best_zone = nil
    local max_total_count = -1

    for zone_key, tiles_prefs in pairs(monitor_prefs) do
        local current_zone_total_count = 0
        for _, count in pairs(tiles_prefs) do
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

-- Commits a learned position after a window has "settled"
local function commit_learned_position(app_name, monitor_id, zone_key, tile_index)
    -- This is the core preference-incrementing logic
    if not preferences[app_name] then
        preferences[app_name] = {}
    end
    if not preferences[app_name][monitor_id] then
        preferences[app_name][monitor_id] = {}
    end
    if not preferences[app_name][monitor_id][zone_key] then
        preferences[app_name][monitor_id][zone_key] = {}
    end
    if not preferences[app_name][monitor_id][zone_key][tile_index] then
        preferences[app_name][monitor_id][zone_key][tile_index] = 0
    end
    preferences[app_name][monitor_id][zone_key][tile_index] =
        preferences[app_name][monitor_id][zone_key][tile_index] + 1

    debug_log("Learned (settled)", app_name, "on monitor", monitor_id, "zone:", zone_key, "tile:", tile_index,
        "(New Count:", preferences[app_name][monitor_id][zone_key][tile_index], ")")
end

-- Called by tiler when a window is positioned
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
            tile_index = tile_index
        }
    }

    -- Start a new timer. When it fires, it will commit the learning.
    local settle_delay_sec = (config.window_memory and config.window_memory.settle_delay_sec) or 2.0
    pending_learning[window_id].timer = hs.timer.doAfter(settle_delay_sec, function()
        -- The timer fired, so the window has "settled".
        local learn_data = pending_learning[window_id] and pending_learning[window_id].data
        if learn_data then
            commit_learned_position(learn_data.app_name, learn_data.monitor_id, learn_data.zone_key,
                learn_data.tile_index)
            pending_learning[window_id] = nil -- Clean up the pending entry
        end
    end)
end

-- Called by tiler when a new window is created
function window_memory.on_window_created(window)
    if not window or not window:isStandard() then
        return
    end

    local app_name = window:application():name()
    if is_excluded_app(app_name) then
        return
    end

    debug_log("New window created:", app_name)

    -- Wait for window to settle, then try to position it
    hs.timer.doAfter(0.3, function() -- Initial delay for window to become stable
        if not window:isStandard() or window:isMinimized() then
            debug_log("Window", app_name, "not standard or minimized after initial delay. Aborting auto-placement.")
            return
        end

        local screen = window:screen()
        if not screen then
            debug_log("Window", app_name, "has no screen after initial delay. Aborting auto-placement.")
            return
        end

        local monitor_id = tiler.monitors.get_id(screen)
        local placed = false

        -- Helper function to attempt placement and set 'placed' flag
        -- This function will be called within the inner timer, after focus.
        local function attempt_placement(placement_type, zone_key, tile_index)
            local success = false
            if zone_key and tiler.move_window_to_zone then -- For preferred zone/app_zones/default_zone
                -- move_window_to_zone handles preferred tile internally
                success = tiler.move_window_to_zone(window, zone_key)
            elseif tile_index and tiler.position_window_from_memory then -- For remembered position
                success = tiler.position_window_from_memory(window, monitor_id, zone_key, tile_index)
            end

            if success then
                debug_log("Successfully auto-placed", app_name, "using", placement_type, "to zone:", zone_key, "tile:",
                    tile_index or "N/A")
                placed = true
            else
                debug_log("Failed to auto-place", app_name, "using", placement_type, "to zone:", zone_key, "tile:",
                    tile_index or "N/A", ". Falling back.")
            end
            return success
        end

        -- Focus the window once before attempting any moves, as some apps require focus for setFrame to work reliably.
        window:focus()

        -- Small delay to ensure focus takes effect before attempting to move the window.
        hs.timer.doAfter(0.1, function()
            if placed then
                return
            end -- If already placed by a previous attempt (e.g., by smart_placer if it runs first, though order is window_memory then smart_placer)

            -- 1. Try learned preferred zone (Phase 2)
            local preferred_zone = window_memory.get_preferred_zone(app_name, monitor_id)
            if preferred_zone then
                debug_log("Attempting auto-placement for", app_name, "to learned preferred zone:", preferred_zone)
                if attempt_placement("learned preferred zone", preferred_zone) then
                    return
                end
            end

            if placed then
                return
            end -- Check again after first attempt

            -- 2. Try remembered last position (Phase 1)
            local remembered = window_memory.get_remembered_position(app_name, monitor_id)
            if remembered then
                debug_log("Attempting auto-placement for", app_name, "to last remembered position:",
                    remembered.zone_key, remembered.tile_index)
                if attempt_placement("remembered last position", remembered.zone_key, remembered.tile_index) then
                    return
                end
            end

            if placed then
                return
            end -- Check again after second attempt

            -- 3. Try configured app zones (existing)
            if config.window_memory and config.window_memory.app_zones then
                local default_zone_from_config = config.window_memory.app_zones[app_name]
                if default_zone_from_config then
                    debug_log("Attempting auto-placement for", app_name, "to configured app_zone:",
                        default_zone_from_config)
                    if attempt_placement("configured app zone", default_zone_from_config) then
                        return
                    end
                end
            end

            if placed then
                return
            end -- Check again after third attempt

            -- 4. Try global default fallback (existing)
            if config.window_memory and config.window_memory.auto_tile_fallback then
                local global_default_zone = config.window_memory.default_zone or "0"
                debug_log("Attempting auto-placement for", app_name, "to global default zone:", global_default_zone)
                attempt_placement("global default zone", global_default_zone) -- No 'return' here, as this is the last fallback.
            end
        end) -- End of inner hs.timer.doAfter(0.1)
    end) -- End of outer hs.timer.doAfter(0.3)
end

-- Check if window should be positioned (called by tiler)
function window_memory.should_position_window(window)
    if not window or not window:isStandard() then
        return false
    end

    local app_name = window:application():name()
    return not is_excluded_app(app_name)
end

-- Save all window positions (for hotkey)
function window_memory.save_all_positions()
    debug_log("Manually saving all window positions")
    save_positions()
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
function window_memory.restore_all_positions()
    debug_log("Restoring all window positions")
    local count = 0

    for _, window in ipairs(hs.window.allWindows()) do
        if window:isStandard() and not window:isMinimized() then
            local app_name = window:application():name()
            if not is_excluded_app(app_name) then
                local screen = window:screen()
                if screen then
                    local monitor_id = tiler.monitors.get_id(screen)
                    local remembered = get_remembered_position(app_name, monitor_id)

                    if remembered then
                        debug_log("Restoring", app_name, "to zone:", remembered.zone_key, "tile:", remembered.tile_index)
                        if tiler.position_window_from_memory(window, monitor_id, remembered.zone_key,
                            remembered.tile_index) then
                            count = count + 1
                        end
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

-- Initialize window memory system
function window_memory.init(tiler_module)
    tiler = tiler_module
    window_memory.debug = config.window_memory and config.window_memory.debug or false

    -- Set up integration with tiler
    tiler.set_window_memory(window_memory)

    -- Load positions from disk
    load_positions()

    -- Save positions on shutdown
    local existing_callback = hs.shutdownCallback
    hs.shutdownCallback = function()
        save_positions()
        if existing_callback then
            existing_callback()
        end
    end

    debug_log("Window memory system initialized")
    return window_memory
end

return window_memory
