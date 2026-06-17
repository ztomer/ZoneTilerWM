-- tools/gen_fuzz_memory.lua
-- Emits one random window-memory scenario as JSON on stdout, seeded. Small pools for apps/
-- monitors/zones/tiles/windowIds so learns collide (accumulating counts + running means)
-- and same-window repositions exercise the debounce/cancel path. Includes an excluded app.
--
--   lua tools/gen_fuzz_memory.lua <seed>

package.path = package.path .. ';./?.lua'
local json = require('tools.json')

local seed = tonumber(arg[1] or '1')
math.randomseed(seed)

local apps = { 'Safari', 'Code', 'Term', 'Excluded' }
local monitors = { 'M1', 'M2' }
local zones = { 'h', 'j', 'k', 'y' }
local window_ids = { 1, 2, 3 }

local function dim() return math.random(2, 9) * 100 end

local nev = math.random(3, 14)
local events = {}
for _ = 1, nev do
  if math.random() < 0.25 then
    events[#events + 1] = { op = 'flush' }
  else
    events[#events + 1] = {
      op = 'position',
      windowId = window_ids[math.random(#window_ids)],
      app = apps[math.random(#apps)],
      monitor = monitors[math.random(#monitors)],
      zone = zones[math.random(#zones)],
      tile = math.random(1, 4),
      win = { w = dim(), h = dim() },
      screen = { w = 1920, h = 1080 },
    }
  end
end
events[#events + 1] = { op = 'flush' } -- settle everything at the end

local queries = {}
for _ = 1, 3 do
  queries[#queries + 1] = {
    app = apps[math.random(#apps)],
    monitor = monitors[math.random(#monitors)],
    zone = zones[math.random(#zones)],
  }
end

io.write(json.encode({
  config = { excluded_apps = { 'Excluded' }, settle_delay_sec = 2.0 },
  events = events,
  queries = queries,
}))
