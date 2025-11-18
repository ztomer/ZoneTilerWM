local storage = require "modules.storage"

-- Mock io.open to avoid writing to disk during tests
local mock_files = {}
local original_io_open = io.open

io.open = function(path, mode)
    if mode == "w" then
        return {
            write = function(self, content)
                mock_files[path] = content
            end,
            close = function() end
        }
    elseif mode == "r" then
        if mock_files[path] then
            return {
                read = function(self, fmt)
                    return mock_files[path]
                end,
                close = function() end
            }
        else
            return nil
        end
    end
    return nil
end

-- Mock hs.json.encode/decode for the test
hs.json.encode = function(t)
    -- Very simple encoder for the test data
    if t.test_key then
        return '{"test_key":"' .. t.test_key .. '"}'
    end
    return "{}"
end

hs.json.decode = function(s)
    if s:find("test_value") then
        return {test_key = "test_value"}
    end
    return {}
end


-- Test 1: Save data
local test_data = { test_key = "test_value" }
local success, err = storage.save("test_item", test_data)

if not success then
    error("Storage save failed: " .. tostring(err))
end

-- Verify file "written"
local expected_path = os.getenv("HOME") .. "/.config/ZoneTilerWM/test_item.json"
if not mock_files[expected_path] then
    error("File was not written to expected path: " .. expected_path)
end

-- Test 2: Load data
local loaded_data = storage.load("test_item")
if not loaded_data then
    error("Storage load returned nil")
end

if loaded_data.test_key ~= "test_value" then
    error("Loaded data mismatch. Expected 'test_value', got " .. tostring(loaded_data.test_key))
end

print("Storage tests passed!")
