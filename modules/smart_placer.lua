-- smart_placer.lua
-- Contains the logic for intelligently placing new windows in empty screen areas.
local hs_window = hs.window

local smart_placer = {}

-- Module state
local config = nil -- Set in init
local window_state_manager = nil -- Set in init
local debug_log = function(...)
end -- Placeholder, will be set in init

-- Compute distance map for empty space finding
local function compute_distance_map(screen, cell_size)
    local screen_frame = screen:frame()
    local grid_width = math.ceil(screen_frame.w / cell_size)
    local grid_height = math.ceil(screen_frame.h / cell_size)

    -- Initialize grid
    local grid = {}
    for i = 1, grid_height do
        grid[i] = {}
        for j = 1, grid_width do
            grid[i][j] = 0 -- 0 = empty
        end
    end

    -- Mark occupied cells
    for _, win in pairs(hs_window.allWindows()) do
        if win:screen():id() == screen:id() and win:isStandard() and not win:isMinimized() then
            local frame = win:frame()
            -- Ensure frame coordinates are relative to the screen origin
            local x1 = math.floor((frame.x - screen_frame.x) / cell_size) + 1
            local y1 = math.floor((frame.y - screen_frame.y) / cell_size) + 1
            local x2 = math.ceil((frame.x + frame.w - screen_frame.x) / cell_size)
            local y2 = math.ceil((frame.y + frame.h - screen_frame.h) / cell_size)

            for i = math.max(1, y1), math.min(grid_height, y2) do
                for j = math.max(1, x1), math.min(grid_width, x2) do
                    grid[i][j] = 1 -- 1 = occupied
                end
            end
        end
    end

    -- BFS to compute distances from occupied cells
    local distance = {}
    local queue = {}

    for i = 1, grid_height do
        distance[i] = {}
        for j = 1, grid_width do
            if grid[i][j] == 1 then
                distance[i][j] = 0
                table.insert(queue, {i, j})
            else
                distance[i][j] = -1 -- -1 = unvisited
            end
        end
    end

    local directions = {{0, 1}, {0, -1}, {1, 0}, {-1, 0}}
    local head = 1
    while head <= #queue do
        local cell = queue[head]
        head = head + 1
        local i, j = cell[1], cell[2]

        for _, dir in pairs(directions) do
            local ni, nj = i + dir[1], j + dir[2]
            if ni >= 1 and ni <= grid_height and nj >= 1 and nj <= grid_width and distance[ni][nj] == -1 then
                distance[ni][nj] = distance[i][j] + 1
                table.insert(queue, {ni, nj})
            end
        end
    end

    return distance, screen_frame
end

-- Find best position for a window
local function find_best_position(screen, window_width, window_height)
    local sp_config = config.tiler.smart_placement
    local cell_size = sp_config and sp_config.cell_size or 50
    local distance_map, screen_frame = compute_distance_map(screen, cell_size)

    local grid_width = math.ceil(screen_frame.w / cell_size)
    local grid_height = math.ceil(screen_frame.h / cell_size)
    local window_grid_width = math.ceil(window_width / cell_size)
    local window_grid_height = math.ceil(window_height / cell_size)

    local best_score = -1
    local best_pos = {
        x = screen_frame.x + 100, -- Default fallback x
        y = screen_frame.y + 100 -- Default fallback y
    }

    for i = 1, math.max(1, grid_height - window_grid_height + 1) do
        for j = 1, math.max(1, grid_width - window_grid_width + 1) do
            local min_distance_in_rect = math.huge
            local covered_occupied_cell = false

            for di = 0, window_grid_height - 1 do
                for dj = 0, window_grid_width - 1 do
                    if i + di >= 1 and i + di <= grid_height and j + dj >= 1 and j + dj <= grid_width then
                        local dist = distance_map[i + di][j + dj]
                        if dist == 0 then -- This cell is occupied
                            covered_occupied_cell = true
                            break
                        end
                        if dist < min_distance_in_rect then
                            min_distance_in_rect = dist
                        end
                    end
                end
                if covered_occupied_cell then
                    break
                end
            end

            if not covered_occupied_cell and min_distance_in_rect > best_score then
                best_score = min_distance_in_rect
                best_pos = {
                    x = screen_frame.x + (j - 1) * cell_size,
                    y = screen_frame.y + (i - 1) * cell_size
                }
            end
        end
    end
    debug_log("Smart placement best score:", best_score, "at x:", best_pos.x, "y:", best_pos.y)
    return best_pos
end

-- Place window smartly
function smart_placer.place_window(window)
    if not window or not window:isStandard() or window:isMinimized() then
        return false
    end

    local sp_config = config.tiler.smart_placement
    if not sp_config or not sp_config.enabled then
        return false
    end

    -- Exclude configured apps from smart placement
    if sp_config.exclude_apps then
        local app_name = window:application():name()
        for _, excluded_app in ipairs(config.tiler.smart_placement.exclude_apps) do
            if app_name == excluded_app then
                debug_log("Skipping smart placement for excluded app:", app_name)
                return false
            end
        end
    end

    local screen = window:screen()
    if not screen then
        return false
    end

    -- Skip if window is already in a tiler-managed zone
    if window_state_manager and window_state_manager.get and window_state_manager.get(window:id()) then
        debug_log("Skipping smart placement, window already in a zone:", window:application():name())
        return false
    end

    local frame = window:frame()
    local pos = find_best_position(screen, frame.w, frame.h)

    -- Apply the frame
    local saved_duration = hs.window.animationDuration
    hs.window.animationDuration = 0
    local success = window:setFrame({
        x = pos.x,
        y = pos.y,
        w = frame.w, -- Keep original width
        h = frame.h -- Keep original height
    })
    hs.window.animationDuration = saved_duration

    if success then
        debug_log("Smart placed window", window:application():name(), "at x:", pos.x, "y:", pos.y)
    else
        debug_log("Smart placement failed to set frame for window", window:application():name())
    end

    return success
end

-- Initialize the module
function smart_placer.init(cfg, wsm, log_func)
    config = cfg
    window_state_manager = wsm
    debug_log = log_func or debug_log
    debug_log("SmartPlacer initialized")
end

return smart_placer
