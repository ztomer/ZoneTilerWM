-- tools/gen_fuzz_focus.lua — random focus collection scenario.
--   lua tools/gen_fuzz_focus.lua <seed>
package.path = package.path .. ';./?.lua'
local json = require('tools.json')
local seed = tonumber(arg[1] or '1'); math.randomseed(seed)
local function rect()
  local w=math.random(2,9)*100; local h=math.random(2,8)*100
  local x=math.random(0,10)*100; local y=math.random(0,8)*100
  return {x=x,y=y,w=w,h=h}
end
local ntiles = math.random(1,3)
local zone_tiles = {}
for i=1,ntiles do zone_tiles[i]=rect() end
local nwin = math.random(0,6)
local windows, state = {}, {}
for i=1,nwin do
  windows[i] = { id=i, app='App'..(i%3), frame=rect(), z_order=i }
  -- ~40% explicitly assigned to this zone (k), some to other zone, some none
  local r = math.random()
  if r < 0.3 then state[tostring(i)] = { monitor_id='M1', zone_key='k', tile_index=math.random(1,ntiles) }
  elseif r < 0.45 then state[tostring(i)] = { monitor_id='M1', zone_key='h', tile_index=1 } end
end
-- shuffle z_order
for i=#windows,2,-1 do local j=math.random(i); windows[i].z_order,windows[j].z_order=windows[j].z_order,windows[i].z_order end
io.write(json.encode({ monitor_id='M1', zone_key='k', overlap_threshold=0.5, zone_tiles=zone_tiles, windows=windows, state=next(state) and state or nil }))
