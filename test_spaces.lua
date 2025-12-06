-- Test script for Spaces API
-- Run this in Hammerspoon console to verify Spaces detection

print("========== Testing Spaces API ==========")

-- Test 1: Get current space
local success, current_space = pcall(function()
    return hs.spaces.focusedSpace()
end)

if success then
    print("✓ Current Space ID:", current_space)
else
    print("✗ Failed to get current space:", current_space)
end

-- Test 2: Get all spaces
success, all_spaces = pcall(function()
    return hs.spaces.allSpaces()
end)

if success and all_spaces then
    print("\n✓ All Spaces:")
    for screen_uuid, spaces in pairs(all_spaces) do
        print("  Screen:", screen_uuid)
        print("  Spaces:", hs.inspect(spaces))
    end
else
    print("✗ Failed to get all spaces:", all_spaces)
end

-- Test 3: Count total spaces
if success and all_spaces then
    local total = 0
    local space_list = {}
    for _, spaces in pairs(all_spaces) do
        for _, space_id in ipairs(spaces) do
            total = total + 1
            table.insert(space_list, space_id)
        end
    end
    table.sort(space_list)
    print("\n✓ Total Spaces:", total)
    print("  Space IDs (sorted):", hs.inspect(space_list))
end

-- Test 4: Check if current space is in the list
if success and all_spaces and current_space then
    local found = false
    for _, spaces in pairs(all_spaces) do
        for _, space_id in ipairs(spaces) do
            if space_id == current_space then
                found = true
                break
            end
        end
    end
    if found then
        print("\n✓ Current space", current_space, "is in the list")
    else
        print("\n✗ WARNING: Current space", current_space, "is NOT in the list of all spaces")
    end
end

-- Test 5: Check menubar
local space_menubar = require "modules.space_menubar"
print("\n✓ Space menubar module loaded")

-- Test 6: Check space manager state
local space_manager = require "modules.space_manager"
local definitions = space_manager.get_space_definitions()
print("\n✓ Space definitions:", #definitions or 0)
for space_id, def in pairs(definitions) do
    print("  Space", space_id .. ":", def.name, "(created:", os.date("%Y-%m-%d %H:%M:%S", def.created_at) .. ")")
end

print("\n========== Test Complete ==========")
