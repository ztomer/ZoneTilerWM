-- window_state.lua
-- DEPRECATED: This file is replaced by window_state_manager.lua.
-- Keeping this file temporarily for compatibility if other modules
-- directly require "modules.window_state".
-- All functionality has been moved to window_state_manager.lua.
local window_state_manager = require "modules.window_state_manager"

-- Forward calls to the new manager
local window_state = {
    set = function(...)
        return window_state_manager.set(...)
    end,
    get = function(...)
        return window_state_manager.get(...)
    end,
    get_app_memory = function(...)
        return window_state_manager.get_app_memory(...)
    end,
    cleanup = function(...)
        return window_state_manager.cleanup(...)
    end,
    -- Expose the internal state for compatibility if needed (use with caution)
    _state = window_state_manager._state
}

-- Initialize the manager (it will handle its own init logic)
-- window_state_manager.init(...) -- This should be called by tiler.lua

return window_state
