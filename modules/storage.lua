--- Abstract storage adapter for persisting data.
-- Currently implements a JSON file adapter.
-- @module storage
local json = require('hs.json')
local fs = require('hs.fs')

local storage = {}

---@class StorageAdapter
---@field save function(key, data)
---@field load function(key)

-- Default configuration
local config = {
    dir = os.getenv('HOME') .. '/.config/ZoneTilerWM',
}

--- Ensures the storage directory exists.
local function ensure_dir()
    hs.fs.mkdir(config.dir)
end

--- Gets the full file path for a given key.
---@param key string The storage key (filename without extension).
---@return string The full path.
local function get_path(key)
    return config.dir .. '/' .. key .. '.json'
end

--- Saves data to disk as JSON.
---@param key string The identifier for the data.
---@param data table The data to save.
---@return boolean success
---@return string|nil error_message
function storage.save(key, data)
    ensure_dir()
    local path = get_path(key)

    -- Add timestamp
    if type(data) == 'table' then
        data._timestamp = os.time()
    end

    local content = json.encode(data)
    if not content then
        return false, 'Failed to encode data to JSON'
    end

    local file = io.open(path, 'w')
    if not file then
        return false, 'Failed to open file for writing: ' .. path
    end

    file:write(content)
    file:close()
    return true
end

--- Loads data from disk.
---@param key string The identifier for the data.
---@return table|nil data The loaded data or nil if not found/error.
function storage.load(key)
    local path = get_path(key)
    local file = io.open(path, 'r')
    if not file then
        return nil
    end

    local content = file:read('*all')
    file:close()

    local success, data = pcall(function()
        return json.decode(content)
    end)
    if not success then
        print('[Storage] Failed to decode JSON from ' .. path)
        return nil
    end

    return data
end

--- Initializes the storage module with custom configuration.
---@param custom_config table|nil
function storage.init(custom_config)
    if custom_config then
        if custom_config.dir then
            config.dir = custom_config.dir
        end
    end
    ensure_dir()
end

return storage
