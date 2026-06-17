-- tools/cmp_focus.lua — compare ordered zone-window lists. Exit 0 if equal.
package.path = package.path .. ';./?.lua'
local json = require('tools.json')
local function read(p) local f=assert(io.open(p,'r')); local s=f:read('*a'); f:close(); return s end
local a=json.decode(read(arg[1])); local b=json.decode(read(arg[2]))
local oa, ob = a.ordered or {}, b.ordered or {}
local errs={}
if #oa ~= #ob then errs[#errs+1]=string.format('count %d vs %d', #oa, #ob)
else
  for i=1,#oa do
    local x,y=oa[i],ob[i]
    if x.window_id~=y.window_id or tostring(x.tile_index)~=tostring(y.tile_index) or (x.explicit and true or false)~=(y.explicit and true or false) then
      errs[#errs+1]=string.format('pos %d: id %s/%s tile %s/%s explicit %s/%s', i, tostring(x.window_id),tostring(y.window_id),tostring(x.tile_index),tostring(y.tile_index),tostring(x.explicit),tostring(y.explicit))
    end
  end
end
if #errs==0 then os.exit(0) else for _,e in ipairs(errs) do io.stderr:write('  DIFF: '..e..'\n') end; os.exit(1) end
