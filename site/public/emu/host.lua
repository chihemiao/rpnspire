-- TI-Nspire Lua scripting API for the browser demo (see emulator.js).
--
-- Runs before the toolkit bundle. Drawing calls are collected into a command
-- buffer (records separated by \30, fields by \31) that emulator.js replays
-- on a <canvas>; text widths come from the canvas (js_measure). Events from
-- the page arrive through host_event and call the on.* handlers like the
-- calculator does.
-- luacheck: globals js_measure js_copy class platform on toolpalette clipboard var timer cursor
-- luacheck: globals document locale unpack loadstring string host_start host_event host_paint
-- luacheck: globals host_menu host_menu_select host_set_clip
-- luacheck: ignore 212/self

local W, H = 318, 212
local RS, US = '\30', '\31'

function class(base)
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

if not unpack then unpack = table.unpack end
if not loadstring then loadstring = load end

-- UTF-8 substring (TI built-in)
function string.usub(s, i, j)
   local n = utf8.len(s)
   if not n then return s:sub(i, j) end
   i, j = i or 1, j or -1
   if i < 0 then i = n + i + 1 end
   if j < 0 then j = n + j + 1 end
   if i < 1 then i = 1 end
   if j > n then j = n end
   if i > j then return '' end
   return s:sub(utf8.offset(s, i), utf8.offset(s, j + 1) - 1)
end
string.uchar = utf8.char

-- Drawing --------------------------------------------------------------------

local buf, n = {}, 0
local function emit(...)
   n = n + 1
   buf[n] = table.concat({ ... }, US)
end

local widths, nwidths = {}, 0

local G = {}
G.__index = G

local function newgc(draws)
   return setmetatable({ draws = draws, fam = 'sansserif', st = 'r', size = 11 }, G)
end

function G:setFont(fam, st, size)
   self.fam, self.st, self.size = fam or 'sansserif', st or 'r', size or 11
   if self.draws then emit('F', self.fam, self.st, self.size) end
end

function G:getStringWidth(s)
   s = tostring(s or '')
   local key = self.fam .. self.st .. self.size .. US .. s
   local w = widths[key]
   if not w then
      if nwidths > 4000 then widths, nwidths = {}, 0 end
      w = math.floor(js_measure(s, self.fam, self.st, self.size) + 0.5)
      widths[key] = w
      nwidths = nwidths + 1
   end
   return w
end

function G:getStringHeight()
   return math.floor(self.size * 1.45 + 0.5)
end

function G:setColorRGB(r, g, b)
   if not self.draws then return end
   local c = g and (r * 65536 + g * 256 + b) or r
   emit('C', math.floor(c or 0))
end

function G:setPen(size, style)
   if self.draws then emit('P', size or 'thin', style or 'smooth') end
end

function G:setAlpha() end

local function nums(...)
   local t = { ... }
   for i = 1, select('#', ...) do t[i] = string.format('%.2f', tonumber(t[i]) or 0) end
   return unpack(t, 1, select('#', ...))
end

function G:fillRect(x, y, w, h) if self.draws then emit('R', nums(x, y, w, h)) end end
function G:drawRect(x, y, w, h) if self.draws then emit('r', nums(x, y, w, h)) end end
function G:drawLine(x1, y1, x2, y2) if self.draws then emit('L', nums(x1, y1, x2, y2)) end end
function G:fillArc(x, y, w, h, a, d) if self.draws then emit('A', nums(x, y, w, h, a or 0, d or 360)) end end
function G:drawArc(x, y, w, h, a, d) if self.draws then emit('a', nums(x, y, w, h, a or 0, d or 360)) end end

local function poly(self, kind, pts)
   if not self.draws or not pts then return end
   local t = { kind }
   for i = 1, #pts do t[#t + 1] = string.format('%.2f', pts[i]) end
   n = n + 1
   buf[n] = table.concat(t, US)
end
function G:fillPolygon(pts) poly(self, 'G', pts) end
function G:drawPolyLine(pts) poly(self, 'g', pts) end

