-- Full-screen interactive graph (opened from a graph row in the sheet).
--
-- Keys: left/right trace along the curve, up/down jump between marked
-- points, tab next curve, + / - zoom, 8 4 6 2 pan, l labels, a asymptotes,
-- esc or enter close.
local class = require 'class'
local ui = require 'ui'
local plot = require 'ui.plot'
local mb = require 'ui.mathbox'

ui.graphview = class(ui.view)

local max, min = math.max, math.min

local function copy_window(spec)
   return { xmin = spec.xmin, xmax = spec.xmax, ymin = spec.ymin, ymax = spec.ymax }
end

function ui.graphview:init(layout, spec, texts)
   ui.view.init(self, layout)
   self.spec = spec
   self.texts = texts or {}
   plot.auto_range(spec)
   self.home = copy_window(spec)
   self.labels = self.texts.labels ~= false
   self.curve = 1
   self.point_idx = nil
   self.cx = (spec.xmin + spec.xmax) / 2
   -- own copy of the solver's show/hide choices (toggled with 'a')
   self.hide = {}
   for k, v in pairs(spec.hide or {}) do self.hide[k] = v end
   -- marked points to jump between (coincident features merged)
   self.points = plot.merge_points(spec.points, self.hide)
   table.sort(self.points, function(a, b) return a.x < b.x end)
end

function ui.graphview:plot_rect()
   local f = self:frame()
   return ui.rect(f.x, f.y + 15, f.width, f.height - 15 - 12)
end

-- Current traced curve value at x (or parametric t)
function ui.graphview:trace_value()
   local c = (self.spec.curves or {})[self.curve]
   if not c then return nil end
   if c.kind == 'param' then
      local t = self.ct or c.tmin
      local x, y = c.fx(t), c.fy(t)
      return x, y, t
   elseif c.kind == 'x' then
      local y = self.cy or (self.spec.ymin + self.spec.ymax) / 2
      return c.fn(y), y
   elseif c.pts then
      local i = self.pi or 1
      local p = c.pts[i]
      return p and p[1], p and p[2]
   end
   return self.cx, c.fn(self.cx)
end

function ui.graphview:draw_self(wgc)
   local g = wgc.gc
   local f = self:frame()
   local spec = self.spec
   g:setColorRGB(0xFFFFFF)
   g:fillRect(f.x, f.y, f.width, f.height)

   local x, y, t = self:trace_value()
   local r = self:plot_rect()
   plot.draw(g, r, spec, { labels = self.labels, cursor = { x = x, y = y }, hide = self.hide })

   -- readout bar
   g:setColorRGB(0x24476B)
   g:fillRect(f.x, f.y, f.width, 15)
   g:setColorRGB(0xFFFFFF)
   g:setFont('sansserif', 'r', mb.snap(9))
   local function n(v)
      if not v then return 'undef' end
      if math.abs(v) < 1e-12 then v = 0 end
      local s = string.format('%.5g', v)
      return (s:gsub('^%-', '\226\136\146'))
   end
   local txt = 'x=' .. n(x) .. '  y=' .. n(y)
   if t then txt = 't=' .. n(t) .. '  ' .. txt end
   local p = self.point_idx and self.points[self.point_idx]
   if p and p.label then txt = txt .. '   ' .. p.label end
   g:drawString(txt, f.x + 3, f.y + 1, 'top')

   -- hint bar
   g:setColorRGB(0xEDEDED)
   g:fillRect(f.x, f.y + f.height - 12, f.width, 12)
   g:setColorRGB(0x505050)
   g:setFont('sansserif', 'r', mb.snap(7))
   g:drawString(self.texts.hint or '</> trace  ^/v points  +/- zoom  8462 pan  l labels  a asym.  esc',
                f.x + 3, f.y + f.height - 12, 'top')
end

function ui.graphview:step()
   return (self.spec.xmax - self.spec.xmin) / 120
end

function ui.graphview:on_left() self:move(-1) end
function ui.graphview:on_right() self:move(1) end

