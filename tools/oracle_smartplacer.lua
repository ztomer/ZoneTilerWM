-- tools/oracle_smartplacer.lua
-- Headless differential-testing oracle for smart_placer.find_best_tile.
-- Stubs zone_calculator/monitor_manager/window_state_manager and injects
-- hs.geometry.intersectionRect (CGRectIntersection semantics). Passes zones via an
-- occupied_frames override so neither window_cache nor live state is touched.
--
--   lua tools/oracle_smartplacer.lua < scenario.json
--
-- Scenario contract:
--   { "screen": {x,y,w,h},
--     "zones": [ {"zone_key", "tiles": [ {x,y,w,h} ]} ],
--     "occupied": [ {x,y,w,h} ]? }
-- Result: { "found": bool, "zone_key", "tile_index", "tile": {x,y,w,h}, "overlap_ratio" }

package.path = package.path .. ';./?.lua'
require('tests.mock_hs')
_G.print = function() end -- silence module debug logs; result goes via io.write

local json = require('tools.json')
local scen = json.decode(io.read('*a'))

-- CGRectIntersection-style intersection (nil when disjoint), matching the Swift port.
hs.geometry = hs.geometry or {}
hs.geometry.intersectionRect = function(a, b)
  local ix = math.max(a.x, b.x)
  local iy = math.max(a.y, b.y)
  local iw = math.min(a.x + a.w, b.x + b.w) - ix
  local ih = math.min(a.y + a.h, b.y + b.h) - iy
  if iw <= 0 or ih <= 0 then return nil end
  return { x = ix, y = iy, w = iw, h = ih }
end

-- Map zone_key -> tiles, and a layouts table whose keys drive smart_placer's iteration.
local zones_by_key = {}
local layout_zones = {}
for _, z in ipairs(scen.zones or {}) do
  zones_by_key[z.zone_key] = z.tiles
  layout_zones[z.zone_key] = true
end

local cfg = {
  tiler = {
    smart_placement = { enabled = true, exclude_apps = {} },
    layouts = { L = layout_zones },
  },
}

local zc_stub = {
  get_layout_config = function(_screen) return nil, 'L' end,
  get = function(_mid, zone_key) return zones_by_key[zone_key] end,
}
local mm_stub = { get_id = function(_screen) return 'M1' end }
local wsm_stub = { get = function(_id) return nil end }
local wa_stub = {}

local smart_placer = require('modules.smart_placer')
smart_placer.init(cfg, mm_stub, zc_stub, wsm_stub, wa_stub, function() end)

local sf = scen.screen
local window = {
  isStandard = function() return true end,
  isMinimized = function() return false end,
  application = function() return { name = function() return 'App' end } end,
  screen = function()
    return { frame = function() return sf end, id = function() return 1 end }
  end,
  id = function() return 999 end,
  frame = function() return { x = sf.x, y = sf.y, w = 100, h = 100 } end,
}

local best = smart_placer.find_best_tile(window, scen.occupied or {})

local out
if best then
  out = {
    found = true,
    zone_key = best.zone_key,
    tile_index = best.tile_index,
    tile = { x = best.tile.x, y = best.tile.y, w = best.tile.w, h = best.tile.h },
    overlap_ratio = best.overlap_ratio,
  }
else
  out = { found = false }
end

io.write(json.encode(out))
