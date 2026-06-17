-- tools/cmp_strategy.lua
-- Compares two placement-strategy oracle result JSON files. Exit 0 if equivalent, 1 else.
--   lua tools/cmp_strategy.lua <a.json> <b.json>

package.path = package.path .. ';./?.lua'
local json = require('tools.json')

local EPS = 1e-6
local errs = {}

local function read(p)
  local f = assert(io.open(p, 'r')); local s = f:read('*a'); f:close(); return s
end
local function feq(x, y) return math.abs((x or 0) - (y or 0)) <= EPS end
local function truthy(v) return v and true or false end

local a = json.decode(read(arg[1]))
local b = json.decode(read(arg[2]))

if truthy(a.found) ~= truthy(b.found) then
  errs[#errs + 1] = string.format('found: %s vs %s', tostring(a.found), tostring(b.found))
elseif a.found and b.found then
  local ta, tb = a.tile or {}, b.tile or {}
  for _, d in ipairs({ 'x', 'y', 'w', 'h' }) do
    if not feq(ta[d], tb[d]) then
      errs[#errs + 1] = string.format('tile.%s: %.9g vs %.9g', d, ta[d] or 0, tb[d] or 0)
    end
  end
end

if #errs == 0 then
  os.exit(0)
else
  for _, e in ipairs(errs) do io.stderr:write('  DIFF: ' .. e .. '\n') end
  os.exit(1)
end
