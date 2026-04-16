-- Timeline debug
local function time_it(label, fn)
    local start = os.clock()
    local result = fn()
    local elapsed = os.clock() - start
    print(label .. ": " .. (elapsed * 1000) .. "ms")
    return result
end

-- Test different phases
print("=== Timing Test ===")

time_it("allWindows", function()
    return hs.window.allWindows()
end)

local win = hs.window.focusedWindow()
if win then
    time_it("window:frame", function()
        return win:frame()
    end)
    
    time_it("window:screen", function()
        return win:screen()
    end)
    
    time_it("window:application", function()
        return win:application()
    end)
    
    time_it("window:setFrame", function()
        return win:setFrame({x=100, y=100, w=800, h=600})
    end)
end