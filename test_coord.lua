-- Trace coordinate parsing
local coords_tests = {"a1", "a1:a2", "a1:b1", "a1:b2"}

local function test_coord(coords)
    local col_start_char, row_start_str, col_end_char, row_end_str = coords:match(
        "([a-z])([0-9]+):?([a-z]?)([0-9]*)")
    
    local col_start = string.byte(col_start_char) - string.byte('a') + 1
    local row_start = tonumber(row_start_str)
    local col_end = col_end_char ~= "" and (string.byte(col_end_char) - string.byte('a') + 1) or col_start
    local row_end = row_end_str ~= "" and tonumber(row_end_str) or row_start
    
    local num_cols = col_end - col_start + 1
    local num_rows = row_end - row_start + 1
    
    print(coords .. " -> col_start="..col_start.." col_end="..col_end.." num_cols="..num_cols.." row_start="..row_start.." row_end="..row_end.." num_rows="..num_rows)
end

for _, c in ipairs(coords_tests) do
    test_coord(c)
end