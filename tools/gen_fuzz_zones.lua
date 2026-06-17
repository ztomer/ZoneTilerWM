-- tools/gen_fuzz_zones.lua
-- Emits one random zone scenario as JSON on stdout, seeded. Uses the real config.toml's
-- ZoneConfig and randomizes screen name (matching & non-matching), resolution, and
-- resize offsets to exercise detection branches + offset arithmetic.
--
--   lua tools/gen_fuzz_zones.lua <seed>

package.path = package.path .. ';./?.lua'

require('tests.mock_hs')
hs.configdir = os.getenv('PWD')

local json = require('tools.json')

-- config.lua prints a banner to stdout on load; silence it so only JSON reaches stdout.
local real_print = print
_G.print = function() end
local config = require('modules.config')
_G.print = real_print

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

local names = {
  'DELL U3223QE', 'DELL U3219Q', 'LG IPS QHD', 'Built-in Retina Display',
  'Color LCD', 'MacBook Pro', 'internal display', 'Acme 5000', 'Random Monitor', 'VX2758',
}
local widths = { 1280, 1440, 1920, 2560, 3440, 3840 }
local heights = { 800, 900, 1080, 1440, 1600, 2160, 2560 }

local name = names[math.random(#names)]
local w = widths[math.random(#widths)]
local h = heights[math.random(#heights)]

local offsets = nil
if math.random() < 0.5 then
  offsets = { x = {}, y = {} }
  offsets.x[tostring(math.random(1, 3))] = math.random(-5, 5) / 100
  offsets.y[tostring(math.random(1, 2))] = math.random(-5, 5) / 100
end

io.write(json.encode({
  screen = { name = name, frame = { x = 0, y = 0, w = w, h = h }, uuid = 'Mf' },
  config = zone_config,
  offsets = offsets,
}))
