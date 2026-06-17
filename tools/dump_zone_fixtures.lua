-- tools/dump_zone_fixtures.lua
-- Builds zone-calculator fixtures from the REAL config.toml: extracts the ZoneConfig
-- subset and pairs it with a set of representative screens (exact custom match, pattern
-- match, portrait/landscape defaults, small fallback). Writes inputs to tools/fixtures/zones/.
--
--   lua tools/dump_zone_fixtures.lua

package.path = package.path .. ';./?.lua'

require('tests.mock_hs')
hs.configdir = os.getenv('PWD')

local json = require('tools.json')
local config = require('modules.config')

local OUT_DIR = 'tools/fixtures/zones'
os.execute('mkdir -p ' .. OUT_DIR)

-- Only the subset ZoneCalculator reads (screen_detection.sizes is unused by the code).
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

-- (name, w, h) chosen to exercise each detection branch.
local screens = {
  { name = 'DELL U3223QE',            w = 3840, h = 2160 }, -- custom exact -> 4x3
  { name = 'LG IPS QHD',              w = 1440, h = 2560 }, -- custom exact (portrait) -> 1x3
  { name = 'DELL U3219Q',             w = 3840, h = 2160 }, -- pattern "DELL.*U32" -> 4x3
  { name = 'Built-in Retina Display', w = 1512, h = 982  }, -- pattern "Built[-]?in" -> 2x2
  { name = 'Color LCD',               w = 1440, h = 900  }, -- pattern "Color LCD" -> 2x2
  { name = 'Acme UltraWide',          w = 3440, h = 1440 }, -- landscape default (>=3440) -> 4x3
  { name = 'Generic FHD',             w = 1920, h = 1080 }, -- landscape default -> 3x2
  { name = 'Generic QHD',             w = 2560, h = 1440 }, -- landscape default -> 3x3
  { name = 'Tiny Panel',              w = 1280, h = 800  }, -- landscape default -> 2x2
  { name = 'Portrait Tall',           w = 1440, h = 2560 }, -- portrait default -> portrait.large
}

local function slug(name) return (name:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')) end

for i, s in ipairs(screens) do
  local scenario = {
    screen = { name = s.name, frame = { x = 0, y = 0, w = s.w, h = s.h }, uuid = 'M' .. i },
    config = zone_config,
  }
  local fname = string.format('%s/%02d_%s.json', OUT_DIR, i, slug(s.name))
  local f = assert(io.open(fname, 'w'))
  f:write(json.encode(scenario))
  f:close()
  print('wrote ' .. fname)
end

print(string.format('Dumped %d zone fixtures to %s', #screens, OUT_DIR))