function G:drawString(s, x, y, align)
   s = tostring(s or '')
   if self.draws and s ~= '' then
      emit('S', string.format('%.2f', x or 0), string.format('%.2f', y or 0), align or 'top', s)
   end
   return (x or 0) + self:getStringWidth(s)
end

function G:clipRect(op, x, y, w, h)
   if not self.draws then return end
   if op == 'reset' or not x then
      emit('K')
   else
      emit('k', nums(x, y, w, h))
   end
end

function G:drawImage() end

-- Platform -------------------------------------------------------------------

local invalid = true
local measure_gc = newgc(false)
local error_handler

platform = {
   apiLevel = '2.4',
   hw = function() return 7 end,
   isColorDisplay = function() return true end,
   isDeviceModeRendering = function() return true end,
   isTabletModeRendering = function() return false end,
   withGC = function(fn, ...) return fn(measure_gc, ...) end,
   registerErrorHandler = function(fn) error_handler = fn end,
   window = {
      width = function() return W end,
      height = function() return H end,
      invalidate = function() invalid = true end,
      setFocus = function() end,
      setPreferredSize = function() end,
   },
}

on = {}

local menu = nil
toolpalette = {
   register = function(m) menu = m end,
   enable = function() end,
   enableCopy = function() end,
   enableCut = function() end,
   enablePaste = function() end,
}

local clip_text = ''
clipboard = {
   addText = function(s)
      clip_text = tostring(s or '')
      pcall(js_copy, clip_text)
   end,
   getText = function() return clip_text end,
}

var = {
   list = function() return {} end,
   store = function() end,
   recall = function() return nil end,
   recallStr = function() return nil end,
   monitor = function() end,
   unmonitor = function() end,
}

timer = {
   start = function() end,
   stop = function() end,
   getMilliSecCounter = function() return math.floor(os.clock() * 1000) end,
}
cursor = { set = function() end, show = function() end, hide = function() end }
document = { markChanged = function() end }
locale = { name = function() return 'en' end }

-- Page interface -------------------------------------------------------------

local function call(fn, ...)
   local ok, err = xpcall(fn, debug.traceback, ...)
   if not ok then
      print(err)
      if error_handler then pcall(error_handler, 0, tostring(err)) end
      invalid = true
      return false
   end
   return true
end

function host_paint()
   invalid = false
   buf, n = {}, 0
   if on.paint then call(on.paint, newgc(true)) end
   return table.concat(buf, RS, 1, n)
end

local function after()
   if invalid then return host_paint() end
   return nil
end

-- Open the document: construction, size and activation, then the first paint
function host_start()
   if on.construction then call(on.construction) end
   if on.resize then call(on.resize, W, H) end
   if on.activate then call(on.activate) end
   if on.getFocus then call(on.getFocus) end
   return host_paint()
end

local EVENTS = {
   char = 'charIn', enter = 'enterKey', ['return'] = 'returnKey', tab = 'tabKey',
   backtab = 'backtabKey', esc = 'escapeKey', up = 'arrowUp', down = 'arrowDown',
   left = 'arrowLeft', right = 'arrowRight', backspace = 'backspaceKey',
   clear = 'clearKey', ctx = 'contextMenu', help = 'help', copy = 'copy',
   cut = 'cut', paste = 'paste', mouse = 'mouseDown', rmouse = 'rightMouseDown',
}

-- Returns a paint buffer when the screen changed, else nil
function host_event(name, a, b)
   local h = on[EVENTS[name] or name]
   if h then call(h, a, b) end
   return after()
end

function host_set_clip(s)
   clip_text = tostring(s or '')
end

-- The toolpalette (menu key): titles of each menu and its items
function host_menu()
   if not menu then return '' end
   local out = {}
   for _, sub in ipairs(menu) do
      local parts = { tostring(sub[1]) }
      for j = 2, #sub do
         parts[#parts + 1] = tostring(sub[j][1])
      end
      out[#out + 1] = table.concat(parts, US)
   end
   return table.concat(out, RS)
end

function host_menu_select(i, j)
   local sub = menu and menu[i]
   local item = sub and sub[j + 1]
   if item and type(item[2]) == 'function' then
      call(item[2], sub[1], item[1])
   end
   return after()
end
