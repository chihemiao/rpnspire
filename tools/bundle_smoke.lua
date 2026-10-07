-- Run a bundled .lua like the TI runtime would (no require/package/io/os)
-- and exercise the on.* handlers. Usage: lua5.1 tools/bundle_smoke.lua vce_bundle.lua
package.path = './?.lua;' .. package.path
local file = arg[1] or 'vce_bundle.lua'
local f = assert(io.open(file, 'r'))
local src = f:read('*a')
f:close()

function _G.class(base)
   local classdef = {}
   setmetatable(classdef, {
      __index = base,
      __call = function(_, ...)
         local inst = { class = classdef, super = base or nil }
         setmetatable(inst, { __index = classdef })
         if inst.init then inst:init(...) end
         return inst
      end
   })
   return classdef
end
string.usub = string.sub

local mock = require 'testcas'
math.evalStr = mock.evalStr

local gc = setmetatable({}, { __index = function(_, k)
   if k == 'getStringWidth' then return function(_, s) return 6 * #(s or '') end end
   if k == 'getStringHeight' then return function() return 12 end end
   return function() end
end })
_G.platform = {
   withGC = function(fn) return fn(gc) end,
   window = { width = function() return 318 end, height = function() return 212 end, invalidate = function() end },
}
_G.on = {}
_G.clipboard = { addText = function() end, getText = function() return '1/2' end }
_G.var = { list = function() return {} end, store = function() end }
local menu
_G.toolpalette = { register = function(m) menu = m end, enableCopy = function() end,
                   enableCut = function() end, enablePaste = function() end }

-- TI runtime lacks these
local load_chunk = loadstring or load
local chunk = assert(load_chunk(src, '=' .. file))
_G.require, _G.package, _G.io, _G.os, _G.dofile, _G.loadfile = nil, nil, nil, nil, nil, nil
chunk()

on.construction()
on.resize(318, 212)
on.paint(gc)
local function keys(s) for ch in s:gmatch('.') do on.charIn(ch) end end
if file:find('bundle.lua', 1, true) == 1 then
   -- rpnspire: launch the toolkit via .a (apps) and the filter dialog
   keys('.a') keys('VCE') on.enterKey()
   assert(menu, 'toolkit opened from rpnspire')
   keys('9') keys('2') on.enterKey() keys('3') on.enterKey() on.enterKey() keys('1') on.enterKey()
   on.paint(gc)
   on.escapeKey() on.escapeKey()
   on.paint(gc)
   local state = on.save()
   assert(type(state) == 'table' and state.vce, 'rpnspire saves toolkit state')
   on.restore(state)
else
   assert(menu, 'toolpalette registered')
   if file:find('zh', 1, true) then
      assert(menu[1][1]:find('[\227-\233]'), 'bilingual document starts with a bilingual menu')
   else
      assert(not menu[1][1]:find('[\227-\233]'), 'English document starts in English')
   end
   -- vce entry: open a solver, type, solve
   keys('1') keys('50') on.enterKey() keys('4') on.enterKey() on.enterKey() keys('X<55') on.enterKey()
   on.paint(gc)
   on.arrowDown() on.arrowDown() on.enterKey() on.paint(gc)
   on.contextMenu() on.escapeKey() on.paint(gc)
   on.escapeKey()
   -- Probability: choose the kind (6 = sample proportion), then type
   keys('9') on.paint(gc) keys('6') on.arrowDown()
   keys('0.3') on.enterKey() keys('50') on.enterKey() keys('P>0.36') on.enterKey()
   on.paint(gc) on.escapeKey()
   -- unknown constants, transformations, simultaneous equations
   keys('2') keys('a*x^2+b') on.enterKey() keys('f(1)=3') on.enterKey() keys('(0,1)') on.enterKey()
   on.paint(gc) on.escapeKey()
   keys('3') keys('x^2') on.enterKey() keys('2f(x-1)+3') on.enterKey() on.paint(gc) on.escapeKey()
   keys('4') keys('kx+y=1') on.enterKey() keys('x+ky=1') on.enterKey() on.paint(gc) on.escapeKey()
   local state = on.save()
   assert(type(state) == 'table', 'state saved')
   on.restore(state)
   on.paint(gc)
end
print('bundle ok: ' .. file)
