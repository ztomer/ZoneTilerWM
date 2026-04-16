-- Auto-run cache verification
local f = io.open(os.getenv("HOME") .. "/cache_debug.log", "w")
local cache = {}
local allw = hs.window.allWindows()

for _, win in ipairs(allw) do
    local id = win:id()
    if id then
        local app = win:application()
        cache[id] = {
            app = app and app:name() or "?",
            frame = win:frame()
        }
    end
end

local mismatches = 0
for id, info in pairs(cache) do
    local win = hs.window.get(id)
    if win then
        local actual = win:frame()
        if info.frame.x ~= actual.x or info.frame.y ~= actual.y or info.frame.w ~= actual.w or info.frame.h ~= actual.h then
            f:write("MISMATCH " .. info.app .. ": cache=(" .. info.frame.x .. "," .. info.frame.y .. "," .. info.frame.w .. "," .. info.frame.h .. ") actual=(" .. actual.x .. "," .. actual.y .. "," .. actual.w .. "," .. actual.h .. ")\n")
            mismatches = mismatches + 1
        end
    end
end

f:write("Total windows: " .. #allw .. ", Mismatches: " .. mismatches .. "\n")
f:close()
print("Done - ~/cache_debug.log created")