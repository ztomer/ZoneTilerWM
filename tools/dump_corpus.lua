-- tools/dump_corpus.lua
-- Converts tests/solver_corpus.lua scenarios into language-neutral JSON fixtures
-- (the shared differential-testing contract). Writes inputs to tools/fixtures/solver/.
-- Mirrors the data shaping in tests/run_corpus.lua (screen 1000x1000, memory as a single
-- ranked preference with count=10).
--
-- Run from repo root:  lua tools/dump_corpus.lua

package.path = package.path .. ';./?.lua'

local json = require('tools.json')
local corpus = require('tests.solver_corpus')

local OUT_DIR = 'tools/fixtures/solver'
os.execute('mkdir -p ' .. OUT_DIR)

local function slug(name)
  return (name:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''))
end

for i, scen in ipairs(corpus.scenarios) do
  local windows = {}
  for _, wdef in ipairs(scen.windows) do
    local w = { id = wdef.id, w = wdef.w, h = wdef.h }
    if wdef.memory_zone then
      w.memory = { { zone_key = wdef.memory_zone, tile_index = 1, count = 10 } }
    end
    windows[#windows + 1] = w
  end

  local tiles = {}
  for _, tdef in ipairs(scen.tiles) do
    tiles[#tiles + 1] = { zone = tdef.zone, idx = tdef.idx, rect = tdef.rect }
  end

  local scenario = {
    name = scen.name,
    screen = { x = 0, y = 0, w = 1000, h = 1000 },
    windows = windows,
    tiles = tiles,
  }

  local fname = string.format('%s/%02d_%s.json', OUT_DIR, i, slug(scen.name))
  local f = assert(io.open(fname, 'w'))
  f:write(json.encode(scenario))
  f:close()
  print('wrote ' .. fname)
end

print(string.format('Dumped %d fixtures to %s', #corpus.scenarios, OUT_DIR))
