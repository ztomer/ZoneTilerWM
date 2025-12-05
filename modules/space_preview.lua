--- Provides a visual preview of windows in Spaces with drag-and-drop support.
-- This module creates a canvas overlay showing miniaturized representations
-- of windows across different Spaces, allowing users to see and drag windows
-- between Spaces.
-- @module space_preview

local space_preview = {}

-- Module state
local canvas = nil
local is_visible = false
local drag_state = {
    active = false,
    window_id = nil,
    source_space_id = nil,
    target_space_id = nil,
    start_x = nil,
    start_y = nil
}
local click_away_watcher = nil

-- Module dependencies (set during init)
local config = nil
local space_manager = nil
local window_state_manager = nil

-- Debug logging
local debug_log = function(...) end -- Placeholder, will be set in init

--- Gets the frame where the preview canvas should be positioned.
-- Positions it directly below the menubar indicator, centered on screen.
-- @return (table) A frame table {x, y, w, h}.
local function get_preview_frame()
    local screen = hs.mouse.getCurrentScreen()
    if not screen then
        screen = hs.screen.mainScreen()
    end

    local screen_frame = screen:fullFrame()
    local menubar_height = 25 -- Standard macOS menubar height

    local width = config.spaces.preview.window_width
    local height = config.spaces.preview.window_height

    -- Center horizontally on screen, position directly below menubar with small gap
    local x = screen_frame.x + (screen_frame.w - width) / 2
    local y = screen_frame.y + menubar_height + 2 -- 2px gap below menubar

    debug_log("Preview frame:", "x=" .. x, "y=" .. y, "w=" .. width, "h=" .. height)

    return {x = x, y = y, w = width, h = height}
end

