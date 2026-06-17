-- tools/gen_fuzz.lua
-- Emits one random-but-valid solver scenario as JSON on stdout, seeded for reproducibility.
-- Exercises overlapping tiles, exact/zone memory matches, varied aspect ratios and sizes —
-- the long tail the 7-case corpus can't cover.
--
--   lua tools/gen_fuzz.lua <seed>

package.path = package.path .. ';./?.lua'
local json = require('tools.json')

local seed = tonumber(arg[1] or '1')
math.randomseed(seed)

local SW, SH = 1000, 1000
local function ri(a, b) return math.random(a, b) end

-- Tiles first, so memory prefs can reference real zones.
local ntile = ri(2, 6)
local tiles = {}
for j = 1, ntile do
  local tw = ri(2, 9) * 100
  local th = ri(2, 9) * 100
  local x = ri(0, math.max(0, (SW - tw) // 100)) * 100
  local y = ri(0, math.max(0, (SH - th) // 100)) * 100
  tiles[j] = {
    zone = 'Z' .. j,
    idx = ri(1, 4),
    rect = { x = x, y = y, w = tw, h = th },
  }
end

local nwin = ri(1, 5)
local windows = {}
for i = 1, nwin do
  local w = { id = 'W' .. i, w = ri(1, 9) * 100, h = ri(1, 9) * 100 }
  -- ~40% of windows carry a memory preference referencing a random tile's zone.
  if math.random() < 0.4 then
    local t = tiles[ri(1, ntile)]
    -- Half exact (same tile_index), half zone-only (different tile_index).
    local ti = (math.random() < 0.5) and t.idx or (t.idx + 1)
    w.memory = { { zone_key = t.zone, tile_index = ti, count = ri(1, 20) } }
  end
  windows[i] = w
end

io.write(json.encode({
  name = 'fuzz_' .. seed,
  screen = { x = 0, y = 0, w = SW, h = SH },
  windows = windows,
  tiles = tiles,
}))
