--- Manages macOS Spaces integration for ZoneTilerWM.
-- This module provides the core functionality for detecting, tracking, and switching
-- between macOS Mission Control Spaces. It uses the hs.spaces API to interact with
-- the native Spaces system and maintains state about Space definitions and current focus.
-- @module space_manager

local space_manager = {}

-- Module state
local spaces = {
    -- Current macOS Space ID from hs.spaces.focusedSpace()
    current_space_id = nil,

    -- Space definitions keyed by macOS Space ID
    -- space_id -> {name, macos_space_id, created_at, monitor_ids}
    definitions = {},

    -- hs.spaces.watcher instance (backup, rarely fires with valid IDs)
    watcher = nil,

    -- Callbacks for Space change events
    change_callbacks = {}
}

-- Module dependencies (set during init)
local config = nil
local tiler = nil
local monitor_manager = nil
local window_memory = nil
local space_storage = nil

-- Debug logging
local debug_log = function(...) end -- Placeholder, will be set in init

--- Wraps hs.spaces.focusedSpace() with error handling.
-- NOTE: This function updates spaces.current_space_id as a side effect!
-- Use query_current_space() if you want to check without updating state.
-- @return (number|nil) The current Space ID, or nil if API call fails.
function space_manager.get_current_space()
    local success, space_id = pcall(function()
        return hs.spaces.focusedSpace()
    end)

    if success and space_id then
        spaces.current_space_id = space_id
        debug_log("Current Space ID:", space_id)
        return space_id
    else
        debug_log("Failed to get current Space ID:", space_id)
        return nil
    end
end

--- Queries the current Space ID without updating internal state.
-- Use this when you want to check the space without side effects.
-- @return (number|nil) The current Space ID, or nil if API call fails.
local function query_current_space()
    debug_log("🔍 API CALL: hs.spaces.focusedSpace()")
    local success, space_id = pcall(function()
        return hs.spaces.focusedSpace()
    end)

    if success and space_id then
        debug_log("🔍 API RESULT: hs.spaces.focusedSpace() returned", space_id)
        return space_id
    else
        debug_log("🔍 API ERROR: hs.spaces.focusedSpace() failed:", space_id)
        return nil
    end
end

--- Wraps hs.spaces.allSpaces() with error handling.
-- @return (table|nil) A table of all Spaces organized by screen UUID, or nil if API call fails.
function space_manager.get_all_spaces()
    debug_log("🔍 API CALL: hs.spaces.allSpaces()")
    local success, all_spaces = pcall(function()
        return hs.spaces.allSpaces()
    end)

    if success and all_spaces then
        -- Count total spaces
        local total = 0
        for _, spaces_list in pairs(all_spaces) do
            total = total + #spaces_list
        end
        debug_log("🔍 API RESULT: hs.spaces.allSpaces() returned", total, "total spaces")
        return all_spaces
    else
        debug_log("🔍 API ERROR: hs.spaces.allSpaces() failed:", all_spaces)
        return nil
    end
end

