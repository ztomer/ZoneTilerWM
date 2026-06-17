-- tools/cmp_memory.lua
-- Compares two window-memory oracle result JSON files. Exit 0 if equivalent, 1 otherwise.
-- Contract: save.positions + save.preferences arrays equal (counts exact, means within
-- epsilon); per query: remembered, preferred_zone, preferred_tile, and ranked list equal.
--
--   lua tools/cmp_memory.lua <a.json> <b.json>

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

-- save.positions
local pa = (a.save or {}).positions or {}
local pb = (b.save or {}).positions or {}
if #pa ~= #pb then
  errs[#errs + 1] = string.format('save.positions count: %d vs %d', #pa, #pb)
else
  for i = 1, #pa do
    local x, y = pa[i], pb[i]
    if x.app_name ~= y.app_name or x.monitor_id ~= y.monitor_id
        or x.zone_key ~= y.zone_key or tostring(x.tile_index) ~= tostring(y.tile_index) then
      errs[#errs + 1] = 'save.positions[' .. i .. '] mismatch'
    end
  end
end

-- save.preferences
local fa = (a.save or {}).preferences or {}
local fb = (b.save or {}).preferences or {}
if #fa ~= #fb then
  errs[#errs + 1] = string.format('save.preferences count: %d vs %d', #fa, #fb)
else
  for i = 1, #fa do
    local x, y = fa[i], fb[i]
    if x.app_name ~= y.app_name or x.monitor_id ~= y.monitor_id
        or x.zone_key ~= y.zone_key or tostring(x.tile_index) ~= tostring(y.tile_index) then
      errs[#errs + 1] = 'save.preferences[' .. i .. '] key mismatch'
    else
      local da, db = x.data or {}, y.data or {}
      if (da.count or 0) ~= (db.count or 0) then
        errs[#errs + 1] = string.format('pref[%d] count: %s vs %s', i, tostring(da.count), tostring(db.count))
      end
      if not feq(da.mean_ar, db.mean_ar) then
        errs[#errs + 1] = string.format('pref[%d] mean_ar: %.9g vs %.9g', i, da.mean_ar or 0, db.mean_ar or 0)
      end
      if not feq(da.mean_area, db.mean_area) then
        errs[#errs + 1] = string.format('pref[%d] mean_area: %.9g vs %.9g', i, da.mean_area or 0, db.mean_area or 0)
      end
    end
  end
end

-- queries
local qa, qb = a.queries or {}, b.queries or {}
if #qa ~= #qb then
  errs[#errs + 1] = string.format('queries count: %d vs %d', #qa, #qb)
else
  for i = 1, #qa do
    local x, y = qa[i], qb[i]
    local ra, rb = x.remembered, y.remembered
    if (ra == nil) ~= (rb == nil) then
      errs[#errs + 1] = 'q' .. i .. ' remembered presence differs'
    elseif ra and rb and (ra.zone_key ~= rb.zone_key or tostring(ra.tile_index) ~= tostring(rb.tile_index)) then
      errs[#errs + 1] = 'q' .. i .. ' remembered mismatch'
    end
    if tostring(x.preferred_zone) ~= tostring(y.preferred_zone) then
      errs[#errs + 1] = string.format('q%d preferred_zone: %s vs %s', i, tostring(x.preferred_zone), tostring(y.preferred_zone))
    end
    if tostring(x.preferred_tile) ~= tostring(y.preferred_tile) then
      errs[#errs + 1] = string.format('q%d preferred_tile: %s vs %s', i, tostring(x.preferred_tile), tostring(y.preferred_tile))
    end
    local kra, krb = x.ranked or {}, y.ranked or {}
    if #kra ~= #krb then
      errs[#errs + 1] = string.format('q%d ranked count: %d vs %d', i, #kra, #krb)
    else
      for j = 1, #kra do
        local m, n = kra[j], krb[j]
        if m.zone_key ~= n.zone_key or tostring(m.tile_index) ~= tostring(n.tile_index)
            or (m.count or 0) ~= (n.count or 0)
            or not feq(m.mean_ar, n.mean_ar) or not feq(m.mean_area, n.mean_area) then
          errs[#errs + 1] = string.format('q%d ranked[%d] mismatch', i, j)
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
