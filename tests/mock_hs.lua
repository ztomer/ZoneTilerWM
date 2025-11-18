-- Mock Hammerspoon API
local mock_hs = {}

-- Mock hs.fs
mock_hs.fs = {
    mkdir = function(path)
        -- print("Mock: mkdir " .. path)
        return true
    end,
    attributes = function(path)
        return {
            mode = "directory"
        }
    end
}

-- Mock hs.json
mock_hs.json = {
    encode = function(data)
        -- Simple JSON encoder for testing (not robust, but enough for basic tables)
        local function serialize(val)
            if type(val) == "table" then
                local parts = {}
                local is_array = #val > 0
                if is_array then
                    for _, v in ipairs(val) do
                        table.insert(parts, serialize(v))
                    end
                    return "[" .. table.concat(parts, ",") .. "]"
                else
                    for k, v in pairs(val) do
                        table.insert(parts, '"' .. k .. '":' .. serialize(v))
                    end
                    return "{" .. table.concat(parts, ",") .. "}"
                end
            elseif type(val) == "string" then
                return '"' .. val .. '"'
            else
                return tostring(val)
            end
        end
        return serialize(data)
    end,
    decode = function(str)
        -- Very basic decoder, relies on Lua's load for simple table strings
        -- In a real scenario, we might want a better parser or just assume the mock saves correctly
        -- For now, let's just return a dummy table if we can't parse, or try to parse simple JSON
        -- This is the hardest part to mock in pure Lua without a library.
        -- Let's cheat: The test runner will use a real JSON lib if available, or we assume input is a table for unit tests.
        -- Actually, let's just use a simple pattern matcher for the specific structure we expect
        return {}
    end
}

-- Mock hs.timer
mock_hs.timer = {
    doAfter = function(sec, fn)
        fn() -- Execute immediately for tests
        return {
            stop = function()
            end
        }
    end,
    doEvery = function(sec, fn)
        return {
            stop = function()
            end
        }
    end
}

-- Mock hs.window
mock_hs.window = {
    allWindows = function()
        return {}
    end,
    filter = {
        new = function()
            return {
                subscribe = function()
                end
            }
        end,
        windowCreated = "windowCreated",
        windowOpened = "windowOpened",
        windowDestroyed = "windowDestroyed"
    }
}

-- Mock hs.screen
mock_hs.screen = {
    allScreens = function()
        return {}
    end,
    watcher = {
        new = function()
            return {
                start = function()
                end
            }
        end
    }
}

-- Mock hs.hotkey
mock_hs.hotkey = {
    bind = function()
    end
}

-- Mock hs.drawing
mock_hs.drawing = {
    color = {
        green = {red=0, green=1, blue=0, alpha=1},
        red = {red=1, green=0, blue=0, alpha=1}
    }
}

-- Global hs injection
_G.hs = mock_hs

-- Mock module loading so `require "hs.json"` works
package.loaded["hs.fs"] = mock_hs.fs
package.loaded["hs.json"] = mock_hs.json
package.loaded["hs.window"] = mock_hs.window
package.loaded["hs.screen"] = mock_hs.screen
package.loaded["hs.timer"] = mock_hs.timer
package.loaded["hs.hotkey"] = mock_hs.hotkey

return mock_hs