--- Gets all windows for a specific Space.
-- @param space_id (number) The Space ID.
-- @return (table) A list of hs.window objects.
local function get_windows_for_space(space_id)
    local windows_in_space = {}

    debug_log("Getting windows for Space:", space_id)

    -- Use hs.spaces API to get windows in this specific space
    local success, window_ids = pcall(function()
        return hs.spaces.windowsForSpace(space_id)
    end)

    if not success or not window_ids then
        debug_log("Failed to get windows for Space:", space_id, "Error:", window_ids)
        return windows_in_space
    end

    debug_log("hs.spaces.windowsForSpace returned", #window_ids, "window IDs for Space", space_id)

    -- Convert window IDs to window objects
    for _, window_id in ipairs(window_ids) do
        local window = hs.window.get(window_id)
        if window and window:isStandard() and not window:isMinimized() then
            table.insert(windows_in_space, window)
            debug_log("  - Added window:", window:application():name(), "-", window:title())
        end
    end

    debug_log("Found", #windows_in_space, "standard windows in Space", space_id)
    return windows_in_space
end

--- Calculates layout for window thumbnails within a space section.
-- @param windows (table) List of hs.window objects.
-- @param section_frame (table) The frame for this space section {x, y, w, h}.
-- @return (table) A list of thumbnail frames for each window.
local function calculate_thumbnail_layout(windows, section_frame)
    local thumbnails = {}
    local base_thumb_width = config.spaces.preview.thumbnail_size.width
    local base_thumb_height = config.spaces.preview.thumbnail_size.height
    local padding = 10

    -- Calculate how many columns fit in this section
    local columns = math.floor((section_frame.w - padding) / (base_thumb_width + padding))
    if columns < 1 then columns = 1 end

    -- Scale down thumbnail size if section is too narrow
    local actual_thumb_width = base_thumb_width
    local actual_thumb_height = base_thumb_height

    local available_width = section_frame.w - (2 * padding)
    local required_width = columns * base_thumb_width + (columns - 1) * padding

    if required_width > available_width then
        -- Scale down to fit
        local scale_factor = available_width / required_width
        actual_thumb_width = math.floor(base_thumb_width * scale_factor)
        actual_thumb_height = math.floor(base_thumb_height * scale_factor)
    end

    debug_log("Section width:", section_frame.w, "Columns:", columns, "Thumb size:", actual_thumb_width, "x", actual_thumb_height)

    for i, window in ipairs(windows) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)

        local x = section_frame.x + padding + col * (actual_thumb_width + padding)
        local y = section_frame.y + padding + row * (actual_thumb_height + padding)

        table.insert(thumbnails, {
            window = window,
            frame = {x = x, y = y, w = actual_thumb_width, h = actual_thumb_height}
        })
    end

    return thumbnails
end

--- Draws the preview canvas with all Spaces and their windows.
local function draw_preview()
    if not canvas then
        return
    end

    canvas:replaceElements()

    local frame = get_preview_frame()
    canvas:frame(frame)

    local bg_color = config.spaces.preview.background_color
    local border_color = config.spaces.preview.border_color
    local active_color = config.spaces.preview.active_space_color

    -- Background
    canvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = bg_color,
        frame = {x = 0, y = 0, w = frame.w, h = frame.h}
    })

    -- Border
    canvas:appendElements({
        type = "rectangle",
        action = "stroke",
        strokeColor = border_color,
        strokeWidth = 2,
        frame = {x = 1, y = 1, w = frame.w - 2, h = frame.h - 2}
    })

    -- Get all spaces
    local all_spaces = space_manager.get_all_spaces()
    if not all_spaces then
        debug_log("No spaces to display")
        return
    end

    -- Flatten and sort spaces
    local space_list = {}
    for screen_uuid, spaces_for_screen in pairs(all_spaces) do
        for _, space_id in ipairs(spaces_for_screen) do
            table.insert(space_list, space_id)
        end
    end
    table.sort(space_list)

    local current_space = space_manager.get_current_space()

    -- Calculate section dimensions
    local section_width = frame.w / #space_list
    local section_height = frame.h
    local header_height = 30

    -- Draw each space section
    for i, space_id in ipairs(space_list) do
        local section_x = (i - 1) * section_width
        local is_current = (space_id == current_space)

        -- Section background (highlight current space)
        if is_current then
            canvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = active_color,
                frame = {x = section_x, y = 0, w = section_width, h = header_height}
            })
        end

        -- Section border
        canvas:appendElements({
            type = "rectangle",
            action = "stroke",
            strokeColor = border_color,
            strokeWidth = 1,
            frame = {x = section_x, y = 0, w = section_width, h = section_height}
        })

        -- Space label
        local space_name = space_manager.get_space_name(space_id) or ("Space " .. i)
        canvas:appendElements({
            type = "text",
            text = space_name,
            textColor = {red = 1, green = 1, blue = 1, alpha = 1},
            textSize = 14,
            textAlignment = "center",
            frame = {x = section_x, y = 5, w = section_width, h = header_height}
        })

        -- Get windows for this space
        local windows = get_windows_for_space(space_id)

        -- Calculate thumbnail layout
        local section_frame = {
            x = section_x,
            y = header_height,
            w = section_width,
            h = section_height - header_height
        }
        local thumbnails = calculate_thumbnail_layout(windows, section_frame)

        -- Draw window thumbnails
        for _, thumbnail_data in ipairs(thumbnails) do
            local window = thumbnail_data.window
            local thumb_frame = thumbnail_data.frame

            -- Window rectangle
            canvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {red = 0.2, green = 0.2, blue = 0.2, alpha = 0.8},
                frame = thumb_frame,
                id = "window_" .. window:id()
            })

            -- Window border
            canvas:appendElements({
                type = "rectangle",
                action = "stroke",
                strokeColor = {red = 0.5, green = 0.5, blue = 0.5, alpha = 1},
                strokeWidth = 1,
                frame = thumb_frame
            })

            -- App icon (if available)
            local app = window:application()
            if app then
                local icon_size = 32
                local icon_x = thumb_frame.x + (thumb_frame.w - icon_size) / 2
                local icon_y = thumb_frame.y + 10

                canvas:appendElements({
                    type = "image",
                    image = hs.image.imageFromAppBundle(app:bundleID()),
                    frame = {x = icon_x, y = icon_y, w = icon_size, h = icon_size}
                })

                -- App name
                canvas:appendElements({
                    type = "text",
                    text = app:name(),
                    textColor = {red = 1, green = 1, blue = 1, alpha = 1},
                    textSize = 10,
                    textAlignment = "center",
                    frame = {x = thumb_frame.x, y = thumb_frame.y + 45, w = thumb_frame.w, h = 20}
                })
            end
        end
    end

    debug_log("Preview drawn with", #space_list, "spaces")
end

--- Finds the window ID at a given canvas position.
-- @param x (number) The x coordinate in canvas space.
-- @param y (number) The y coordinate in canvas space.
-- @return (number|nil) The window ID, or nil if no window at that position.
local function get_window_at_position(x, y)
    if not canvas then
        return nil
    end

    -- Iterate through canvas elements to find a window element at this position
    local elements = canvas:elementAttribute()
    for i, element in ipairs(elements) do
        if element.id and element.id:match("^window_") and element.frame then
            local frame = element.frame
            if x >= frame.x and x <= frame.x + frame.w and
               y >= frame.y and y <= frame.y + frame.h then
                local window_id = tonumber(element.id:match("^window_(%d+)$"))
                debug_log("Found window at position:", window_id)
                return window_id
            end
        end
    end

    return nil
end

--- Gets the Space ID for a given x coordinate in the canvas.
-- @param x (number) The x coordinate in canvas space.
-- @return (number|nil) The Space ID, or nil if not over a space.
local function get_space_at_position(x)
    local all_spaces = space_manager.get_all_spaces()
    if not all_spaces then
        return nil
    end

    -- Flatten and sort spaces
    local space_list = {}
    for screen_uuid, spaces_for_screen in pairs(all_spaces) do
        for _, space_id in ipairs(spaces_for_screen) do
            table.insert(space_list, space_id)
        end
    end
    table.sort(space_list)

    local frame = get_preview_frame()
    local section_width = frame.w / #space_list

    local section_index = math.floor(x / section_width) + 1
    if section_index >= 1 and section_index <= #space_list then
        return space_list[section_index]
    end

    return nil
end

--- Sets up mouse event handlers for drag-and-drop.
local function setup_drag_handlers()
    if not config.spaces.preview.drag_enabled then
        return
    end

    canvas:mouseCallback(function(canvas_obj, event, id, canvas_x, canvas_y)
        debug_log("Mouse event:", event, "at", canvas_x, canvas_y)

        if event == "mouseDown" then
            -- Start drag
            local window_id = get_window_at_position(canvas_x, canvas_y)
            if window_id then
                drag_state.active = true
                drag_state.window_id = window_id
                drag_state.start_x = canvas_x
                drag_state.start_y = canvas_y

                local window = hs.window.get(window_id)
                if window then
                    drag_state.source_space_id = space_manager.get_window_space(window)
                    debug_log("Started drag for window", window_id, "from Space", drag_state.source_space_id)
                end
            end

        elseif event == "mouseUp" then
            -- End drag
            if drag_state.active and drag_state.window_id then
                local target_space = get_space_at_position(canvas_x)

                if target_space and target_space ~= drag_state.source_space_id then
                    debug_log("Dropping window", drag_state.window_id, "to Space", target_space)

                    local window = hs.window.get(drag_state.window_id)
                    if window then
                        space_manager.move_window_to_space(window, target_space)

                        -- Redraw after a short delay to reflect the change
                        hs.timer.doAfter(0.2, function()
                            if is_visible then
                                draw_preview()
                            end
                        end)
                    end
                else
                    debug_log("Drag cancelled or dropped on same Space")
                end
            end

            -- Reset drag state
            drag_state.active = false
            drag_state.window_id = nil
            drag_state.source_space_id = nil
            drag_state.target_space_id = nil

        elseif event == "mouseMove" and drag_state.active then
            -- Update target space during drag
            drag_state.target_space_id = get_space_at_position(canvas_x)
            -- Could add visual feedback here (e.g., highlight target space)
        end
    end)

    debug_log("Drag handlers set up")
end

--- Sets up a click-away handler for click mode.
-- Closes the preview when clicking outside of it.
local function setup_click_away_handler()
    if click_away_watcher then
        click_away_watcher:stop()
        click_away_watcher = nil
    end

    click_away_watcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
        local mouse_pos = hs.mouse.absolutePosition()
        local canvas_frame = canvas:frame()

        -- Check if click is outside canvas
        if mouse_pos.x < canvas_frame.x or
           mouse_pos.x > canvas_frame.x + canvas_frame.w or
           mouse_pos.y < canvas_frame.y or
           mouse_pos.y > canvas_frame.y + canvas_frame.h then

            debug_log("Click outside preview, hiding")
            space_preview.hide()
            return true -- Consume the event
        end

        return false
    end)

    click_away_watcher:start()
    debug_log("Click-away handler set up")
