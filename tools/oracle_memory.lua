-- tools/oracle_memory.lua
-- Headless differential-testing oracle for modules/window_memory.lua (pure learning logic).
-- Drives on_window_positioned with a DEFERRED timer mock + explicit flush, so the debounce/
-- cancel behavior is exercised faithfully. Stubs config + storage so no Hammerspoon-coupled
-- code runs. Uses the module's _save_to_disk test seam to serialize in-memory state.
--
--   lua tools/oracle_memory.lua < scenario.json
--
-- Scenario contract:
--   { "config": {"excluded_apps": [..], "settle_delay_sec": 2.0}?,
--     "events": [ {"op":"position", windowId, app, monitor, zone, tile,
--                  "win":{w,h}, "screen":{w,h}} | {"op":"flush"} ],
--     "queries": [ {"app","monitor","zone"?} ] }

package.path = package.path .. ';./?.lua'
require('tests.mock_hs')

-- window_memory's debug_log prints to stdout (it takes no log_func); silence print so only
-- the JSON result reaches stdout. Errors still go to stderr via error()/traceback.
_G.print = function() end

local json = require('tools.json')
local scen = json.decode(io.read('*a'))

-- Stub config + storage BEFORE requiring window_memory.
local wm_cfg = {
  window_memory = {
    excluded_apps = (scen.config and scen.config.excluded_apps) or {},
    settle_delay_sec = (scen.config and scen.config.settle_delay_sec) or 2.0,
    save_interval_sec = 0,
  },
  keys = {},
}
package.loaded['modules.config'] = wm_cfg

local saved_store = {}
package.loaded['modules.storage'] = {
  init = function() end,
  load = function(_k) return nil end,
  save = function(k, data) saved_store[k] = data; return true end,
}

-- Deferred timer mock (overrides mock_hs's immediate-fire doAfter).
local timer_queue = {}
local seq = 0
hs.timer.doAfter = function(_sec, fn)
  seq = seq + 1
  local t = { fn = fn, stopped = false, seq = seq }
  timer_queue[#timer_queue + 1] = t
  return { stop = function() t.stopped = true end }
end
local function flush_timers()
  for _, t in ipairs(timer_queue) do
    if not t.stopped then t.stopped = true; t.fn() end
  end
end

local window_memory = require('modules.window_memory')
window_memory.init(wm_cfg)

local function mock_window(e)
  return {
    isStandard = function() return true end,
    application = function() return { name = function() return e.app end } end,
    id = function() return e.windowId end,
    frame = function() return { w = e.win.w, h = e.win.h } end,
    screen = function() return { frame = function() return { w = e.screen.w, h = e.screen.h } end } end,
  }
end

for _, e in ipairs(scen.events or {}) do
  if e.op == 'position' then
    window_memory.on_window_positioned(mock_window(e), e.monitor, e.zone, e.tile)
  elseif e.op == 'flush' then
    flush_timers()
  end
end

-- Serialize current in-memory state (no live capture) via the test seam.
window_memory._save_to_disk()
local saved = saved_store['window_positions'] or { positions = {}, preferences = {} }

table.sort(saved.positions, function(a, b)
  if a.app_name ~= b.app_name then return a.app_name < b.app_name end
  return a.monitor_id < b.monitor_id
end)
table.sort(saved.preferences, function(a, b)
  if a.app_name ~= b.app_name then return a.app_name < b.app_name end
  if a.monitor_id ~= b.monitor_id then return a.monitor_id < b.monitor_id end
  if a.zone_key ~= b.zone_key then return a.zone_key < b.zone_key end
  return tostring(a.tile_index) < tostring(b.tile_index)
end)

local query_out = {}
for _, q in ipairs(scen.queries or {}) do
  local r = { app = q.app, monitor = q.monitor, zone = q.zone }
  r.remembered = window_memory.get_remembered_position(q.app, q.monitor)
  r.preferred_zone = window_memory.get_preferred_zone(q.app, q.monitor)
  if q.zone then r.preferred_tile = window_memory.get_preferred_tile(q.app, q.monitor, q.zone) end
  r.ranked = window_memory.get_ranked_preferences(q.app, q.monitor)
  query_out[#query_out + 1] = r
end

io.write(json.encode({ save = saved, queries = query_out }))
