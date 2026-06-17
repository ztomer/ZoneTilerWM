-- tools/oracle_solver.lua
-- Headless differential-testing oracle for modules/layout_solver.lua.
-- Reads a JSON scenario on stdin, runs the solver, writes JSON results on stdout.
-- No Hammerspoon required (layout_solver only needs debug.init, which loads headless).
--
-- Run from repo root:  lua tools/oracle_solver.lua < scenario.json
--
-- Scenario contract (input):
--   { "screen": {"x","y","w","h"},
--     "windows": [ {"id", "w", "h",
--                   "memory": [ {"zone_key","tile_index","count"} ]? } ],
--     "tiles":   [ {"zone", "idx", "rect": {"x","y","w","h"}} ] }
-- Result contract (output):
--   { "assignments": [ {"window_id","zone_key","tile_index","cost"} ]  (sorted by window_id),
--     "total_cost": <number>, "placed": <int> }

package.path = package.path .. ';./?.lua'

local json = require('tools.json')
local layout_solver = require('modules.layout_solver')

--------------------------------------------------------------------------------
-- Mock window (mirrors tests/run_corpus.lua's MockWindow)
--------------------------------------------------------------------------------
local function make_window(wdef, screen_rect)
  return {
    frame = function() return { w = wdef.w, h = wdef.h } end,
    screen = function()
      return { frame = function() return screen_rect end }
    end,
    application = function()
      return { name = function() return wdef.id end }
    end,
    id = function() return wdef.id end,
  }
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------
local input = io.read('*a')
local scen = json.decode(input)

local screen_rect = scen.screen or { x = 0, y = 0, w = 1000, h = 1000 }

-- Per-window memory preferences, keyed by app name (= window id), injected into the solver.
local memory = {}
local windows = {}
for _, wdef in ipairs(scen.windows or {}) do
  windows[#windows + 1] = make_window(wdef, screen_rect)
  if wdef.memory then
    memory[wdef.id] = wdef.memory
  end
end

layout_solver.init({
  get_ranked_preferences = function(app_name, _mid)
    return memory[app_name] or {}
  end,
})

local tiles = {}
for _, tdef in ipairs(scen.tiles or {}) do
  tiles[#tiles + 1] = {
    rect = tdef.rect,
    zone_key = tdef.zone,
    tile_index = tdef.idx,
    monitor_id = 'oracle_mid',
  }
end

local moves = layout_solver.solve(windows, tiles, 'oracle_mid')

local assignments = {}
local total_cost = 0
for _, m in ipairs(moves) do
  assignments[#assignments + 1] = {
    window_id = m.window:application():name(),
    zone_key = m.tile.zone_key,
    tile_index = m.tile.tile_index,
    cost = m.cost,
  }
  total_cost = total_cost + (m.cost or 0)
end

-- Stable order: assignment set is order-independent, so sort for deterministic diffs.
table.sort(assignments, function(a, b) return a.window_id < b.window_id end)

io.write(json.encode({
  assignments = assignments,
  total_cost = total_cost,
  placed = #assignments,
}))