--- Switches to a specific Space using hs.spaces.gotoSpace().
-- @param space_id (number) The macOS Space ID to switch to.
-- @return (boolean) True if the switch was successful, false otherwise.
function space_manager.switch_to_space(space_id)
    if not space_id then
        debug_log("Cannot switch to nil Space ID")
        return false
    end

    -- Track rapid space switching
    local now = os.time()
    local time_since_last_switch = now - spaces.last_switch_time
    if time_since_last_switch < 1 then
        debug_log("⚠️ RAPID SPACE SWITCH detected! Time since last:", time_since_last_switch, "seconds")
    end
    spaces.last_switch_time = now

    debug_log("========== SPACE SWITCH REQUEST ==========")
    debug_log("Switching to Space ID:", space_id)
    debug_log("Current Space ID:", spaces.current_space_id)

    debug_log("🔍 API CALL: hs.spaces.gotoSpace(" .. tostring(space_id) .. ")")
    local success, result = pcall(function()
        return hs.spaces.gotoSpace(space_id)
    end)

    if success then
        debug_log("🔍 API RESULT: hs.spaces.gotoSpace() returned", result, "(true=success)")
        debug_log("Successfully switched to Space:", space_id)

        -- The watcher may not fire with a valid ID, so manually update after animation
        -- Wait a bit for the animation, then verify and update if needed
        hs.timer.doAfter(0.3, function()
            local actual_space = query_current_space()
            debug_log("Post-switch verification: requested", space_id, "actual", actual_space, "stored", spaces.current_space_id)

            -- Warn if we didn't end up where we requested
            if actual_space and actual_space ~= space_id then
                debug_log("⚠️⚠️⚠️ SPACE MISMATCH! Requested space", space_id, "but actually at space", actual_space)
            end

            if actual_space and actual_space > 0 and actual_space ~= spaces.current_space_id then
                debug_log("🔧 Manually updating space state (watcher didn't fire with valid ID)")
                local old_space_id = spaces.current_space_id
                spaces.current_space_id = actual_space
                debug_log("📝 Updated space_id:", old_space_id, "->", actual_space)

                -- Ensure Space is defined
                space_manager.ensure_space_defined(actual_space)

                -- Notify all registered callbacks
                debug_log("🔔 Notifying", #spaces.change_callbacks, "callbacks of manual space change:", old_space_id, "->", actual_space)
                for i, callback in ipairs(spaces.change_callbacks) do
                    local cb_success, err = pcall(callback, actual_space, old_space_id)
                    if not cb_success then
                        debug_log("❌ Callback", i, "error:", err)
                    else
                        debug_log("✅ Callback", i, "completed successfully")
                    end
                end

                -- Save current Space to storage
                if space_storage then
                    space_storage.set_last_active_space(actual_space)
                    debug_log("Saved space to storage")
                end
            else
                debug_log("Watcher already updated space state, no manual update needed")
            end
        end)

        debug_log("========== SPACE SWITCH REQUEST COMPLETE ==========")
        return true
    else
        debug_log("Failed to switch to Space:", space_id, "Error:", result)
        debug_log("========== SPACE SWITCH REQUEST FAILED ==========")
        return false
    end
end

--- Callback function for hs.spaces.watcher.
-- Called when the active Space changes.
-- @param space_id (number) The new active Space ID.
local function on_space_change(space_id)
    debug_log("========== SPACE CHANGE EVENT ==========")
    debug_log("Watcher received space_id:", space_id, "type:", type(space_id))
    debug_log("Current stored space_id:", spaces.current_space_id)

    -- Ignore invalid space IDs from the watcher
    -- The watcher sometimes sends -1 during transitions, which we can safely ignore
    if not space_id or space_id == -1 or space_id <= 0 then
        debug_log("❌ Ignoring invalid space ID from watcher:", space_id)
        return
    end

    -- We got a valid space ID from the watcher!
    debug_log("✅ VALID space ID from watcher:", space_id)

    -- Update current Space ID
    local old_space_id = spaces.current_space_id
    spaces.current_space_id = space_id
    debug_log("📝 Updated space_id:", old_space_id, "->", space_id)

    -- Ensure Space is defined
    space_manager.ensure_space_defined(space_id)

    -- Notify all registered callbacks (even if space didn't change, for initialization)
    debug_log("🔔 Notifying", #spaces.change_callbacks, "callbacks of space change:", old_space_id, "->", space_id)
    for i, callback in ipairs(spaces.change_callbacks) do
        local success, err = pcall(callback, space_id, old_space_id)
        if not success then
            debug_log("❌ Callback", i, "error:", err)
        else
            debug_log("✅ Callback", i, "completed successfully")
        end
    end

    -- Save current Space to storage
    if space_storage then
        space_storage.set_last_active_space(space_id)
        debug_log("Saved space to storage")
    end

    debug_log("========== SPACE CHANGE COMPLETE ==========")
end

--- Registers a callback to be called when Spaces change.
-- @param callback (function) A function that takes (new_space_id, old_space_id) as parameters.
function space_manager.register_change_callback(callback)
    table.insert(spaces.change_callbacks, callback)
    debug_log("Registered Space change callback")
end

--- Notifies the system that a space switch has occurred.
-- This is called by the hotkey interceptor when it detects a space switch.
-- Unlike switch_to_space(), this doesn't call gotoSpace() - Mission Control handles the switch.
-- We just update our internal state and trigger callbacks.
-- @param target_space_id (number) The space ID we're switching to.
function space_manager.notify_space_switch(target_space_id)
    if not target_space_id or target_space_id <= 0 then
        debug_log("Invalid target space ID:", target_space_id)
        return
    end

    debug_log("🔔 Notified of space switch to:", target_space_id)

    -- Verify we actually switched by querying the current space
    local actual_space = query_current_space()
    if actual_space and actual_space > 0 then
        if actual_space == target_space_id then
            debug_log("✅ Confirmed: switched to space", target_space_id)
            on_space_change(actual_space)
        else
            debug_log("⚠️ Mismatch: expected", target_space_id, "but at", actual_space)
            -- Still update to where we actually are
            on_space_change(actual_space)
        end
    else
        debug_log("❌ Could not verify space switch")
    end
end

--- Ensures a Space definition exists for the given Space ID.
-- If the Space is not defined, creates a default definition.
-- @param space_id (number) The macOS Space ID.
function space_manager.ensure_space_defined(space_id)
    -- Validate space ID - reject invalid IDs like -1
    if not space_id or type(space_id) ~= "number" or space_id <= 0 then
        debug_log("Refusing to create definition for invalid space ID:", space_id)
        return
    end

    if not spaces.definitions[space_id] then
        debug_log("Creating default definition for Space:", space_id)
        spaces.definitions[space_id] = {
            name = "Space " .. space_id,
            macos_space_id = space_id,
            created_at = os.time(),
            monitor_ids = {}
        }

        -- Save to storage
        if space_storage then
            space_storage.save_space_definitions(spaces.definitions)
        end
    end
end

--- Sets a custom name for a Space.
-- @param space_id (number) The macOS Space ID.
-- @param name (string) The custom name for the Space.
function space_manager.set_space_name(space_id, name)
    space_manager.ensure_space_defined(space_id)
    spaces.definitions[space_id].name = name
    debug_log("Set name for Space", space_id, "to:", name)

    -- Save to storage
    if space_storage then
        space_storage.save_space_definitions(spaces.definitions)
    end
end

--- Gets the name of a Space.
-- @param space_id (number) The macOS Space ID.
-- @return (string) The Space name.
function space_manager.get_space_name(space_id)
    space_manager.ensure_space_defined(space_id)
    return spaces.definitions[space_id].name
end

--- Synchronizes Space definitions with the current macOS Spaces state.
-- This discovers all available Spaces and ensures they are defined.
-- Should be called on initialization and when screen configuration changes.
function space_manager.sync_spaces()
    debug_log("Synchronizing Spaces with macOS...")

    local all_spaces = space_manager.get_all_spaces()
    if not all_spaces then
        debug_log("Cannot sync: failed to get all Spaces")
        return
    end

    -- Iterate through all screens and their Spaces
    for screen_uuid, space_ids in pairs(all_spaces) do
        for _, space_id in ipairs(space_ids) do
            space_manager.ensure_space_defined(space_id)
            debug_log("Found Space:", space_id, "on screen:", screen_uuid)
        end
    end

    debug_log("Space synchronization complete")
end

--- Gets all Space definitions.
-- @return (table) A table of Space definitions keyed by Space ID.
function space_manager.get_space_definitions()
    return spaces.definitions
end

--- Moves a window to a specific Space.
-- @param window (hs.window) The window to move.
-- @param space_id (number) The target Space ID.
-- @return (boolean) True if successful, false otherwise.
function space_manager.move_window_to_space(window, space_id)
    if not window or not space_id then
        debug_log("Cannot move window: invalid parameters")
        return false
    end

    debug_log("Moving window", window:id(), "to Space:", space_id)

    local success, result = pcall(function()
        return hs.spaces.moveWindowToSpace(window, space_id)
    end)

    if success then
        debug_log("Successfully moved window to Space:", space_id)
        return true
    else
        debug_log("Failed to move window to Space:", space_id, "Error:", result)
        return false
    end
end

--- Gets the Space ID that a window is currently on.
-- @param window (hs.window) The window to check.
-- @return (number|nil) The Space ID, or nil if it cannot be determined.
function space_manager.get_window_space(window)
    if not window then
        return nil
    end

    local success, spaces_for_window = pcall(function()
        return hs.spaces.windowSpaces(window)
    end)

    if success and spaces_for_window and #spaces_for_window > 0 then
        -- A window can be on multiple Spaces (sticky windows), return the first
        return spaces_for_window[1]
    else
        debug_log("Failed to get Space for window:", window:id())
        return nil
    end
end

--- Checks if the Spaces feature is enabled in configuration.
-- @return (boolean) True if Spaces are enabled.
function space_manager.is_enabled()
    return config and config.spaces and config.spaces.enabled or false
end

--- Initializes the space_manager module.
-- @param cfg (table) The main configuration table.
-- @param tiler_module (table) The tiler module instance.
-- @param monitor_mgr (table) The monitor_manager module instance.
-- @param window_mem (table) The window_memory module instance.
-- @param storage (table) The space_storage module instance.
-- @param log_func (function) The logging function to use.
function space_manager.init(cfg, tiler_module, monitor_mgr, window_mem, storage, log_func)
    debug_log = log_func or debug_log
    config = cfg
    tiler = tiler_module
    monitor_manager = monitor_mgr
    window_memory = window_mem
    space_storage = storage

    -- Check if Spaces are enabled
    if not space_manager.is_enabled() then
        debug_log("Spaces feature is disabled in configuration")
        return space_manager
    end

    debug_log("Initializing Space Manager...")

    -- Load Space definitions from storage
    if space_storage then
        local loaded_definitions = space_storage.load_space_definitions()
        if loaded_definitions then
            spaces.definitions = loaded_definitions
            debug_log("Loaded", #spaces.definitions, "Space definitions from storage")
        end

        -- Restore last active Space
        local last_space = space_storage.get_last_active_space()
        if last_space then
            spaces.current_space_id = last_space
        end
    end

    -- Get current Space
    local current = space_manager.get_current_space()
    if current then
        space_manager.ensure_space_defined(current)
    end

    -- Sync with macOS Spaces
    space_manager.sync_spaces()

    -- Set up Spaces watcher (backup mechanism, rarely fires with valid IDs)
    local success, watcher_or_err = pcall(function()
        return hs.spaces.watcher.new(on_space_change)
    end)

    if success and watcher_or_err then
        spaces.watcher = watcher_or_err
        spaces.watcher:start()
        debug_log("Spaces watcher started (backup)")
    else
        debug_log("Failed to create Spaces watcher:", watcher_or_err)
    end

    -- NOTE: We don't use polling anymore!
    -- Instead, hotkey interception (in init.lua) detects space switches instantly
    -- when the user presses the configured shortcuts (e.g., Ctrl+Shift+1-9)

    debug_log("Space Manager initialized")
    return space_manager
end

--- Cleans up the space_manager module.
-- Stops the watcher and saves state.
function space_manager.cleanup()
    debug_log("Cleaning up Space Manager...")

    if spaces.watcher then
        spaces.watcher:stop()
        debug_log("Spaces watcher stopped")
    end

    -- Save Space definitions
    if space_storage then
        space_storage.save_space_definitions(spaces.definitions)
    end
end

-- Expose internal state for debugging
space_manager._state = spaces

return space_manager
