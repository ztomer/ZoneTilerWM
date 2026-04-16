--- Manages dynamic grid resizing offsets.
-- Allows users to adjust the position of grid lines (separators) for each monitor.
-- @module resize_manager
local hs_timer = hs.timer
local save_debouncer = nil
local resize_manager = {}
local storage = require('modules.storage')

-- State: monitor_id -> { x = { [index] = offset }, y = { [index] = offset } }
-- Offsets are relative to the default grid line position (0.0 - 1.0 scale or pixels? Let's use pixels for simplicity in calculation, or percentage?)
-- Let's use percentage of screen width/height to be resolution independent.
local offsets = {}

-- Configuration
local config = {
    step_size = 0.02 -- 2% adjustment per step
}

--- Loads saved offsets from storage.
function resize_manager.load()
    local data = storage.load('grid_offsets')
    if data then
        offsets = data
    end
end

--- Saves offsets to storage.
function resize_manager.save()
    storage.save('grid_offsets', offsets)
end

--- Gets the offset for a specific grid line.
---@param monitor_id string
---@param axis string "x" (cols) or "y" (rows)
---@param index number The index of the grid line (1 to N-1)
---@return number offset The offset in percentage (e.g., 0.05 for +5%)
function resize_manager.get_offset(monitor_id, axis, index)
    if offsets[monitor_id] and offsets[monitor_id][axis] then
        return offsets[monitor_id][axis][index] or 0
    end
    return 0
end

--- Adjusts a grid line.
---@param monitor_id string
---@param axis string "x" or "y"
---@param index number The index of the grid line.
---@param delta number The amount to change (e.g., 1 for +step, -1 for -step)
function resize_manager.adjust(monitor_id, axis, index, delta)
    if not offsets[monitor_id] then
        offsets[monitor_id] = {
            x = {},
            y = {}
        }
    end
    if not offsets[monitor_id][axis] then
        offsets[monitor_id][axis] = {}
    end

    local current = offsets[monitor_id][axis][index] or 0
    local new_val = current + (delta * config.step_size)

    -- Clamp
    if new_val > 0.4 then
        new_val = 0.4
    end
    if new_val < -0.4 then
        new_val = -0.4
    end

    offsets[monitor_id][axis][index] = new_val

    -- ONLY update the UI instantly. Defer the disk write.
    if save_debouncer then
        save_debouncer:stop()
    end
    save_debouncer = hs_timer.delayed.new(1.0, function()
        resize_manager.save()
        save_debouncer = nil
    end)
    save_debouncer:start()
end

--- Resets offsets for a monitor.
---@param monitor_id string
function resize_manager.reset(monitor_id)
    if offsets[monitor_id] then
        offsets[monitor_id] = nil
        resize_manager.save()
    end
end

--- Initializes the manager.
function resize_manager.init()
    resize_manager.load()
end

return resize_manager
