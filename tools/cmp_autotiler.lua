-- tools/cmp_autotiler.lua
-- Compares two auto-tiler oracle result JSON files. Exit 0 if equivalent, 1 otherwise.
-- Moves compared as a map keyed by window_id (monitor/zone/tile exact, rect within epsilon).
--   lua tools/cmp_autotiler.lua <a.json> <b.json>

package.path = package.path .. ';./?.lua'
local json = require('tools.json')

local EPS = 1e-6
local errs = {}

local function read(p)
  local f = assert(io.open(p, 'r')); local s = f:read('*a'); f:close(); return s
end
local function feq(x, y) return math.abs((x or 0) - (y or 0)) <= EPS end

local a = json.decode(read(arg[1]))
local b = json.decode(read(arg[2]))

local function map_of(r)
  local m = {}
  for _, mv in ipairs(r.moves or {}) do m[mv.window_id] = mv end
  return m
end
local ma, mb = map_of(a), map_of(b)

if #(a.moves or {}) ~= #(b.moves or {}) then
  errs[#errs + 1] = string.format('move count: %d vs %d', #(a.moves or {}), #(b.moves or {}))
end

local keys = {}
for k in pairs(ma) do keys[k] = true end
for k in pairs(mb) do keys[k] = true end
for k in pairs(keys) do
  local x, y = ma[k], mb[k]
  if not (x and y) then
    errs[#errs + 1] = 'window ' .. tostring(k) .. ' moved on only one side'
  else
    if x.monitor_id ~= y.monitor_id then
      errs[#errs + 1] = string.format('win %s monitor: %s vs %s', tostring(k), tostring(x.monitor_id), tostring(y.monitor_id))
    end
    if x.zone_key ~= y.zone_key then
      errs[#errs + 1] = string.format('win %s zone: %s vs %s', tostring(k), tostring(x.zone_key), tostring(y.zone_key))
    end
    if tostring(x.tile_index) ~= tostring(y.tile_index) then
      errs[#errs + 1] = string.format('win %s tile: %s vs %s', tostring(k), tostring(x.tile_index), tostring(y.tile_index))
    end
    local ra, rb = x.rect or {}, y.rect or {}
    for _, d in ipairs({ 'x', 'y', 'w', 'h' }) do
      if not feq(ra[d], rb[d]) then
        errs[#errs + 1] = string.format('win %s rect.%s: %.9g vs %.9g', tostring(k), d, ra[d] or 0, rb[d] or 0)
      end
    end
  end
end

if #errs == 0 then
  os.exit(0)
else
  for _, e in ipairs(errs) do io.stderr:write('  DIFF: ' .. e .. '\n') end
  os.exit(1)
end
