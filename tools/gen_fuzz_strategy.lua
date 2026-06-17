-- tools/gen_fuzz_strategy.lua
-- Emits one random placement-strategy scenario as JSON on stdout, seeded. Exercises rotate
-- and largest_free_space, including current-frame-matches-a-tile, already-in-zone cycling,
-- all-blocked fallback, and missing state.
--
--   lua tools/gen_fuzz_strategy.lua <seed>

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

local strategies = { 'rotate', 'largest_free_space', 'hybrid' }
local strategy = strategies[math.random(#strategies)]

local nt = math.random(1, 5)
local tiles = {}
for i = 1, nt do tiles[i] = rect() end

-- current frame: half the time exactly one of the tiles (to trigger current-match paths).
local current_frame
if math.random() < 0.5 then
  local t = tiles[math.random(nt)]
  current_frame = { x = t.x, y = t.y, w = t.w, h = t.h }
else
  current_frame = rect()
end

-- current state present ~60% of the time.
local state = nil
if math.random() < 0.6 then
  state = {
    zone_key = (math.random() < 0.5) and 'h' or 'k',
    tile_index = math.random(1, nt),
  }
end

-- occupied windows (other than self id 999).
local occupied = {}
local no = math.random(0, 4)
for i = 1, no do
  occupied[i] = { id = math.random(1, 50), frame = rect() }
end

io.write(json.encode({
  strategy = strategy,
  tiles = tiles,
  zone_key = 'h',
  current = { frame = current_frame, state = state },
  occupied = occupied,
}))
