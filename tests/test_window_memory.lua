local window_memory = require "modules.window_memory"

-- Mock Tiler
local mock_tiler = {
    window_state = {
        get = function(id)
            return {
                monitor_id = "monitor-1",
                zone_key = "h",
                tile_index = 1
            }
        end
    },
    monitors = {
        get_id = function(screen) return "monitor-1" end
    },
    set_window_memory = function() end,
    position_window_from_memory = function() return true end
}

-- Mock Storage (override the real one for this test)
local mock_storage = {}
local stored_data = {}
mock_storage.load = function(key)
    return stored_data[key]
end
mock_storage.save = function(key, data)
    stored_data[key] = data
    return true
end
mock_storage.init = function() end

-- Inject mock storage into window_memory (requires us to modify window_memory to accept injection or use package.loaded hack)
-- Since we can't easily inject without modifying the module structure further, we'll rely on the fact that `require "modules.storage"` returns the same table.
local real_storage = require "modules.storage"
real_storage.save = mock_storage.save
real_storage.load = mock_storage.load


-- Initialize
window_memory.init(mock_tiler)

-- Test 1: Remember Position
local mock_window = {
    id = function() return 123 end,
    isStandard = function() return true end,
    isMinimized = function() return false end,
    application = function() return { name = function() return "TestApp" end } end,
    screen = function() return {} end
}

-- Mock allWindows to return our window for capture_current_positions
hs.window.allWindows = function()
    return { mock_window }
end

window_memory.on_window_positioned(mock_window, "monitor-1", "h", 1)

local remembered = window_memory.get_remembered_position("TestApp", "monitor-1")
if not remembered then
    error("Failed to remember position")
end
if remembered.zone_key ~= "h" then
    error("Remembered wrong zone: " .. tostring(remembered.zone_key))
end

-- Test 2: Save to Disk (via mock storage)
window_memory.save_all_positions()
local saved = stored_data["window_positions"]
if not saved then
    error("Failed to save to storage")
end
if #saved.positions == 0 then
    error("Saved positions array is empty")
end
if saved.positions[1].app_name ~= "TestApp" then
    error("Saved wrong app name")
end

print("WindowMemory tests passed!")
