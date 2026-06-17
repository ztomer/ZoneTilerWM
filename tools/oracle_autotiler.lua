-- tools/oracle_autotiler.lua
-- Headless differential-testing oracle for auto_tiler.tile_all_windows (the 4-pass cascade
-- + working-set cull + BSP + fill-gaps). Runs the REAL auto_tiler + zone_calculator +
-- layout_solver, stubbing the live-system deps (focused window, z-order, window_cache,
-- monitor_manager, window_actions, window_state_manager) and capturing the moves that would
-- be applied instead of applying them. Clock is injected via auto_tiler._now.
--
--   lua tools/oracle_autotiler.lua < scenario.json
--
-- Scenario contract:
--   { "now": int,
--     "config": <tiler config: auto_tile_center_zones, working_set{time_limit_sec,max_capacity},
--                auto_tiling_mode, solver_weights?, grids, layouts, custom_screens?,
--                screen_detection?, margins?>,
--     "screens": [ {uuid, name, id, frame:{x,y,w,h}} ],
--     "windows": [ {id, app, monitor(uuid), frame:{x,y,w,h}, last_focused_time,
--                   isStandard?, isMinimized?} ],
--     "z_order": [ window_id... ]  (front to back),
--     "focused_id": int|null,
--     "memory": { app_name: [ {zone_key, tile_index, count} ] } }
-- Result: { "moves": [ {window_id, monitor_id, zone_key, tile_index, rect:{x,y,w,h}} ] }
--          (sorted by window_id)

package.path = package.path .. ';./?.lua'
require('tests.mock_hs')
_G.print = function() end

local json = require('tools.json')
local scen = json.decode(io.read('*a'))

local cfg = { tiler = scen.config, keys = {} }

-- Screens -------------------------------------------------------------------
local screens_by_uuid, screens_by_id, screen_list = {}, {}, {}
for _, s in ipairs(scen.screens) do
  local sf = s.frame
  local screen = {
    _uuid = s.uuid,
    getUUID = function() return s.uuid end,
    name = function() return s.name end,
    id = function() return s.id end,
    frame = function() return sf end,
  }
  screens_by_uuid[s.uuid] = screen
  screens_by_id[s.id] = screen
  screen_list[#screen_list + 1] = screen
end

-- Windows -------------------------------------------------------------------
local windows_by_id = {}
for _, w in ipairs(scen.windows) do
  local wf = w.frame
  windows_by_id[w.id] = {
    id = function() return w.id end,
    isStandard = function() return w.isStandard ~= false end,
    isMinimized = function() return w.isMinimized == true end,
    application = function() return { name = function() return w.app end } end,
    screen = function() return screens_by_uuid[w.monitor] end,
    frame = function() return wf end,
  }
end

local ordered = {}
for _, id in ipairs(scen.z_order or {}) do
  if windows_by_id[id] then ordered[#ordered + 1] = windows_by_id[id] end
end

-- hs.* mocks ----------------------------------------------------------------
hs.window.focusedWindow = function()
  return scen.focused_id and windows_by_id[scen.focused_id] or nil
end
hs.window.orderedWindows = function() return ordered end
hs.screen.allScreens = function() return screen_list end
hs.screen.find = function(id) return screens_by_id[id] end

-- window_cache stub
local visible_info, info_by_id = {}, {}
for _, w in ipairs(scen.windows) do
  local sc = screens_by_uuid[w.monitor]
  visible_info[#visible_info + 1] = {
    window = windows_by_id[w.id],
    screen_id = sc and sc:id(),
    app_name = w.app,
    last_focused_time = w.last_focused_time,
  }
  info_by_id[w.id] = { last_focused_time = w.last_focused_time }
end
package.loaded['modules.window_cache'] = {
  get_all_visible_info = function() return visible_info end,
  get_info = function(id) return info_by_id[id] end,
  update = function() end,
  get_for_screen_with_cache = function() return {} end,
}

-- zone_calculator deps (must be stubbed before requiring it)
package.loaded['modules.resize_manager'] = { init = function() end, get_offset = function() return 0 end }
package.loaded['modules.monitor_manager'] = {
  get_id = function(screen) return screen and screen._uuid end,
  get_screen = function(mid) return screens_by_uuid[mid] end,
}

-- Capture moves instead of applying them.
local recorded, pending_rect = {}, {}
package.loaded['modules.window_state_manager'] = {
  set = function(id, mid, zone, tile, _suppress)
    recorded[#recorded + 1] = {
      window_id = id, monitor_id = mid, zone_key = zone, tile_index = tile, rect = pending_rect[id],
    }
  end,
}
local window_actions = {
  apply_frame = function(window, rect) pending_rect[window:id()] = rect; return true end,
  position_window_from_memory = function(window, mid, zone, tile, _suppress)
    recorded[#recorded + 1] = {
      window_id = window:id(), monitor_id = mid, zone_key = zone, tile_index = tile,
    }
    return true
  end,
}

local window_memory = {
  get_ranked_preferences = function(app, _mid)
    return (scen.memory and scen.memory[app]) or {}
  end,
}

-- Wire up and run -----------------------------------------------------------
local zone_calculator = require('modules.zone_calculator')
zone_calculator.init(cfg, cfg.tiler.margins, function() end)
local monitor_manager = package.loaded['modules.monitor_manager']

local auto_tiler = require('modules.auto_tiler')
auto_tiler.init(cfg, nil, window_memory, nil, zone_calculator, monitor_manager, window_actions)
auto_tiler._now = scen.now
auto_tiler.tile_all_windows()

table.sort(recorded, function(a, b) return a.window_id < b.window_id end)
io.write(json.encode({ moves = recorded }))