end

--- Shows the preview window.
function space_preview.show()
    if not canvas or is_visible then
        return
    end

    debug_log("Showing Space preview")
    draw_preview()
    canvas:show()
    is_visible = true

    -- Set up click-away handler for click mode
    if config.spaces.preview.activation_mode == "click" then
        setup_click_away_handler()
    end
end

--- Hides the preview window.
function space_preview.hide()
    if not canvas or not is_visible then
        return
    end

    debug_log("Hiding Space preview")
    canvas:hide()
    is_visible = false

    -- Stop click-away handler
    if click_away_watcher then
        click_away_watcher:stop()
        click_away_watcher = nil
    end
end

--- Toggles the preview window visibility.
function space_preview.toggle()
    if is_visible then
        space_preview.hide()
    else
        space_preview.show()
    end
end

--- Refreshes the preview display if it's visible.
function space_preview.refresh()
    if is_visible then
        draw_preview()
    end
end

--- Initializes the space_preview module.
-- @param cfg (table) The main configuration table.
-- @param space_mgr (table) The space_manager module instance.
-- @param win_state_mgr (table) The window_state_manager module instance.
-- @param log_func (function) The logging function to use.
function space_preview.init(cfg, space_mgr, win_state_mgr, log_func)
    debug_log = log_func or debug_log
    config = cfg
    space_manager = space_mgr
    window_state_manager = win_state_mgr

    -- Check if preview is enabled
    if not config.spaces or not config.spaces.preview or not config.spaces.preview.enabled then
        debug_log("Space preview is disabled in configuration")
        return space_preview
    end

    debug_log("Initializing Space Preview...")

    -- Create canvas
    canvas = hs.canvas.new(get_preview_frame())
    canvas:level(hs.canvas.windowLevels.floating)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)

    -- Set up drag handlers
    setup_drag_handlers()

    -- Register for space change events to refresh preview
    space_manager.register_change_callback(function(new_space_id, old_space_id)
        debug_log("Preview detected Space change, refreshing")
        space_preview.refresh()
    end)

    debug_log("Space Preview initialized")
    return space_preview
end

--- Cleans up the space_preview module.
function space_preview.cleanup()
    debug_log("Cleaning up Space Preview...")

    if canvas then
        canvas:delete()
        canvas = nil
    end

    if click_away_watcher then
        click_away_watcher:stop()
        click_away_watcher = nil
    end

    is_visible = false
end

return space_preview
