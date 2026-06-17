-- tools/gen_fuzz_movezone.lua
-- Random move-to-zone scenarios from the real config.toml: a landscape screen, a zone key
-- present in all landscape layouts, a placement strategy, a focused-window frame, and some
-- occupied windows.
--
--   lua tools/gen_fuzz_movezone.lua <seed>

package.path = package.path .. ';./?.lua'
require('tests.mock_hs')
hs.configdir = os.getenv('PWD')
local json = require('tools.json')
local real_print = print; _G.print = function() end
local config = require('modules.config'); _G.print = real_print

local seed = tonumber(arg[1] or '1')
math.randomseed(seed)

local zone_config = {
  grids = config.tiler.grids,
  layouts = config.tiler.layouts,
  margins = config.tiler.margins,
  custom_screens = config.tiler.custom_screens,
  screen_detection = {
    patterns = config.tiler.screen_detection and config.tiler.screen_detection.patterns,
    portrait = config.tiler.screen_detection and config.tiler.screen_detection.portrait,
  },
}

-- Landscape screens only; zone keys present across 2x2/3x2/3x3/4x3.
local screens = {
  { name = 'Generic FHD', w = 1920, h = 1080 },
  { name = 'Generic QHD', w = 2560, h = 1440 },
  { name = 'DELL U3223QE', w = 3840, h = 2160 },
  { name = 'Built-in Retina Display', w = 1512, h = 982 },
}
local zone_keys = { 'h', 'j', 'k', 'y', 'u', 'n', 'm', 'i', ',' }
local strategies = { 'rotate', 'largest_free_space', 'hybrid' }

local sc = screens[math.random(#screens)]
local function frameIn(W, H)
  local w = math.random(2, 9) * 100
  local h = math.random(2, 8) * 100
  local x = math.random(0, math.max(0, (W - w) // 100)) * 100
  local y = math.random(0, math.max(0, (H - h) // 100)) * 100
  return { x = x, y = y, w = w, h = h }
end

local occupied = {}
for i = 1, math.random(0, 4) do occupied[i] = { id = math.random(1, 50), frame = frameIn(sc.w, sc.h) } end

io.write(json.encode({
  screen = { name = sc.name, frame = { x = 0, y = 0, w = sc.w, h = sc.h } },
  config = zone_config,
  zone_key = zone_keys[math.random(#zone_keys)],
  strategy = strategies[math.random(#strategies)],
  window = { frame = frameIn(sc.w, sc.h) },
  occupied = occupied,
  self_id = 999,
}))
