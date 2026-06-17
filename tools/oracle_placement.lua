-- tools/oracle_placement.lua
-- Headless differential-testing oracle for placement_strategy.find_best_tile.
-- Stubs window_state_manager + window_cache so the rotate / largest_free_space logic runs
-- without Hammerspoon. Self window id is 999 (distinct from occupied ids).
--
--   lua tools/oracle_placement.lua < scenario.json
--
-- Scenario contract:
--   { "strategy": "rotate"|"largest_free_space"|"hybrid",
--     "tiles": [ {x,y,w,h} ],
--     "zone_key": "h",
--     "current": { "frame": {x,y,w,h}, "state": {zone_key, tile_index}|null },
--     "occupied": [ {id, frame:{x,y,w,h}} ]?,
--     "self_id": 999? }
-- Result: { "found": bool, "tile": {x,y,w,h}? }

package.path = package.path .. ';./?.lua'
require('tests.mock_hs')
_G.print = function() end

local json = require('tools.json')
local scen = json.decode(io.read('*a'))

local SELF_ID = scen.self_id or 999

-- window_cache stub: get_for_screen_with_cache -> occupied info entries.
local occupied_info = {}
for _, e in ipairs(scen.occupied or {}) do
  occupied_info[#occupied_info + 1] = {
    window = { id = function() return e.id end },
    frame = e.frame,
  }
end
package.loaded['modules.window_cache'] = {
  get_for_screen_with_cache = function(_sid) return occupied_info end,
}

local cfg = { tiler = { placement_strategy = scen.strategy } }
local wsm_stub = {
  get = function(_id) return scen.current.state end, -- {zone_key, tile_index} or nil
}

local placement_strategy = require('modules.placement_strategy')
placement_strategy.init(cfg, wsm_stub)

local cf = scen.current.frame
local window = {
  id = function() return SELF_ID end,
  screen = function()
    return { id = function() return 1 end, frame = function() return { x = 0, y = 0, w = 1920, h = 1080 } end }
  end,
  frame = function() return cf end,
}

local tile = placement_strategy.find_best_tile(window, scen.zone_key, {}, nil, scen.tiles)

if tile then
  io.write(json.encode({ found = true, tile = { x = tile.x, y = tile.y, w = tile.w, h = tile.h } }))
else
  io.write(json.encode({ found = false }))
end
