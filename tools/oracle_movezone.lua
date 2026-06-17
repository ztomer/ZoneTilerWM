-- tools/oracle_movezone.lua
-- Ground-truth oracle for the move-to-zone DECISION (window_actions.move_window_to_zone's
-- core): compute the zone's tiles via the real zone_calculator, pick a tile via the real
-- placement_strategy.find_best_tile, report the chosen tile + its index. Diffed against the
-- Swift TilerCoordinator. Stubs the system deps; no Hammerspoon.
--
--   lua tools/oracle_movezone.lua < scenario.json
--
-- Scenario: { screen:{name,frame}, config:<ZoneConfig>, zone_key, strategy,
--             window:{frame}, occupied:[{id,frame}]?, self_id? }
-- Result: { found, zone_key, tile_index, rect:{x,y,w,h} }

package.path = package.path .. ';./?.lua'
require('tests.mock_hs')
_G.print = function() end

local json = require('tools.json')
local scen = json.decode(io.read('*a'))
local SELF_ID = scen.self_id or 999

-- Config: zone fields + the placement strategy (find_best_tile reads tiler.placement_strategy).
local cfg = {
  tiler = {
    grids = scen.config.grids,
    layouts = scen.config.layouts,
    custom_screens = scen.config.custom_screens,
    screen_detection = scen.config.screen_detection,
    margins = scen.config.margins,
    placement_strategy = scen.strategy,
  },
}

package.loaded['modules.resize_manager'] = { init = function() end, get_offset = function() return 0 end }
package.loaded['modules.monitor_manager'] = { get_id = function(s) return s:getUUID() end }

-- window_cache for placement's largest_free_space overlap calc.
local occupied_info = {}
for _, e in ipairs(scen.occupied or {}) do
  occupied_info[#occupied_info + 1] = { window = { id = function() return e.id end }, frame = e.frame }
end
package.loaded['modules.window_cache'] = {
  get_for_screen_with_cache = function() return occupied_info end,
}

local zone_calculator = require('modules.zone_calculator')
zone_calculator.init(cfg, cfg.tiler.margins, function() end)
local placement_strategy = require('modules.placement_strategy')
placement_strategy.init(cfg, { get = function(_id) return nil end })  -- no prior tiler state

local sf = scen.screen.frame
local screen = {
  getUUID = function() return 'M1' end,
  name = function() return scen.screen.name end,
  id = function() return 1 end,
  frame = function() return sf end,
}
zone_calculator.create_for_monitor('M1', screen)
local zone_tiles = zone_calculator.get('M1', scen.zone_key)

local wf = scen.window.frame
local window = {
  id = function() return SELF_ID end,
  screen = function() return screen end,
  frame = function() return wf end,
}

local tile = nil
if zone_tiles and #zone_tiles > 0 then
  tile = placement_strategy.find_best_tile(window, scen.zone_key, nil, nil, zone_tiles)
end

local out
if tile then
  local idx = 1
  for i, t in ipairs(zone_tiles) do if t == tile then idx = i; break end end
  out = { found = true, zone_key = scen.zone_key, tile_index = idx,
          rect = { x = tile.x, y = tile.y, w = tile.w, h = tile.h } }
else
  out = { found = false }
end

io.write(json.encode(out))
