--- Manages persistence of Space-related data to disk.
-- This module handles saving and loading Space definitions, layouts, and window
-- positions. It uses JSON for serialization and stores data in the cache directory
-- specified in the configuration.
-- @module space_storage

local space_storage = {}
local json = require("hs.json")

-- Module state
local config = nil
local debug_log = function(...) end -- Placeholder, will be set in init

--- Gets the cache directory path from configuration.
-- Falls back to ~/.config/tiler if not specified.
-- @return (string) The cache directory path.
local function get_cache_dir()
    if config and config.window_memory and config.window_memory.cache_dir then
        return config.window_memory.cache_dir
    end
    return os.getenv("HOME") .. "/.config/tiler"
end

--- Ensures the cache directory exists.
local function ensure_cache_dir()
    local cache_dir = get_cache_dir()
    os.execute("mkdir -p " .. cache_dir)
end

--- Gets the full path to the Space definitions file.
-- @return (string) The file path.
local function get_definitions_file()
    return get_cache_dir() .. "/space_definitions.json"
end

--- Gets the full path to the Space layouts file.
-- @return (string) The file path.
local function get_layouts_file()
    return get_cache_dir() .. "/space_layouts.json"
end

--- Gets the full path to the last active Space file.
-- @return (string) The file path.
local function get_last_active_file()
    return get_cache_dir() .. "/last_active_space.txt"
end

--- Saves Space definitions to disk.
-- @param definitions (table) The Space definitions table keyed by Space ID.
-- @return (boolean) True if successful, false otherwise.
function space_storage.save_space_definitions(definitions)
    ensure_cache_dir()
    local filename = get_definitions_file()

    debug_log("Saving Space definitions to:", filename)

    -- Convert numeric keys to strings for JSON encoding
    local serializable = {}
    for space_id, definition in pairs(definitions) do
        serializable[tostring(space_id)] = definition
    end

    local success, json_str = pcall(function()
        return json.encode(serializable, true) -- true for pretty printing
    end)

    if not success then
        debug_log("Failed to encode Space definitions:", json_str)
        return false
    end

    if not json_str then
        debug_log("JSON encoding returned nil")
        return false
    end

    local file = io.open(filename, "w")
    if not file then
        debug_log("Failed to open file for writing:", filename)
        return false
    end

    file:write(json_str)
    file:close()

    debug_log("Space definitions saved successfully")
    return true
end

--- Loads Space definitions from disk.
-- @return (table|nil) The Space definitions table, or nil if loading fails.
function space_storage.load_space_definitions()
    local filename = get_definitions_file()

    debug_log("Loading Space definitions from:", filename)

    local file = io.open(filename, "r")
    if not file then
        debug_log("No Space definitions file found")
        return nil
    end

    local content = file:read("*all")
    file:close()

    local success, loaded = pcall(function()
        return json.decode(content)
    end)

    if success and loaded then
        -- Convert string keys back to numbers
        local definitions = {}
        for space_id_str, definition in pairs(loaded) do
            local space_id = tonumber(space_id_str)
            if space_id then
                definitions[space_id] = definition
            else
                -- Keep as string if it can't be converted (shouldn't happen)
                definitions[space_id_str] = definition
            end
        end
        debug_log("Loaded Space definitions successfully")
        return definitions
    else
        debug_log("Failed to decode Space definitions:", loaded)
        return nil
    end
end

--- Saves Space layouts (window positions per Space per monitor) to disk.
-- @param layouts (table) The layouts table: space_id -> monitor_id -> layout_data
-- @return (boolean) True if successful, false otherwise.
function space_storage.save_space_layouts(layouts)
    ensure_cache_dir()
    local filename = get_layouts_file()

    debug_log("Saving Space layouts to:", filename)

    local success, json_str = pcall(function()
        return json.encode(layouts, true)
    end)

    if not success then
        debug_log("Failed to encode Space layouts:", json_str)
        return false
    end

    if not json_str then
        debug_log("JSON encoding returned nil")
        return false
    end

    local file = io.open(filename, "w")
    if not file then
        debug_log("Failed to open file for writing:", filename)
        return false
    end

    file:write(json_str)
    file:close()

    debug_log("Space layouts saved successfully")
    return true
end

--- Loads Space layouts from disk.
-- @return (table|nil) The layouts table, or nil if loading fails.
function space_storage.load_space_layouts()
    local filename = get_layouts_file()

    debug_log("Loading Space layouts from:", filename)

    local file = io.open(filename, "r")
    if not file then
        debug_log("No Space layouts file found")
        return nil
    end

    local content = file:read("*all")
    file:close()

    local success, layouts = pcall(function()
        return json.decode(content)
    end)

    if success and layouts then
        debug_log("Loaded Space layouts successfully")
        return layouts
    else
        debug_log("Failed to decode Space layouts:", layouts)
        return nil
    end
end

