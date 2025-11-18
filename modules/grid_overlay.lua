--- Renders a visual grid overlay on the screen.
-- Uses hs.canvas to draw grid lines that match the current tiling layout and offsets.
-- @module grid_overlay
local grid_overlay = {}
local canvas = require("hs.canvas")
local screen = require("hs.screen")
local resize_manager = require("modules.resize_manager")
local zone_calculator = require("modules.zone_calculator")

-- Active canvas objects: monitor_id -> canvas
local overlays = {}

-- Configuration for the overlay visuals
local style = {
    color = { red = 0, green = 0.8, blue = 1, alpha = 0.8 }, -- Cyan/Blue "Tron" look
    strokeWidth = 4,
    fillColor = { red = 0, green = 0.2, blue = 0.3, alpha = 0.1 } -- Subtle background tint
}

--- Helper to calculate line position with offsets
local function get_line_pos(axis, index, total_size, count, monitor_id)
    if index <= 0 then return 0 end
    if index >= count then return total_size end

    local default_pos = (index / count) * total_size
    local offset_pct = resize_manager.get_offset(monitor_id, axis, index)
    local offset_px = offset_pct * total_size

    return default_pos + offset_px
end

--- Draws the grid for a specific screen.
-- @param scr hs.screen The screen to draw on.
local function draw_for_screen(scr)
    local monitor_id = require("modules.monitor_manager").get_id(scr)
    local frame = scr:fullFrame() -- Use fullFrame to cover menu bar if needed, or frame() for usable area

    -- Get layout config
    local grid_config, _ = zone_calculator.get_layout_config(scr)
    if not grid_config then return end

    local rows = grid_config.rows
    local cols = grid_config.cols

    -- Create or reuse canvas
    if overlays[monitor_id] then
        overlays[monitor_id]:delete()
    end

    local cv = canvas.new(frame)
    overlays[monitor_id] = cv

    -- 1. Draw Vertical Lines (Columns)
    for i = 1, cols - 1 do
        local x_pos = get_line_pos("x", i, frame.w, cols, monitor_id)
        cv:appendElements({
            type = "segments",
            coordinates = {
                { x = x_pos, y = 0 },
                { x = x_pos, y = frame.h }
            },
            action = "stroke",
            strokeColor = style.color,
            strokeWidth = style.strokeWidth
        })
    end

    -- 2. Draw Horizontal Lines (Rows)
    for i = 1, rows - 1 do
        local y_pos = get_line_pos("y", i, frame.h, rows, monitor_id)
        cv:appendElements({
            type = "segments",
            coordinates = {
                { x = 0, y = y_pos },
                { x = frame.w, y = y_pos }
            },
            action = "stroke",
            strokeColor = style.color,
            strokeWidth = style.strokeWidth
        })
    end

    -- 3. Optional: Draw a border around the whole screen to confirm active state
    cv:appendElements({
        type = "rectangle",
        action = "stroke",
        strokeColor = { red = style.color.red, green = style.color.green, blue = style.color.blue, alpha = 0.3 },
        strokeWidth = 10,
        frame = { x = 0, y = 0, w = frame.w, h = frame.h }
    })

    cv:show()
end

--- Shows the grid overlay on all screens.
function grid_overlay.show()
    for _, scr in ipairs(screen.allScreens()) do
        draw_for_screen(scr)
    end
end

--- Hides the grid overlay on all screens.
function grid_overlay.hide()
    for id, cv in pairs(overlays) do
        cv:delete()
    end
    overlays = {}
end

--- Updates the overlay (e.g., after a resize action).
function grid_overlay.update()
    -- For now, simple redraw. Optimization: update existing canvas elements.
    grid_overlay.show()
end

return grid_overlay
