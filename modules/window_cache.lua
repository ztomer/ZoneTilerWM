local window_cache = {}
local hs_window = hs.window
local cache = {}
local debug_log_file = nil

local function get_debug_file()
    if not debug_log_file then
        local f = io.open(os.getenv("HOME") .. "/hammerspoon_cache_debug.log", "a")
        if f then
            debug_log_file = f
        end
    end
    return debug_log_file
end

local function dbg_write(msg)
    local f = get_debug_file()
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. ": " .. tostring(msg) .. "\n")
        f:flush()
    end
end

local function invalidate()
    cache = {}
end

function window_cache.init()
    invalidate()
end

function window_cache.refresh()
    invalidate()
    local wins = hs_window.allWindows()
    for _, win in ipairs(wins) do
        local wid = win:id()
        if wid then
            local app = win:application()
            local scr = win:screen()
            cache[wid] = {
                window = win,
                app_name = app and app:name() or nil,
                screen_id = scr and scr:id() or nil,
                screen_frame = scr and scr:frame() or nil,
                frame = win:frame(),
                isStandard = win:isStandard(),
                isMinimized = win:isMinimized()
            }
        end
    end
end

function window_cache.update(win, event)
    local wid = win:id()
    if not wid then return end
    if event == "destroyed" then
        cache[wid] = nil
        return
    end
    local app = win:application()
    local scr = win:screen()
    cache[wid] = {
        window = win,
        app_name = app and app:name() or nil,
        screen_id = scr and scr:id() or nil,
        screen_frame = scr and scr:frame() or nil,
        frame = win:frame(),
        isStandard = win:isStandard(),
        isMinimized = win:isMinimized()
    }
end

function window_cache.get_for_screen(screen_id)
    local result = {}
    for wid, info in pairs(cache) do
        if info.screen_id == screen_id and info.isStandard and not info.isMinimized then
            table.insert(result, info.window)
        end
    end
    return result
end

function window_cache.get_all_visible()
    local result = {}
    for wid, info in pairs(cache) do
        if info.isStandard and not info.isMinimized then
            table.insert(result, info.window)
        end
    end
    return result
end

function window_cache.get_for_screen_with_cache(screen_id)
    local result = {}
    for wid, info in pairs(cache) do
        if info.screen_id == screen_id and info.isStandard and not info.isMinimized then
            table.insert(result, info)
        end
    end
    return result
end

-- Returns the full cached info entry for a window id, or nil if not cached.
-- Use this to avoid hitting the AX API for properties like app_name / screen_id
-- that are already cached and rarely change for a given window.
function window_cache.get_info(wid)
    return cache[wid]
end

-- Like get_all_visible(), but returns the info entries (with app_name, screen_id,
-- frame, etc.) instead of bare hs.window objects. Prefer this when you need to
-- iterate and filter by cached fields.
function window_cache.get_all_visible_info()
    local result = {}
    for _, info in pairs(cache) do
        if info.isStandard and not info.isMinimized then
            table.insert(result, info)
        end
    end
    return result
end

-- Debug: Auto-verify all cached windows against actual API positions
function window_cache.verify_all()
    local f = get_debug_file()
    local mismatches = 0
    for wid, info in pairs(cache) do
        local win = hs_window.get(wid)
        if win then
            local actual = win:frame()
            if info.frame.x ~= actual.x or info.frame.y ~= actual.y or info.frame.w ~= actual.w or info.frame.h ~= actual.h then
                if f then
                    f:write("MISMATCH " .. tostring(info.app_name) .. ": cache=(" .. info.frame.x .. "," .. info.frame.y .. "," .. info.frame.w .. "," .. info.frame.h .. ") actual=(" .. actual.x .. "," .. actual.y .. "," .. actual.w .. "," .. actual.h .. ")\n")
                end
                mismatches = mismatches + 1
            end
        end
    end
    if f then
        f:write("Cache verify: " .. mismatches .. " mismatches out of " .. (#cache or 0) .. " cached\n")
        f:flush()
    end
    return mismatches
end

return window_cache