--- Saves a layout for a specific Space and monitor.
-- @param space_id (number) The Space ID.
-- @param monitor_id (number) The monitor ID.
-- @param layout_data (table) The layout data to save.
-- @return (boolean) True if successful, false otherwise.
function space_storage.save_space_monitor_layout(space_id, monitor_id, layout_data)
    -- Load existing layouts
    local all_layouts = space_storage.load_space_layouts() or {}

    -- Ensure Space entry exists
    if not all_layouts[tostring(space_id)] then
        all_layouts[tostring(space_id)] = {}
    end

    -- Save layout for this monitor
    all_layouts[tostring(space_id)][tostring(monitor_id)] = layout_data

    debug_log("Saving layout for Space", space_id, "monitor", monitor_id)

    -- Save back to disk
    return space_storage.save_space_layouts(all_layouts)
end

--- Loads a layout for a specific Space and monitor.
-- @param space_id (number) The Space ID.
-- @param monitor_id (number) The monitor ID.
-- @return (table|nil) The layout data, or nil if not found.
function space_storage.load_space_monitor_layout(space_id, monitor_id)
    local all_layouts = space_storage.load_space_layouts()
    if not all_layouts then
        return nil
    end

    local space_layouts = all_layouts[tostring(space_id)]
    if not space_layouts then
        debug_log("No layouts found for Space:", space_id)
        return nil
    end

    local layout = space_layouts[tostring(monitor_id)]
    if layout then
        debug_log("Loaded layout for Space", space_id, "monitor", monitor_id)
    else
        debug_log("No layout found for Space", space_id, "monitor", monitor_id)
    end

    return layout
end

--- Saves the ID of the last active Space.
-- @param space_id (number) The Space ID.
-- @return (boolean) True if successful, false otherwise.
function space_storage.set_last_active_space(space_id)
    ensure_cache_dir()
    local filename = get_last_active_file()

    debug_log("Saving last active Space:", space_id)

    local file = io.open(filename, "w")
    if not file then
        debug_log("Failed to open file for writing:", filename)
        return false
    end

    file:write(tostring(space_id))
    file:close()

    return true
end

--- Loads the ID of the last active Space.
-- @return (number|nil) The Space ID, or nil if not found.
function space_storage.get_last_active_space()
    local filename = get_last_active_file()

    local file = io.open(filename, "r")
    if not file then
        debug_log("No last active Space file found")
        return nil
    end

    local content = file:read("*all")
    file:close()

    local space_id = tonumber(content)
    if space_id then
        debug_log("Loaded last active Space:", space_id)
    else
        debug_log("Failed to parse last active Space")
    end

    return space_id
end

--- Captures the current window layout for a Space and monitor.
-- This records the position (zone_key, tile_index) of all windows on the monitor.
-- @param space_id (number) The Space ID.
-- @param monitor_id (number) The monitor ID.
-- @param window_state_manager (table) The window_state_manager module.
-- @return (table) The captured layout data.
function space_storage.capture_layout(space_id, monitor_id, window_state_manager)
    debug_log("Capturing layout for Space", space_id, "monitor", monitor_id)

    local layout = {
        space_id = space_id,
        monitor_id = monitor_id,
        captured_at = os.time(),
        windows = {}
    }

    -- Get all windows
    for _, window in ipairs(hs.window.allWindows()) do
        if window:isStandard() and not window:isMinimized() then
            local window_id = window:id()
            local pos = window_state_manager.get(window_id)

            -- Only capture windows on this monitor
            if pos and pos.monitor_id == monitor_id then
                table.insert(layout.windows, {
                    app_name = window:application():name(),
                    title = window:title(),
                    window_id = window_id,
                    zone_key = pos.zone_key,
                    tile_index = pos.tile_index
                })
            end
        end
    end

    debug_log("Captured", #layout.windows, "windows for Space", space_id)

    return layout
end

--- Restores a saved layout for a Space and monitor.
-- This attempts to move windows back to their saved positions.
-- @param space_id (number) The Space ID.
-- @param monitor_id (number) The monitor ID.
-- @param window_actions (table) The window_actions module.
-- @return (number) The number of windows successfully restored.
function space_storage.restore_layout(space_id, monitor_id, window_actions)
    local layout = space_storage.load_space_monitor_layout(space_id, monitor_id)
    if not layout or not layout.windows then
        debug_log("No layout to restore for Space", space_id, "monitor", monitor_id)
        return 0
    end

    debug_log("Restoring layout for Space", space_id, "monitor", monitor_id)

    local restored_count = 0

    for _, win_info in ipairs(layout.windows) do
        -- Try to find the window by app name
        local window = hs.window.find(win_info.app_name)
        if window then
            debug_log("Restoring window:", win_info.app_name, "to zone:", win_info.zone_key, "tile:", win_info.tile_index)

            -- Use window_actions to position the window
            if window_actions.position_window_from_memory then
                local success = window_actions.position_window_from_memory(
                    window,
                    monitor_id,
                    win_info.zone_key,
                    win_info.tile_index
                )
                if success then
                    restored_count = restored_count + 1
                end
            end
        else
            debug_log("Could not find window for app:", win_info.app_name)
        end
    end

    debug_log("Restored", restored_count, "windows for Space", space_id)
    return restored_count
end

--- Initializes the space_storage module.
-- @param cfg (table) The main configuration table.
-- @param log_func (function) The logging function to use.
function space_storage.init(cfg, log_func)
    debug_log = log_func or debug_log
    config = cfg

    -- Ensure cache directory exists
    ensure_cache_dir()

    debug_log("Space Storage initialized")
    return space_storage
end

return space_storage
