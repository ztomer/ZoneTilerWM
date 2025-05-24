--[[
LRU Cache for Hammerspoon
=========================

A simple but effective Least Recently Used (LRU) cache implementation.
This module provides a general-purpose caching mechanism with configurable size limits.

Usage example:
-------------
local lru_cache = require "lru_cache"

-- Create a new cache with default limit of 1000 items
local my_cache = lru_cache.new()

-- Or with a custom limit
local small_cache = lru_cache.new(100)

-- Set a value
my_cache:set("key1", "value1")

-- Get a value (returns nil if not found)
local value = my_cache:get("key1")

-- Check if a key exists
if my_cache:has("key1") then
    -- do something
end

-- Remove a key
my_cache:remove("key1")

-- Clear the entire cache
my_cache:clear()

-- Get statistics
local stats = my_cache:stats()
print("Cache hits:", stats.hits)
print("Cache misses:", stats.misses)
print("Current size:", stats.size)
]] -- Create the module
local lru_cache = {}

-- Create a new LRU cache
function lru_cache.new(max_size)
    -- Default to 1000 items if not specified
    max_size = max_size or 1000

    -- Create the cache object
    local cache = {
        -- The actual cache storage - keys map to values
        _storage = {},

        -- The linked list for LRU ordering
        -- Head is most recently used, tail is least recently used
        _head = nil,
        _tail = nil,

        -- Map keys to their nodes in the linked list for O(1) lookup
        _nodes = {},

        -- Statistics
        _hits = 0,
        _misses = 0,

        -- Configuration
        _max_size = max_size,
        _current_size = 0
    }

    -- Set metatable for OO-style usage
    setmetatable(cache, {
        __index = lru_cache
    })

    return cache
end

-- Create a new node for the linked list
local function create_node(key, value)
    return {
        key = key,
        value = value,
        next = nil,
        prev = nil
    }
end

-- Add a node to the head of the list (most recently used)
local function add_to_head(cache, node)
    if not cache._head then
        -- Empty list
        cache._head = node
        cache._tail = node
    else
        -- Add to head
        node.next = cache._head
        cache._head.prev = node
        cache._head = node
    end
end

-- Remove a node from the list
local function remove_node(cache, node)
    if node.prev then
        node.prev.next = node.next
    else
        -- This was the head
        cache._head = node.next
    end

    if node.next then
        node.next.prev = node.prev
    else
        -- This was the tail
        cache._tail = node.prev
    end

    -- Clear node references
    node.next = nil
    node.prev = nil
end

-- Move a node to the head (mark as recently used)
local function move_to_head(cache, node)
    if cache._head == node then
        -- Already at head
        return
    end

    -- Remove from current position
    remove_node(cache, node)

    -- Add to head
    add_to_head(cache, node)
end

-- Remove the least recently used item (tail)
local function remove_tail(cache)
    if not cache._tail then
        return nil
    end

    local tail = cache._tail
    remove_node(cache, tail)

    return tail
end

-- Check if a key exists in the cache
function lru_cache:has(key)
    return self._nodes[key] ~= nil
end

-- Get a value from the cache
function lru_cache:get(key)
    local node = self._nodes[key]

    if not node then
        self._misses = self._misses + 1
        return nil
    end

    -- Move to front (mark as recently used)
    move_to_head(self, node)

    self._hits = self._hits + 1
    return node.value
end

-- Set a value in the cache
function lru_cache:set(key, value)
    -- Check if key already exists
    local node = self._nodes[key]

    if node then
        -- Update existing node
        node.value = value
        move_to_head(self, node)
        return
    end

    -- Check if we need to evict
    if self._current_size >= self._max_size then
        -- Remove the least recently used item
        local tail = remove_tail(self)
        if tail then
            self._nodes[tail.key] = nil
            self._storage[tail.key] = nil
            self._current_size = self._current_size - 1
        end
    end

    -- Create new node
    local new_node = create_node(key, value)

    -- Add to data structures
    self._nodes[key] = new_node
    self._storage[key] = value
    add_to_head(self, new_node)

    -- Increment size
    self._current_size = self._current_size + 1
end

-- Remove a key from the cache
function lru_cache:remove(key)
    local node = self._nodes[key]

    if not node then
        return false
    end

    -- Remove from linked list
    remove_node(self, node)

    -- Remove from data structures
    self._nodes[key] = nil
    self._storage[key] = nil

    -- Decrement size
    self._current_size = self._current_size - 1

    return true
end

-- Clear the entire cache
function lru_cache:clear()
    self._storage = {}
    self._nodes = {}
    self._head = nil
    self._tail = nil
    self._current_size = 0

    -- We don't reset statistics
end

-- Reset statistics
function lru_cache:reset_stats()
    self._hits = 0
    self._misses = 0
end

-- Get cache statistics
function lru_cache:stats()
    return {
        hits = self._hits,
        misses = self._misses,
        size = self._current_size,
        max_size = self._max_size,
        hit_ratio = self._hits / math.max(1, (self._hits + self._misses))
    }
end

-- Create a memoized version of a function using this cache
function lru_cache:memoize(func)
    return function(...)
        -- Create a key from the arguments
        local args = {...}
        local key = ""

        for i, arg in ipairs(args) do
            -- Simple serialization for basic types
            if type(arg) == "table" then
                -- For tables, we use a simple recursive approach
                -- This won't handle cycles or complex objects well
                key = key .. "T" .. tostring(i) .. "{"
                for k, v in pairs(arg) do
                    key = key .. tostring(k) .. ":" .. tostring(v) .. ","
                end
                key = key .. "}"
            else
                key = key .. tostring(arg) .. "|"
            end
        end

        -- Check cache
        local result = self:get(key)
        if result ~= nil then
            return result
        end

        -- Calculate, cache, and return
        result = func(...)
        self:set(key, result)
        return result
    end
end

-- Return a serialized version of a key suitable for caching
function lru_cache.key_maker(...)
    local args = {...}
    local key = ""

    for i, arg in ipairs(args) do
        if type(arg) == "table" then
            key = key .. "T" .. tostring(i) .. "{"
            -- Sort keys for consistent serialization
            local sorted_keys = {}
            for k in pairs(arg) do
                table.insert(sorted_keys, k)
            end
            table.sort(sorted_keys)

            for _, k in ipairs(sorted_keys) do
                local v = arg[k]
                key = key .. tostring(k) .. ":" .. tostring(v) .. ","
            end
            key = key .. "}"
        else
            key = key .. tostring(arg) .. "|"
        end
    end

    return key
end

-- Return the module
return lru_cache
