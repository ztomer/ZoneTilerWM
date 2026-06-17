-- tools/gen_fuzz_autotiler.lua
-- Emits one random auto-tiler scenario as JSON on stdout, seeded. Uses the real config.toml
-- grids/layouts; randomizes screen, window set (sizes, recency, z-order), focused window,
-- working-set params, mode, and per-app memory. Some windows are made stale to exercise the
-- limbo path; some apps carry memory to exercise greedy placement.
--
--   lua tools/gen_fuzz_autotiler.lua <seed>

package.path = package.path .. ';./?.lua'
require('tests.mock_hs')
hs.configdir = os.getenv('PWD')
local json = require('tools.json')

local real_print = print
_G.print = function() end
local config = require('modules.config')
_G.print = real_print

local seed = tonumber(arg[1] or '1')
math.randomseed(seed)

local tiler = {
  auto_tile_center_zones = config.tiler.auto_tile_center_zones or { 'j', 'center', '0' },
  working_set = { time_limit_sec = 1800, max_capacity = math.random(2, 6) },
  auto_tiling_mode = (math.random() < 0.5) and 'usage' or 'session',
  solver_weights = config.tiler.solver_weights,
  grids = config.tiler.grids,
  layouts = config.tiler.layouts,
  custom_screens = config.tiler.custom_screens,
  screen_detection = {
    patterns = config.tiler.screen_detection and config.tiler.screen_detection.patterns,
    portrait = config.tiler.screen_detection and config.tiler.screen_detection.portrait,
  },
  margins = config.tiler.margins,
}

local screen_choices = {
  { uuid = 'M1', name = 'Generic FHD', id = 1, frame = { x = 0, y = 0, w = 1920, h = 1080 } },
  { uuid = 'M1', name = 'Generic QHD', id = 1, frame = { x = 0, y = 0, w = 2560, h = 1440 } },
  { uuid = 'M1', name = 'DELL U3223QE', id = 1, frame = { x = 0, y = 0, w = 3840, h = 2160 } },
  { uuid = 'M1', name = 'Built-in Retina Display', id = 1, frame = { x = 0, y = 0, w = 1512, h = 982 } },
}
local screens = { screen_choices[math.random(#screen_choices)] }

local apps = { 'Safari', 'Code', 'Term', 'Music', 'Notes', 'Mail' }
local now = 1000000
local nwin = math.random(1, 7)
local windows, z_order = {}, {}
for i = 1, nwin do
  local stale = math.random() < 0.25
  local lf = now - (stale and math.random(2000, 4000) or math.random(0, 1000))
  windows[i] = {
    id = i,
    app = apps[math.random(#apps)],
    monitor = 'M1',
    frame = { x = math.random(0, 8) * 100, y = math.random(0, 5) * 100,
              w = math.random(3, 12) * 100, h = math.random(2, 8) * 100 },
    last_focused_time = lf,
    isStandard = true,
    isMinimized = false,
  }
  z_order[i] = i
end
for i = #z_order, 2, -1 do
  local j = math.random(i)
  z_order[i], z_order[j] = z_order[j], z_order[i]
end

local focused = (math.random() < 0.8) and math.random(nwin) or nil

local zone_pool = { 'h', 'j', 'k', 'l', 'i', 'u', 'y', 'n', 'm' }
local memory = {}
for _, app in ipairs(apps) do
  if math.random() < 0.5 then
    memory[app] = { {
      zone_key = zone_pool[math.random(#zone_pool)],
      tile_index = math.random(1, 2),
      count = math.random(1, 20),
    } }
  end
end

io.write(json.encode({
  now = now,
  config = tiler,
  screens = screens,
  windows = windows,
  z_order = z_order,
  focused_id = focused,
  -- Omit when empty: the JSON encoder can't distinguish {} from [], and Swift needs an
  -- object here. Absent memory means "no preferences" on both sides.
  memory = next(memory) and memory or nil,
}))
