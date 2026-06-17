-- tools/oracle_zones.lua
-- Headless differential-testing oracle for modules/zone_calculator.lua.
-- Reads a JSON scenario on stdin, computes the monitor's zones, writes JSON on stdout.
-- Stubs resize_manager + monitor_manager so no Hammerspoon-coupled code is pulled in.
--
--   lua tools/oracle_zones.lua < scenario.json
--
-- Scenario contract (input):
--   { "screen": {"name", "frame": {x,y,w,h}, "uuid"? },
--     "config": <ZoneConfig: grids, layouts, margins, screen_detection, custom_screens>,
--     "offsets"?: { axis -> { indexString -> pct } } }
-- Result contract (output): { "layout_key", "zones": { zone_key -> [ {x,y,w,h} ] } }

package.path = package.path .. ';./?.lua'

require('tests.mock_hs')  -- sets _G.hs (zone_calculator captures hs.screen at load)

local json = require('tools.json')
local scen = json.decode(io.read('*a'))

-- Offsets come from the scenario (default 0), matching the Swift OffsetProvider.
local offsets = scen.offsets or {}
package.loaded['modules.resize_manager'] = {
  init = function() end,
  get_offset = function(_mid, axis, index)
    local ax = offsets[axis]
    return (ax and ax[tostring(index)]) or 0
  end,
}
package.loaded['modules.monitor_manager'] = {
  get_id = function(screen) return screen:getUUID() end,
}

local zone_calculator = require('modules.zone_calculator')

-- Build the config shape zone_calculator expects (it reads config.tiler.*).
local cfg = {
  tiler = {
    grids = scen.config.grids,
    layouts = scen.config.layouts,
    custom_screens = scen.config.custom_screens,
    screen_detection = scen.config.screen_detection,
    margins = scen.config.margins,
  },
}
zone_calculator.init(cfg, scen.config.margins, function() end)

local f = scen.screen.frame
local screen = {
  frame = function() return f end,
  name = function() return scen.screen.name end,
  getUUID = function() return scen.screen.uuid or 'M1' end,
}

-- Resolve the layout key the same way create_for_monitor does (with 2x2 fallback).
local grid_config, layout_key = zone_calculator.get_layout_config(screen)
if not (grid_config and layout_key) then layout_key = '2x2' end

zone_calculator.create_for_monitor('M1', screen)

-- Collect tiles for every zone key defined by the resolved layout.
local zone_defs = scen.config.layouts[layout_key] or scen.config.layouts['default'] or {}
local zones = {}
for zone_key in pairs(zone_defs) do
  if zone_key ~= 'default' then
    local tiles = zone_calculator.get('M1', zone_key)
    if tiles and #tiles > 0 then
      local out_tiles = {}
      for _, t in ipairs(tiles) do
        out_tiles[#out_tiles + 1] = { x = t.x, y = t.y, w = t.w, h = t.h }
      end
      zones[zone_key] = out_tiles
    end
  end
end

io.write(json.encode({ layout_key = layout_key, zones = zones }))
