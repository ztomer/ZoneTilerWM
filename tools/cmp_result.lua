-- tools/cmp_result.lua
-- Compares two solver-oracle result JSON files. Exit 0 if equivalent, 1 otherwise
-- (diffs written to stderr). Comparison contract (per the plan):
--   * assignment MAP (window_id -> zone_key + tile_index) compared exactly
--   * per-assignment cost and total_cost compared within epsilon
--   * move ORDER is ignored (cosmetic)
--
--   lua tools/cmp_result.lua <a.json> <b.json>

package.path = package.path .. ';./?.lua'
local json = require('tools.json')

local EPS = 1e-6

local function read(p)
  local f = assert(io.open(p, 'r'))
  local s = f:read('*a'); f:close(); return s
end

local a = json.decode(read(arg[1]))
local b = json.decode(read(arg[2]))

local function map_of(r)
  local m = {}
  for _, x in ipairs(r.assignments or {}) do m[x.window_id] = x end
  return m
end

local ma, mb = map_of(a), map_of(b)
local errs = {}

if (a.placed or 0) ~= (b.placed or 0) then
  errs[#errs + 1] = string.format('placed: %s vs %s', tostring(a.placed), tostring(b.placed))
end
if math.abs((a.total_cost or 0) - (b.total_cost or 0)) > EPS then
  errs[#errs + 1] = string.format('total_cost: %.9g vs %.9g', a.total_cost or 0, b.total_cost or 0)
end

local keys = {}
for k in pairs(ma) do keys[k] = true end
for k in pairs(mb) do keys[k] = true end
for k in pairs(keys) do
  local xa, xb = ma[k], mb[k]
  if not (xa and xb) then
    errs[#errs + 1] = 'window ' .. k .. ' assigned on only one side'
  else
    if xa.zone_key ~= xb.zone_key then
      errs[#errs + 1] = string.format('%s zone: %s vs %s', k, tostring(xa.zone_key), tostring(xb.zone_key))
    end
    if tostring(xa.tile_index) ~= tostring(xb.tile_index) then
      errs[#errs + 1] = string.format('%s tile_index: %s vs %s', k, tostring(xa.tile_index), tostring(xb.tile_index))
    end
    if math.abs((xa.cost or 0) - (xb.cost or 0)) > EPS then
      errs[#errs + 1] = string.format('%s cost: %.9g vs %.9g', k, xa.cost or 0, xb.cost or 0)
    end
  end
end

if #errs == 0 then
  os.exit(0)
else
  for _, e in ipairs(errs) do io.stderr:write('  DIFF: ' .. e .. '\n') end
  os.exit(1)
end
