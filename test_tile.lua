-- Test tile creation directly 
local config = require("modules.config")
local zone_calculator = require("modules.zone_calculator")

zone_calculator.init(config, config.tiler.margins, function() end)

local screen = hs.window.focusedWindow():screen()
local grid = config.tiler.grids["2x2"]

local tests = {
    {col_start=1, col_end=1, row_start=1, row_end=1, label="a1 (single)"},
    {col_start=1, col_end=1, row_start=1, row_end=2, label="a1:a2 (left half)"},
    {col_start=1, col_end=2, row_start=1, row_end=1, label="a1:b1 (top half)"},
}

local f = io.open(os.getenv("HOME").."/tile_test.log", "w")
f:write("Screen: "..screen:frame().w.."x"..screen:frame().h.."\n")
f:write("Grid: "..grid.cols.." cols, "..grid.rows.." rows\n\n")

for _, t in ipairs(tests) do
    local tile = zone_calculator.create_tile_from_grid_coords(screen, {
        col_start = t.col_start,
        row_start = t.row_start,
        num_cols = t.col_end - t.col_start + 1,
        num_rows = t.row_end - t.row_start + 1
    }, grid.rows, grid.cols)
    
    if tile then
        local line = t.label..": x="..tile.x.." y="..tile.y.." w="..tile.w.." h="..tile.h
        print(line)
        f:write(line.."\n")
    else
        local line = t.label..": FAILED"
        print(line)
        f:write(line.."\n")
    end
end

f:close()
print("Written to ~/tile_test.log")