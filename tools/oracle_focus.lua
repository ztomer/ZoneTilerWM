-- tools/oracle_focus.lua
-- Ground-truth oracle for focus_manager zone-window collection + ordering. Drives the real
-- collect_zone_windows + sort via a test seam, stubbing window_cache + window_state.
--
--   lua tools/oracle_focus.lua < scenario.json
--
-- Scenario: { monitor_id, zone_key, overlap_threshold,
--             zone_tiles:[{x,y,w,h}],
--             windows:[{id, app, frame:{x,y,w,h}, z_order}],
--             state: { "<id>": {monitor_id, zone_key, tile_index} } }
-- Result: { ordered: [ {window_id, tile_index, explicit, z_order} ] }

package.path = package.path .. ';./?.lua'
require('tests.mock_hs')
_G.print = function() end

local json = require('tools.json')
local scen = json.decode(io.read('*a'))

local cfg = { tiler = { overlap_threshold = scen.overlap_threshold or 0.5 } }

-- window_cache: per-screen info entries (window + app_name); the function calls win:frame().
local info_entries = {}
for _, w in ipairs(scen.windows or {}) do
  local wf = w.frame
  info_entries[#info_entries + 1] = {
    window = { id = function() return w.id end, frame = function() return wf end },
    app_name = w.app,
  }
end
package.loaded['modules.window_cache'] = {
  get_for_screen_with_cache = function() return info_entries end,
}

local window_state = {
  get = function(id)
    local s = scen.state and scen.state[tostring(id)]
    return s
  end,
}

local focus_manager = require('modules.focus_manager')
focus_manager.init(cfg, { get_id = function() return scen.monitor_id end }, {}, window_state, function() end)

-- z-order map from scenario.
local z_map = {}
for _, w in ipairs(scen.windows or {}) do z_map[w.id] = w.z_order end

local screen = { id = function() return 1 end }
local ordered = focus_manager._ordered_zone_windows(scen.monitor_id, scen.zone_key, screen, scen.zone_tiles, z_map)

local out = {}
for _, zw in ipairs(ordered) do
  out[#out + 1] = { window_id = zw.window_id, tile_index = zw.tile_index, explicit = zw.explicit, z_order = zw.z_order }
end
io.write(json.encode({ ordered = out }))
