-- layout_manager.lua
-- Manages saving and loading of window layout snapshots.

local layout_manager = {}
local config = require "config"
local json = require "hs.json"

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("layout_manager")

-- Module state
local tiler = nil -- Set during initialization
local layouts = {} -- In-memory store for layouts

-- Get layout filename
local function get_layout_filename()
    local cache_dir = config.window_memory and config.window_memory.cache_dir or (os.getenv("HOME") .. "/.config/tiler")
    return cache_dir .. "/layouts.json"
end

-- Ensure cache directory exists
local function ensure_cache_dir()
    local cache_dir = config.window_memory and config.window_memory.cache_dir or (os.getenv("HOME") .. "/.config/tiler")
    os.execute("mkdir -p " .. cache_dir)
end

-- Load layouts from disk
function layout_manager.load_layouts()
    local filename = get_layout_filename()
    local file = io.open(filename, "r")
    if not file then
        debug_log("No layout file found")
        return
    end

    local content = file:read("*all")
    file:close()

    local success, data = pcall(function()
        return json.decode(content)
    end)

    if success and data then
        layouts = data
        debug_log("Loaded layouts from disk")
    else
        debug_log("Failed to parse layout file")
    end
end

-- Save layouts to disk
function layout_manager.save_layouts()
    ensure_cache_dir()
    local filename = get_layout_filename()
    local json_str = json.encode(layouts)
    local file = io.open(filename, "w")
    if file then
        file:write(json_str)
        file:close()
        debug_log("Saved layouts to disk")
    else
        debug_log("Failed to save layout file")
    end
end

-- Capture the current layout
function layout_manager.capture_layout(name)
    name = name or "default"
    debug_log("Capturing layout: " .. name)

    local layout = {
        name = name,
        windows = {}
    }

    for _, window in ipairs(hs.window.allWindows()) do
        if window:isStandard() and not window:isMinimized() then
            local app_name = window:application():name()
            local window_id = window:id()
            local pos = tiler.window_state.get(window_id)
            if pos and pos.zone_key and pos.tile_index then
                table.insert(layout.windows, {
                    app_name = app_name,
                    title = window:title(),
                    monitor_id = pos.monitor_id,
                    zone_key = pos.zone_key,
                    tile_index = pos.tile_index
                })
            end
        end
    end

    layouts[name] = layout
    debug_log("Captured " .. #layout.windows .. " windows in layout: " .. name)
    layout_manager.save_layouts()
end

-- Restore a layout
function layout_manager.restore_layout(name)
    name = name or "default"
    local layout = layouts[name]
    if not layout then
        debug_log("Layout not found: " .. name)
        return
    end

    debug_log("Restoring layout: " .. name)
    local restored_count = 0

    for _, win_info in ipairs(layout.windows) do
        -- Find a window that matches the app name and title
        local window = hs.window.find(win_info.app_name)
        if window then
            debug_log("Restoring " .. win_info.app_name .. " to zone: " .. win_info.zone_key .. ", tile: " .. win_info.tile_index)
            if tiler.window_actions.position_window_from_memory(window, win_info.monitor_id, win_info.zone_key, win_info.tile_index) then
                restored_count = restored_count + 1
            end
        end
    end

    debug_log("Restored " .. restored_count .. " windows from layout: " .. name)
end

-- Initialize the layout manager
function layout_manager.init(tiler_module)
    tiler = tiler_module
    layout_manager.debug = config.layout_manager and config.layout_manager.debug or false

    layout_manager.load_layouts()

    -- Save layout on shutdown
    local existing_shutdown_callback = hs.shutdownCallback
    hs.shutdownCallback = function()
        layout_manager.capture_layout("default")
        if existing_shutdown_callback then
            existing_shutdown_callback()
        end
    end

    -- Restore layout on startup
    -- We need to wait a bit for all windows to be created
    hs.timer.doAfter(5, function()
        layout_manager.restore_layout("default")
    end)

    debug_log("Layout manager initialized")
    return layout_manager
end

return layout_manager
