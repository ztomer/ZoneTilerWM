-- tools/cmp_zones.lua
-- Compares two zone-oracle result JSON files. Exit 0 if equivalent, 1 otherwise.
-- Contract: layout_key exact; zones map = same zone keys; per zone, same tile count and
-- order; each tile rect within epsilon.
--
--   lua tools/cmp_zones.lua <a.json> <b.json>

package.path = package.path .. ';./?.lua'
local json = require('tools.json')

local EPS = 1e-6

local function read(p)
  local f = assert(io.open(p, 'r')); local s = f:read('*a'); f:close(); return s
end

local a = json.decode(read(arg[1]))
local b = json.decode(read(arg[2]))
local errs = {}

if a.layout_key ~= b.layout_key then
  errs[#errs + 1] = string.format('layout_key: %s vs %s', tostring(a.layout_key), tostring(b.layout_key))
end

local za, zb = a.zones or {}, b.zones or {}
local keys = {}
for k in pairs(za) do keys[k] = true end
for k in pairs(zb) do keys[k] = true end

for k in pairs(keys) do
  local ta, tb = za[k], zb[k]
  if not (ta and tb) then
    errs[#errs + 1] = 'zone ' .. k .. ' present on only one side'
  elseif #ta ~= #tb then
    errs[#errs + 1] = string.format('zone %s tile count: %d vs %d', k, #ta, #tb)
  else
    for i = 1, #ta do
      for _, d in ipairs({ 'x', 'y', 'w', 'h' }) do
        if math.abs((ta[i][d] or 0) - (tb[i][d] or 0)) > EPS then
          errs[#errs + 1] = string.format('zone %s tile %d %s: %.9g vs %.9g',
            k, i, d, ta[i][d] or 0, tb[i][d] or 0)
        end
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
