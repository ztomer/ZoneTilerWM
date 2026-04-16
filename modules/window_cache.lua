local window_cache = {}
local hs_window = hs.window
local cache = {}
local focus_watcher = nil

function window_cache.init()
    cache = {}
    -- Passive focus tracking to power the Working Set Cull
    if focus_watcher then
        focus_watcher:stop()
    end
    focus_watcher = hs_window.filter.new():subscribe(hs.window.filter.windowFocused, function(win)
        local wid = win:id()
        if wid and cache[wid] then
            cache[wid].last_focused_time = os.time()
        end
    end)
end

function window_cache.refresh()
    cache = {}
    for _, win in ipairs(hs_window.allWindows()) do
        window_cache.update(win, "created")
    end
end

function window_cache.update(win, event)
    local wid = win:id()
    if not wid then
        return
    end
    if event == "destroyed" then
        cache[wid] = nil
        return
    end

    local app = win:application()
    cache[wid] = {
        window = win,
        app_name = app and app:name() or nil,
        isStandard = win:isStandard(),
        last_focused_time = os.time()
    }
end

local function get_live_info(cached_data, wid)
    local win = cached_data.window
    if not win or not win:id() then
        cache[wid] = nil
        return nil
    end
    local scr = win:screen()
    return {
        window = win,
        app_name = cached_data.app_name,
        isStandard = cached_data.isStandard,
        last_focused_time = cached_data.last_focused_time,
        screen_id = scr and scr:id() or nil,
        frame = win:frame(),
        isMinimized = win:isMinimized()
    }
end

function window_cache.get_for_screen_with_cache(screen_id)
    local result = {}
    for wid, cached_data in pairs(cache) do
        if cached_data.isStandard then
            local info = get_live_info(cached_data, wid)
            if info and info.screen_id == screen_id and not info.isMinimized then
                table.insert(result, info)
            end
        end
    end
    return result
end

function window_cache.get_all_visible_info()
    local result = {}
    for wid, cached_data in pairs(cache) do
        if cached_data.isStandard then
            local info = get_live_info(cached_data, wid)
            if info and not info.isMinimized then
                table.insert(result, info)
            end
        end
    end
    return result
end

function window_cache.get_info(wid)
    local cached_data = cache[wid]
    if not cached_data then
        return nil
    end
    return get_live_info(cached_data, wid)
end

return window_cache
