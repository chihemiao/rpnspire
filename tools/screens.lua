-- Desktop screenshot harness: runs the VCE app with the numeric mock CAS and
-- renders screens to SVG (approximate TI fonts). Usage:
--   lua tools/screens.lua <outdir>
package.path = './?.lua;' .. package.path

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
function string.usub(...) return string.sub(...) end
if not unpack then _G.unpack = table.unpack end

local W, H = 318, 212

local function char_w(size, ch)
   -- rough sans-serif metrics (CJK glyphs are full width)
   local b = ch:byte(1)
   if b >= 227 and b <= 233 or (b == 239 and (ch:byte(2) == 188 or ch:byte(2) == 189)) then
      return size * 1.0 * 1.33
   end
   local k = 0.56
   if ch:match('[iIl%.,:;!|\']') then k = 0.28
   elseif ch:match('[mwMW]') then k = 0.85
   elseif ch:match('[%u]') then k = 0.66
   elseif ch:match('[ftrj%(%)%[%]]') then k = 0.36
   elseif ch == ' ' then k = 0.3 end
   return size * k * 1.33
end

local function str_w(s, size)
   local w = 0
   for ch in s:gmatch('[\1-\127\194-\244][\128-\191]*') do w = w + char_w(size, ch) end
   return math.floor(w + 0.5)
end

local svg = {}
local function esc(s)
   s = s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
   -- TI private-use glyphs
   s = s:gsub('\239\128\191', 'e'):gsub('\239\128\128', 'E')
   return s
end

local function color(c)
   return string.format('#%06x', c or 0)
end

local G = {}
G.__index = G
local function newgc()
   return setmetatable({ size = 11, style = 'r', col = 0, clip = nil }, G)
end
function G:setFont(_, style, size) self.size, self.style = size, style end
function G:getStringWidth(s) return str_w(s or '', self.size) end
function G:getStringHeight() return math.floor(self.size * 1.45 + 0.5) end
function G:setColorRGB(c) self.col = c end
function G:clipRect(op, x, y, w, h)
   if op == 'reset' then self.clip = nil else self.clip = { x, y, w, h } end
end
local clipn = 0
function G:cl()
   if not self.clip then return '' end
   clipn = clipn + 1
   local id = 'c' .. clipn
   table.insert(svg, string.format('<clipPath id="%s"><rect x="%d" y="%d" width="%d" height="%d"/></clipPath>', id,
      self.clip[1], self.clip[2], self.clip[3], self.clip[4]))
   return string.format(' clip-path="url(#%s)"', id)
end
function G:fillRect(x, y, w, h)
   table.insert(svg, string.format('<rect x="%d" y="%d" width="%d" height="%d" fill="%s"%s/>', x, y, w, h, color(self.col), self:cl()))
end
function G:drawRect(x, y, w, h)
   table.insert(svg, string.format('<rect x="%.1f" y="%.1f" width="%d" height="%d" fill="none" stroke="%s" stroke-width="1"%s/>', x + 0.5, y + 0.5, w, h, color(self.col), self:cl()))
