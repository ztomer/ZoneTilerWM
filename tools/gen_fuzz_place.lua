-- tools/gen_fuzz_place.lua
-- Emits one random smart-placer scenario as JSON on stdout, seeded. Random zones/tiles and
-- occupied frames over a fixed screen, exercising the scoring + overlap math.
--
--   lua tools/gen_fuzz_place.lua <seed>

package.path = package.path .. ';./?.lua'
local json = require('tools.json')

local seed = tonumber(arg[1] or '1')
math.randomseed(seed)

local SW, SH = 1920, 1080
local function rect()
  local w = math.random(2, 9) * 100
  local h = math.random(2, 9) * 100
  local x = math.random(0, math.max(0, (SW - w) // 100)) * 100
  local y = math.random(0, math.max(0, (SH - h) // 100)) * 100
  return { x = x, y = y, w = w, h = h }
end

local nz = math.random(1, 4)
local zones = {}
for i = 1, nz do
  local nt = math.random(1, 4)
  local tiles = {}
  for j = 1, nt do tiles[j] = rect() end
  zones[i] = { zone_key = 'Z' .. i, tiles = tiles }
end

local no = math.random(0, 5)
local occupied = {}
for i = 1, no do occupied[i] = rect() end

io.write(json.encode({
  screen = { x = 0, y = 0, w = SW, h = SH },
  zones = zones,
  occupied = occupied,
}))