function ui.graphview:move(dir)
   local c = (self.spec.curves or {})[self.curve]
   self.point_idx = nil
   if c and c.kind == 'param' then
      self.ct = max(c.tmin, min(c.tmax, (self.ct or c.tmin) + dir * (c.tmax - c.tmin) / 120))
   elseif c and c.kind == 'x' then
      self.cy = (self.cy or (self.spec.ymin + self.spec.ymax) / 2) + dir * (self.spec.ymax - self.spec.ymin) / 120
   elseif c and c.pts then
      self.pi = max(1, min(#c.pts, (self.pi or 1) + dir))
   else
      self.cx = self.cx + dir * self:step()
      if self.cx < self.spec.xmin or self.cx > self.spec.xmax then
         self:pan(dir * 0.25, 0)
      end
   end
end

function ui.graphview:jump(dir)
   if #self.points == 0 then return end
   local i = self.point_idx
   if not i then
      i = dir > 0 and 0 or #self.points + 1
      for k, p in ipairs(self.points) do
         if dir > 0 and p.x <= self.cx then i = k end
         if dir < 0 and p.x >= self.cx and i == #self.points + 1 then i = k end
      end
   end
   i = i + dir
   if i < 1 then i = #self.points end
   if i > #self.points then i = 1 end
   self.point_idx = i
   local p = self.points[i]
   self.cx = p.x
   self.curve = p.curve or 1
   -- keep the point on screen
   local s = self.spec
   if p.x < s.xmin or p.x > s.xmax then
      local w = s.xmax - s.xmin
      s.xmin, s.xmax = p.x - w / 2, p.x + w / 2
   end
end

function ui.graphview:on_up() self:jump(1) end
function ui.graphview:on_down() self:jump(-1) end

function ui.graphview:on_tab()
   local n = #(self.spec.curves or {})
   if n > 0 then self.curve = self.curve % n + 1 end
   self.point_idx = nil
end

function ui.graphview:zoom(k)
   local s = self.spec
   local x, y = self:trace_value()
   x = x or (s.xmin + s.xmax) / 2
   y = y or (s.ymin + s.ymax) / 2
   if x < s.xmin or x > s.xmax then x = (s.xmin + s.xmax) / 2 end
   if y < s.ymin or y > s.ymax then y = (s.ymin + s.ymax) / 2 end
   s.xmin, s.xmax = x - (x - s.xmin) * k, x + (s.xmax - x) * k
   s.ymin, s.ymax = y - (y - s.ymin) * k, y + (s.ymax - y) * k
end

function ui.graphview:pan(fx, fy)
   local s = self.spec
   local dx, dy = (s.xmax - s.xmin) * fx, (s.ymax - s.ymin) * fy
   s.xmin, s.xmax = s.xmin + dx, s.xmax + dx
   s.ymin, s.ymax = s.ymin + dy, s.ymax + dy
end

function ui.graphview:on_char(c)
   if c == '+' then self:zoom(0.5)
   elseif c == '-' or c == '\226\136\146' then self:zoom(2)
   elseif c == '8' then self:pan(0, 0.25)
   elseif c == '2' then self:pan(0, -0.25)
   elseif c == '4' then self:pan(-0.25, 0)
   elseif c == '6' then self:pan(0.25, 0)
   elseif c == '5' or c == '0' then
      local s = self.spec
      s.xmin, s.xmax, s.ymin, s.ymax = self.home.xmin, self.home.xmax, self.home.ymin, self.home.ymax
   elseif c == 'l' then self.labels = not self.labels
   elseif c == 'a' then
      self.hide.asym = not self.hide.asym
   end
end

function ui.graphview:on_mouse_down(x, _)
   local r = self:plot_rect()
   local s = self.spec
   self.cx = s.xmin + (x - r.x) / r.width * (s.xmax - s.xmin)
   self.point_idx = nil
end

function ui.graphview:close()
   -- restore the window the sheet was showing
   local s = self.spec
   s.xmin, s.xmax, s.ymin, s.ymax = self.home.xmin, self.home.xmax, self.home.ymin, self.home.ymax
   if self.session then ui.pop_modal(self.session) end
   if self.on_close then self.on_close() end
end

function ui.graphview:on_escape() self:close() end
function ui.graphview:on_enter_key() self:close() end
function ui.graphview:on_return() self:close() end

-- Open a full-screen graph for spec
function ui.graphview.open(spec, texts, on_close)
   local v = ui.graphview(ui.rel { top = 0, bottom = 0, left = 0, right = 0 }, spec, texts)
   v.on_close = on_close
   v.session = ui.push_modal(v)
   ui.set_focus(v)
   return v
end

return ui.graphview
