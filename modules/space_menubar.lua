--- Provides a menubar indicator for macOS Spaces.
-- This module displays the current Space and allows switching between Spaces
-- via clicks on the menubar. It also triggers the preview window on hover/click.
-- @module space_menubar

local space_menubar = {}

-- Module state
local menubar_item = nil
local current_space_id = nil
local space_definitions = {}
local preview_module = nil

-- Module dependencies (set during init)
local config = nil
local space_manager = nil

-- Debug logging
local debug_log = function(...) end -- Placeholder, will be set in init

--- Updates the menubar text to reflect the current Space.
local function update_menubar_text()
    debug_log("===== UPDATE MENUBAR TEXT =====")

    if not menubar_item then
        debug_log("No menubar item, skipping")
        return
    end

    local all_spaces = space_manager.get_all_spaces()
    if not all_spaces then
        debug_log("Failed to get all spaces")
        menubar_item:setTitle("? Spaces")
        return
    end

    -- Flatten all spaces into a sorted list
    local space_list = {}
    for screen_uuid, spaces_for_screen in pairs(all_spaces) do
        debug_log("Screen", screen_uuid, "has", #spaces_for_screen, "spaces:", hs.inspect(spaces_for_screen))
        for _, space_id in ipairs(spaces_for_screen) do
            table.insert(space_list, space_id)
        end
    end
    table.sort(space_list)
    debug_log("All space IDs (sorted):", hs.inspect(space_list))

    -- Find the index of the current space in the sorted list
    local current_index = nil
    for i, space_id in ipairs(space_list) do
        debug_log("Comparing space_list[" .. i .. "]=" .. space_id, "with current_space_id=" .. tostring(current_space_id))
        if space_id == current_space_id then
            current_index = i
            debug_log("MATCH found at index", i)
            break
        end
    end

    debug_log("Current space ID:", current_space_id, "Index:", current_index, "Total spaces:", #space_list)

    -- Build menubar text with current space highlighted
    local parts = {}
    for i, space_id in ipairs(space_list) do
        local display_text

        if config.spaces.menubar.show_names then
            -- Show custom names if available
            display_text = space_manager.get_space_name(space_id) or tostring(i)
        else
            -- Show space numbers
            display_text = tostring(i)
        end

        -- Highlight by comparing index, not space_id
        if i == current_index then
            -- Highlight current space with brackets
            debug_log("Adding brackets around index", i)
            table.insert(parts, "[" .. display_text .. "]")
        else
            table.insert(parts, " " .. display_text .. " ")
        end
    end

    local title = table.concat(parts, "")
    menubar_item:setTitle(title)
    debug_log("Set menubar title to:", title)
    debug_log("===== MENUBAR UPDATE COMPLETE =====")
end

--- Handles Space change events from space_manager.
-- @param new_space_id (number) The newly active Space ID.
-- @param old_space_id (number) The previously active Space ID.
local function on_space_changed(new_space_id, old_space_id)
    debug_log("Menubar detected Space change:", old_space_id, "->", new_space_id)
    current_space_id = new_space_id
    update_menubar_text()
end

--- Creates the menubar click handler.
-- This allows users to click on space numbers in the menubar to switch.
-- @return (function) The click callback function.
local function create_click_callback()
    return function(modifiers)
        debug_log("Menubar clicked with modifiers:", hs.inspect(modifiers))

        -- In click mode, toggle the preview
        if config.spaces.preview.enabled and
           config.spaces.preview.activation_mode == "click" and
           preview_module then
            preview_module.toggle()
        end
    end
end

--- Creates a menu for the menubar item showing all Spaces.
-- @return (table) A list of menu items.
local function create_menu()
    local all_spaces = space_manager.get_all_spaces()
    if not all_spaces then
        return {}
    end

    -- Flatten and sort spaces
    local space_list = {}
    for screen_uuid, spaces_for_screen in pairs(all_spaces) do
        for _, space_id in ipairs(spaces_for_screen) do
            table.insert(space_list, space_id)
        end
    end
    table.sort(space_list)

    -- Build menu items
    local menu_items = {}
    for i, space_id in ipairs(space_list) do
        local name = space_manager.get_space_name(space_id) or ("Space " .. i)
        local is_current = (space_id == current_space_id)

        table.insert(menu_items, {
            title = (is_current and "✓ " or "   ") .. name,
            fn = function()
                debug_log("Menu: switching to Space", space_id)
                space_manager.switch_to_space(space_id)
            end
        })
    end

    -- Add separator and settings
    table.insert(menu_items, {title = "-"})
    table.insert(menu_items, {
        title = "Refresh Spaces",
        fn = function()
            debug_log("Menu: refreshing Spaces")
            space_manager.sync_spaces()
            update_menubar_text()
        end
    })

    return menu_items
end

--- Sets up hover detection for the menubar item.
-- When hover is detected, triggers the preview module.
local function setup_hover_detection()
    if not config.spaces.preview.enabled then
        debug_log("Hover detection skipped: preview not enabled")
        return
    end

    if config.spaces.preview.activation_mode ~= "hover" then
        debug_log("Hover detection skipped: activation mode is", config.spaces.preview.activation_mode)
        return
    end

    if not preview_module then
        debug_log("Hover detection skipped: preview_module is nil")
        return
    end

    debug_log("Setting up hover detection for menubar")
    debug_log("Preview config: enabled=", config.spaces.preview.enabled,
              "mode=", config.spaces.preview.activation_mode,
              "delay=", config.spaces.preview.hover_delay)

    -- Use timer-based polling instead of eventtap (more reliable)
    local hover_timer = nil
    local preview_visible = false
    local poll_timer = nil

    local function check_mouse_position()
        local mouse_pos = hs.mouse.absolutePosition()

        -- Get menubar frame
        local screen = hs.mouse.getCurrentScreen()
        if not screen then
            return
        end

        local screen_frame = screen:fullFrame()
        local menubar_height = 25 -- Standard macOS menubar height

        -- Calculate preview frame (to check if mouse is over preview)
        local preview_width = config.spaces.preview.window_width
        local preview_height = config.spaces.preview.window_height
        local preview_x = screen_frame.x + (screen_frame.w - preview_width) / 2
        local preview_y = screen_frame.y + menubar_height + 2

        -- Check if mouse is in menubar region OR over the preview window
        local in_menubar = (mouse_pos.y <= menubar_height)
        local in_preview = preview_visible and
                          (mouse_pos.x >= preview_x and mouse_pos.x <= preview_x + preview_width and
                           mouse_pos.y >= preview_y and mouse_pos.y <= preview_y + preview_height)

        if in_menubar or in_preview then
            -- Mouse is over menubar or preview - show preview after delay
            if not preview_visible and not hover_timer then
                debug_log("Mouse in menubar/preview area at y=", mouse_pos.y, ", starting hover timer")
                hover_timer = hs.timer.doAfter(config.spaces.preview.hover_delay, function()
                    debug_log("Hover delay elapsed, showing preview")
                    if preview_module then
                        preview_module.show()
                        preview_visible = true
                    end
                    hover_timer = nil
                end)
            end
        else
            -- Mouse left both menubar and preview areas - hide preview
            if hover_timer then
                debug_log("Mouse left area before timer at y=", mouse_pos.y, ", cancelling")
                hover_timer:stop()
                hover_timer = nil
            end
            if preview_visible then
                debug_log("Mouse left area at y=", mouse_pos.y, ", hiding preview")
                if preview_module then
                    preview_module.hide()
                end
                preview_visible = false
            end
        end
    end

    -- Poll mouse position every 100ms
    poll_timer = hs.timer.new(0.1, check_mouse_position)
    poll_timer:start()

    debug_log("Hover detection started with timer-based polling (100ms interval)")
end

--- Initializes the space_menubar module.
-- @param cfg (table) The main configuration table.
-- @param space_mgr (table) The space_manager module instance.
-- @param preview (table) The space_preview module instance (can be nil).
-- @param log_func (function) The logging function to use.
function space_menubar.init(cfg, space_mgr, preview, log_func)
    debug_log = log_func or debug_log
    config = cfg
    space_manager = space_mgr
    preview_module = preview

    -- Check if menubar is enabled
    if not config.spaces or not config.spaces.menubar or not config.spaces.menubar.enabled then
        debug_log("Menubar indicator is disabled in configuration")
        return space_menubar
    end

    debug_log("Initializing Space Menubar...")

    -- Create menubar item
    menubar_item = hs.menubar.new()
    if not menubar_item then
        debug_log("Failed to create menubar item")
        return space_menubar
    end

    -- Set up click callback if enabled
    if config.spaces.menubar.click_to_switch then
        menubar_item:setClickCallback(create_click_callback())
    end

    -- Set up menu
    menubar_item:setMenu(create_menu)

    -- Get current space and update display
    current_space_id = space_manager.get_current_space()
    update_menubar_text()

    -- Register for space change events
    space_manager.register_change_callback(on_space_changed)

    -- Set up hover detection if in hover mode
    setup_hover_detection()

    debug_log("Space Menubar initialized")
    return space_menubar
end

--- Updates the menubar display.
-- Call this when space definitions change.
function space_menubar.refresh()
    update_menubar_text()
end

--- Cleans up the space_menubar module.
function space_menubar.cleanup()
    debug_log("Cleaning up Space Menubar...")

    if menubar_item then
        menubar_item:delete()
        menubar_item = nil
    end
end

return space_menubar
