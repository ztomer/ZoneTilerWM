-- lru_cache.lua
local lru_cache = {}

function lru_cache.new(max_size)
    max_size = max_size or 1000
    local cache = {
        _storage = {},
        _head = nil,
        _tail = nil,
        _size = 0,
        _max_size = max_size,
        _stats = {
            hits = 0,
            misses = 0
        }
    }
    setmetatable(cache, {
        __index = lru_cache
    })
    return cache
end

function lru_cache:get(key)
    local node = self._storage[key]
    if node then
        self._stats.hits = self._stats.hits + 1
        self:_move_to_head(node)
        return node.value
    end
    self._stats.misses = self._stats.misses + 1
    return nil
end

function lru_cache:set(key, value)
    local node = self._storage[key]
    if node then
        node.value = value
        self:_move_to_head(node)
    else
        node = {
            key = key,
            value = value,
            prev = nil,
            next = nil
        }
        self._storage[key] = node
        self:_add_to_head(node)
        self._size = self._size + 1
        if self._size > self._max_size then
            self:_remove_tail()
        end
    end
end

function lru_cache:has(key)
    return self._storage[key] ~= nil
end

function lru_cache:remove(key)
    local node = self._storage[key]
    if node then
        self:_remove_node(node)
        self._storage[key] = nil
        self._size = self._size - 1
    end
end

function lru_cache:clear()
    self._storage = {}
    self._head = nil
    self._tail = nil
    self._size = 0
    self._stats = {
        hits = 0,
        misses = 0
    }
end

function lru_cache:stats()
    return {
        hits = self._stats.hits,
        misses = self._stats.misses,
        size = self._size
    }
end

-- Internal Linked-List Methods
function lru_cache:_move_to_head(node)
    if node == self._head then
        return
    end
    self:_remove_node(node)
    self:_add_to_head(node)
end

function lru_cache:_add_to_head(node)
    node.next = self._head
    node.prev = nil
    if self._head then
        self._head.prev = node
    end
    self._head = node
    if not self._tail then
        self._tail = node
    end
end

function lru_cache:_remove_node(node)
    if node.prev then
        node.prev.next = node.next
    else
        self._head = node.next
    end
    if node.next then
        node.next.prev = node.prev
    else
        self._tail = node.prev
    end
end

function lru_cache:_remove_tail()
    if not self._tail then
        return
    end
    self._storage[self._tail.key] = nil
    self:_remove_node(self._tail)
    self._size = self._size - 1
end

-- The Fix: O(1) Key Generation. No sorting, no table iteration.
function lru_cache.key_maker(...)
    local key_parts = {}
    -- select('#', ...) safely counts nil arguments too
    for i = 1, select('#', ...) do
        local arg = select(i, ...)
        -- tostring(arg) for a table returns its memory address natively in Lua
        table.insert(key_parts, type(arg) .. ":" .. tostring(arg))
    end
    return table.concat(key_parts, "|")
end

function lru_cache:memoize(func)
    return function(...)
        local key = lru_cache.key_maker(...)
        local cached_result = self:get(key)
        if cached_result ~= nil then
            return cached_result
        end

        local result = func(...)
        self:set(key, result)
        return result
    end
end

return lru_cache