end
function G:drawLine(x1, y1, x2, y2)
   table.insert(svg, string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1"%s/>', x1 + 0.5, y1 + 0.5, x2 + 0.5, y2 + 0.5, color(self.col), self:cl()))
end
function G:drawArc(x, y, w, h, a0, da)
   local cx, cy, rx, ry = x + w / 2, y + h / 2, w / 2, h / 2
   local function pt(a)
      local r = math.rad(a)
      return cx + rx * math.cos(r), cy - ry * math.sin(r)
   end
   local x1, y1 = pt(a0)
   local x2, y2 = pt(a0 + da)
   table.insert(svg, string.format('<path d="M %.1f %.1f A %.1f %.1f 0 %d 0 %.1f %.1f" fill="none" stroke="%s"%s/>', x1, y1, rx, ry, da > 180 and 1 or 0, x2, y2, color(self.col), self:cl()))
end
function G:fillArc(x, y, w, h)
   table.insert(svg, string.format('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"%s/>', x + w / 2, y + h / 2, w / 2, h / 2, color(self.col), self:cl()))
end
function G:drawString(s, x, y)
   if s == '' then return end
   local w = str_w(s, self.size)
   table.insert(svg, string.format('<text xml:space="preserve" x="%d" y="%.1f" font-family="DejaVu Sans, Noto Sans CJK SC, WenQuanYi Micro Hei, sans-serif" font-size="%.1f" font-weight="%s" font-style="%s" fill="%s" textLength="%d" lengthAdjust="spacingAndGlyphs"%s>%s</text>',
      x, y + self.size * 1.12, self.size * 1.33, self.style:find('b') and 'bold' or 'normal', self.style:find('i') and 'italic' or 'normal', color(self.col), w, self:cl(), esc(s)))
end

local measure_gc = newgc()
_G.platform = {
   apiLevel = '2.4',
   withGC = function(fn) return fn(measure_gc) end,
   window = { width = function() return W end, height = function() return H end, invalidate = function() end },
}
_G.on = {}
_G.clipboard = { addText = function() end, getText = function() return '' end }
_G.var = { list = function() return { 'f11' } end, store = function() end }
_G.toolpalette = { register = function() end, enableCopy = function() end, enableCut = function() end, enablePaste = function() end }

require 'tableext'
require 'stringext'
local mock = require 'testcas'
mock.functions['f11'] = { params = { 'x' }, body = '3*x^2-2' }
math.evalStr = mock.evalStr
local cas = require 'apps.vce.cas'
cas.backend = mock.evalStr

local ui = require 'ui'
local app = require 'apps.vce.app'

local outdir = arg[1] or '.'
if arg[2] == 'bi' then
   local i18n = require 'apps.vce.i18n'
   i18n.install(require 'apps.vce.i18n_zh')
   i18n.default = 'bi'
end

local function shot(name)
   svg = {}
   clipn = 0
   local g = newgc()
   ui.paint(ui.GC(g, 0, 0))
   local f = io.open(outdir .. '/' .. name .. '.svg', 'w')
   f:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><rect width="%d" height="%d" fill="white"/>', W, H, W, H, W, H))
   f:write(table.concat(svg, '\n'))
   f:write('</svg>')
   f:close()
end

local function key(name, ...) ui.on_event(name, ...) end
local function type_text(s)
   for ch in s:gmatch('[\1-\127\194-\244][\128-\191]*') do key('char', ch) end
end

app.open(nil)
shot('01_home')

-- Normal: fill fields
app.new_problem('normal')
type_text('50') key('enter_key')
type_text('4') key('enter_key')
key('enter_key')
type_text('45<X<55') key('enter_key')
shot('02_normal')
for _ = 1, 3 do key('down') end
shot('03_normal_results')
key('enter_key')
shot('04_normal_toggled')

-- PDF
key('escape')
app.new_problem('pdf')
type_text('k*x*(2-x)') key('enter_key')
type_text('0') key('enter_key')
type_text('2') key('enter_key')
shot('05_pdf')
for _ = 1, 8 do key('down') end
shot('06_pdf_results')

-- Kinematics
key('escape')
app.new_problem('kinematics')
key('right') key('down')
type_text('-v/2') key('enter_key')
type_text('0') key('enter_key')
type_text('0') key('enter_key')
type_text('10') key('enter_key')
for _ = 1, 4 do key('down') end
type_text('v=5') key('enter_key')
shot('07_kinematics')
for _ = 1, 10 do key('down') end
shot('08_kinematics_work')

-- SUVAT
key('escape')
app.new_problem('suvat')
type_text('10') key('enter_key')
type_text('20') key('enter_key')
key('enter_key')
type_text('-9.8') key('enter_key')
shot('09_suvat')

-- history
key('escape')
key('char', 'h')
shot('10_history')
key('escape')
key('escape')

-- Graphs: select the graph row, then open it full screen
local function graph_row()
   for i, r in ipairs(app.sheet.rows) do
      if r.kind == 'graph' then
         app.sheet:select(i)
         return i
      end
   end
end

app.new_problem('graph', { f = '(x^2-1)/(x-2)', xmin = '-6', xmax = '8' })
for _ = 1, 12 do key('down') end
shot('11_graph_results')
graph_row()
shot('12_graph_row')
key('enter_key')
key('up') key('up')
shot('13_graph_full')
key('escape')
key('escape')

app.new_problem('graph', { f = 'x^(2/3)*(x-2)', xmin = '-2', xmax = '4' })
graph_row()
key('enter_key')
shot('14_graph_cusp')
key('escape')
key('escape')

app.new_problem('revolution', { type = 'y', f = 'sqrt(x)', g = 'x/2', a = '0', b = '4', axis = 'x' })
for _ = 1, 8 do key('down') end
shot('15_revolution')
graph_row()
key('enter_key')
shot('16_revolution_full')
key('escape')
key('escape')

app.new_problem('demodels', { type = 'logistic', y0 = '10', cap = '100', k = '0.4', find = 't=5' })
for _ = 1, 6 do key('down') end
shot('17_demodels')
graph_row()
key('enter_key')
shot('18_demodels_full')
key('escape')
key('escape')

app.new_problem('demodels', { type = 'general', f = 'x-y', x0 = '0', yg0 = '1', h = '0.25', xn = '2' })
graph_row()
key('enter_key')
shot('19_slope_field')
key('escape')
key('escape')
app.show_home()
for _ = 1, 3 do key('down') end
shot('20_home_calculus')

-- Kinematics: unknown constant, formula working and domain
app.new_problem('kinematics', { type = 'a(v)', f = '-k*v^2', v0 = '10', x0 = '0', c2 = 'a=-4.9 when v=7' })
for i, r in ipairs(app.sheet.rows) do
   if r.rkey == 'xv' then app.sheet:select(i) end
end
shot('21_kin_formula')
key('enter_key')
shot('22_kin_formula_working')
key('escape')
key('escape')

-- New user flow: Probability is one entry; the kind of question comes first
app.show_home()
shot('23_home')
key('char', '9')
shot('24_prob_pick')
key('char', '1')
shot('25_prob_normal_empty')
-- 'Try an example' fills in a sample question
for i, r in ipairs(app.sheet.rows) do
   if r.action and r.action[1] == 'example' then app.sheet:select(i) end
end
key('enter_key')
shot('26_prob_normal_example')
key('escape')

app.new_problem('probability', { type = 'proportion', ['proportion.p'] = '0.3', ['proportion.n'] = '50',
                                 ['proportion.event'] = 'P>0.36' })
for _ = 1, 5 do key('down') end
shot('27_proportion')
key('escape')

app.new_problem('params', { f = 'a*x^3+b*x^2+c', c1 = 'f(1)=3', c2 = "f'(2)=0", c3 = '(0,1)' })
shot('28_params')
for _ = 1, 9 do key('down') end
shot('29_params_answers')
key('escape')

app.new_problem('transform', { f = 'x^2', g = '-2f(3x-6)+4', pt = '(1,1)' })
for _ = 1, 4 do key('down') end
shot('30_transform')
for _ = 1, 8 do key('down') end
shot('31_transform_steps')
graph_row()
key('enter_key')
shot('32_transform_graph')
key('escape')
key('escape')

app.new_problem('simul', { e1 = 'kx+2y=k', e2 = '2x+(k-3)y=k-2' })
for _ = 1, 3 do key('down') end
shot('33_simul')
key('escape')

app.show_settings()
shot('34_settings')
key('escape')

-- Kinematics: choose what to find; a clear note when a condition is missing
-- (enter on 'when' goes to the answer, or to the note when nothing can be found)
app.new_problem('kinematics', { type = 'a(t)', f = '6t', x0 = '1', v0 = '2', want = 'x', find = 't=2' })
for i, r in ipairs(app.sheet.rows) do
   if r.id == 'find' then app.sheet:select(i) end
end
key('enter_key')
shot('35_kin_find_x')
key('escape')
app.new_problem('kinematics', { type = 'a(t)', f = '6t', v0 = '2', want = 'x', find = 't=2' })
for i, r in ipairs(app.sheet.rows) do
   if r.id == 'find' then app.sheet:select(i) end
end
key('enter_key')
shot('36_kin_not_enough')
key('escape')

-- Volume with limits in y, and with a letter in the limits
app.new_problem('revolution', { type = 'y', f = 'x^2', lim = 'y', a = '1', b = '4', axis = 'y' })
for i, r in ipairs(app.sheet.rows) do
   if r.kind == 'graph' then app.sheet:select(i) end
end
shot('37_rev_y_limits')
key('escape')
app.new_problem('revolution', { type = 'y', f = 'sqrt(x)', a = '0', b = 'a', axis = 'x', known = 'V=8pi' })
for i, r in ipairs(app.sheet.rows) do
   if r.id == 'known' then app.sheet:select(i) end
end
key('enter_key')
shot('38_rev_letter')
key('escape')
app.new_problem('graph', { f = '1/x', xmin = '-5', xmax = '5' })
for i, r in ipairs(app.sheet.rows) do
   if r.kind == 'graph' then app.sheet:select(i) end
end
shot('39_asymptote_on_axis')
key('escape')
print('ok')
