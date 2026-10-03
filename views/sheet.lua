-- Scrollable worksheet view used by the VCE toolkit.
--
-- Rows (tables) are drawn top to bottom. Kinds:
--   header  { text }                         section title (not selectable)
--   input   { id, label, text, hint }        editable field (type to edit)
--   choice  { id, label, options, index }    option list (left/right/enter)
--   result  { label, exact, mode }           result; enter/click toggles exact/decimal
--   step    { text, num }                    working line (text with `math`)
--   note    { text, kind }                   info/warn/error text
--   link    { title, desc, key }             menu entry (enter/click activates)
--   math    { m }                            centred display maths
--   text    { text }                         paragraph (help)
--
-- Callbacks (assign on the instance):
--   on_commit(row)            input text changed (row.text updated)
--   on_submit(row)            enter pressed on an input
--   on_choice(row)            choice changed
--   on_activate(row)          enter/click on link
--   on_toggle(row)            result toggled
--   on_escape()               escape (nothing to cancel)
--   on_select(row)            selection changed
--   on_context(row)           context menu key
--   on_delete(row)            backspace on a non-input row
--   on_shortcut(char)         character typed on a non-input row; return true if handled
--   value_text(row)           CAS string shown for a result row
--   input_display(row)        CAS string shown for an input value (pretty form)
local class = require 'class'
local ui = require 'ui'
local mb = require 'ui.mathbox'
local sym = require 'ti.sym'
local report = require 'apps.vce.report'

ui.sheet = class(ui.view)

local floor, max, min = math.floor, math.max, math.min

local C = {
   bg = 0xFFFFFF,
   sel = 0xD6E9FF,
   sel_border = 0x3070C0,
   header_bg = 0xE6E6E6,
   header = 0x404040,
   label = 0x2A4E7A,
   hint = 0x9A9A9A,
   text = 0x000000,
   caret = 0xE00000,
   info = 0x5A5A5A,
   warn = 0xB86000,
   error = 0xC00000,
   num = 0x8A8A8A,
   approx = 0x1F6FB2,
   link_key = 0x2A4E7A,
   field = 0xFFFFFF,
}
ui.sheet.colors = C

-- UTF-8 helpers -------------------------------------------------------------------

local function chars_of(s)
   local t = {}
   for ch in (s or ''):gmatch('[\1-\127\194-\244][\128-\191]*') do
      table.insert(t, ch)
   end
   return t
end

local function join(t, i, j)
   return table.concat(t, '', i or 1, j or #t)
end

-- Init ----------------------------------------------------------------------------

function ui.sheet:init(layout)
   ui.view.init(self, layout)
   self.rows = {}
   self.sel = nil
   self.scroll_y = 0
   self.font = 10
   self.edit = nil
   self.hscroll = 0
   self.label_max = 0.42
end

function ui.sheet:set_font(size)
   self.font = size
   self:invalidate_layout()
end

function ui.sheet:invalidate_layout()
   for _, r in ipairs(self.rows) do r._lay = nil end
end

local SELECTABLE = { input = true, choice = true, result = true, step = true, link = true, math = true }

function ui.sheet:is_selectable(row)
   return row and SELECTABLE[row.kind] and not row.disabled
end

-- Replace rows; keeps selection on the row with the same `key` if possible
function ui.sheet:set_rows(rows, keep)
   local old = self:selected()
   local old_key = old and (old.key or old.id)
   self:commit_edit()
   self.rows = rows
   self._label_w = nil
   self.edit = nil
   self.sel = nil
   if keep and old_key then
      for i, r in ipairs(rows) do
         if (r.key or r.id) == old_key and self:is_selectable(r) then
            self.sel = i
            break
         end
      end
   end
   if not self.sel then
      self.scroll_y = 0
      self:select_first()
   else
      self:begin_edit()
      self:ensure_visible_sel()
   end
end

function ui.sheet:selected()
   return self.sel and self.rows[self.sel]
end

function ui.sheet:select_first(kind)
   for i, r in ipairs(self.rows) do
      if self:is_selectable(r) and (not kind or r.kind == kind) then
         self:select(i)
         return true
      end
   end
   self.sel = nil
   return false
end

function ui.sheet:select(i)
   if i == self.sel then return end
   local target = self.rows[i]
   local tkey = target and (target.key or target.id)
   if self:commit_edit() and self.rows[i] ~= target then
      -- committing rebuilt the rows: find the target row again
      i = nil
      for k, r in ipairs(self.rows) do
         if tkey and (r.key or r.id) == tkey and self:is_selectable(r) then
            i = k
            break
         end
      end
      if not i then return end
      if i == self.sel then
         self:ensure_visible_sel()
         return
      end
   end
   self.sel = i
   self.hscroll = 0
   self:begin_edit()
   self:ensure_visible_sel()
   if self.on_select then self:on_select(self:selected()) end
end

function ui.sheet:move(dir)
   local i = self.sel or 0
   local n = #self.rows
   for _ = 1, n do
      i = i + dir
      if i < 1 or i > n then
         -- scroll to the very top/bottom when there is nothing more to select
         if dir < 0 then self.scroll_y = 0 end
         return false
      end
      if self:is_selectable(self.rows[i]) then
         self:select(i)
         return true
      end
   end
   return false
end

function ui.sheet:next_input(dir)
   local i = self.sel or 0
   local n = #self.rows
   for _ = 1, n do
      i = i + dir
      if i < 1 then i = n elseif i > n then i = 1 end
      local r = self.rows[i]
      if r and (r.kind == 'input' or r.kind == 'choice') then
         self:select(i)
         return true
      end
   end
   return false
end

-- Editing -------------------------------------------------------------------------

function ui.sheet:begin_edit()
   local r = self:selected()
   if r and r.kind == 'input' then
      local chars = chars_of(r.text or '')
      self.edit = { row = r, chars = chars, cur = #chars + 1, orig = r.text or '' }
   else
      self.edit = nil
   end
end

function ui.sheet:edit_text()
   return self.edit and join(self.edit.chars) or nil
end

-- Commit edit; returns true if the text changed
function ui.sheet:commit_edit()
   local e = self.edit
   if not e then return false end
   local text = join(e.chars)
   if text ~= e.orig then
      e.row.text = text
      e.row._lay = nil
      e.orig = text
      if self.on_commit then self:on_commit(e.row) end
      return true
   end
   return false
end

function ui.sheet:revert_edit()
   local e = self.edit
   if e and join(e.chars) ~= e.orig then
      e.chars = chars_of(e.orig)
      e.cur = #e.chars + 1
      return true
   end
   return false
end

local closers = { ['('] = ')', ['['] = ']', ['{'] = '}' }

function ui.sheet:insert(text)
   local e = self.edit
   if not e then return end
   local ins = chars_of(text)
   -- skip over an existing closing paren
   if #ins == 1 and (ins[1] == ')' or ins[1] == ']' or ins[1] == '}') and e.chars[e.cur] == ins[1] then
      e.cur = e.cur + 1
      return
   end
   for k, ch in ipairs(ins) do
      table.insert(e.chars, e.cur + k - 1, ch)
   end
   e.cur = e.cur + #ins
   -- auto close for keys like 'sin(' or '√(' (calculator keys insert '(')
   local last = ins[#ins]
   if last and closers[last] and (#ins > 1 or text == '(') then
      table.insert(e.chars, e.cur, closers[last])
   end
   e.row._lay = nil
end

function ui.sheet:delete_back()
   local e = self.edit
   if not e or e.cur <= 1 then return end
   local ch = e.chars[e.cur - 1]
   table.remove(e.chars, e.cur - 1)
   e.cur = e.cur - 1
   if closers[ch] and e.chars[e.cur] == closers[ch] then
      table.remove(e.chars, e.cur)
   end
end

-- Layout ---------------------------------------------------------------------------

local function seg_lines(gc, segs, size, width, color)
   -- Flow segments into lines of boxes
   local lines = {}
   local cur, cur_w = {}, 0
   local function flush()
      if #cur > 0 then
         table.insert(lines, mb.hbox(cur))
      end
      cur, cur_w = {}, 0
   end
   local function add(box)
      if cur_w + box.w > width and #cur > 0 then
         flush()
      end
      box.color = color
      table.insert(cur, box)
      cur_w = cur_w + box.w
   end
   for _, s in ipairs(segs) do
      if s.m then
         add(mb.layout(s.m, size, gc))
      else
         -- split into words keeping spaces attached
         for word in s.t:gmatch('%s*[^%s]+%s*') do
            add(mb.text(word, size, gc))
         end
         if s.t:match('^%s+$') then add(mb.text(s.t, size, gc)) end
      end
   end
   flush()
   if #lines == 0 then
      table.insert(lines, mb.text('', size, gc))
   end
   return lines
end

local function stack(lines, gap)
   local h, w = 0, 0
   for i, l in ipairs(lines) do
      h = h + l.h + (i > 1 and gap or 0)
      w = max(w, l.w)
   end
   return { w = w, h = h, lines = lines, gap = gap }
end

local function draw_stack(st, g, x, y)
   local cy = y
   for _, l in ipairs(st.lines) do
      mb.draw(l, g, x, cy)
      cy = cy + l.h + st.gap
   end
end

-- Compute label column width
function ui.sheet:label_width(gc, W)
   if self._label_w and self._label_w_for == W then return self._label_w end
   local lw = 0
   for _, r in ipairs(self.rows) do
      if (r.kind == 'input' or r.kind == 'choice') and r.label then
         local lines = seg_lines(gc, report.segments(r.label), self.font, 1000)
         lw = max(lw, lines[1].w)
      end
   end
   lw = min(lw + 8, floor(W * self.label_max))
   self._label_w, self._label_w_for = lw, W
   return lw
end

local PAD = 3

function ui.sheet:layout_row(gc, r, W)
   local editing = (self.edit ~= nil and self.edit.row == r)
   if r._lay and r._lay.W == W and r._lay.font == self.font and r._lay.editing == editing then
      return r._lay
   end
   local S = self.font
   local small = mb.snap(max(7, S - 1))
   local L = { W = W, font = S, editing = editing }
   local k = r.kind

   if k == 'header' then
      L.content = stack(seg_lines(gc, report.segments(r.text or ''), small, W - 2 * PAD), 0)
      L.h = L.content.h + 4
   elseif k == 'input' or k == 'choice' then
      local lw = self:label_width(gc, W)
      L.lw = lw
      L.label = stack(seg_lines(gc, report.segments(type(r.label) == 'string' and r.label or ''), S, lw - 4), 0)
      local vw = W - lw - 2 * PAD
      if k == 'choice' then
         local opt = r.options[r.index or 1]
         local txt = opt and (opt[2] or opt[1]) or ''
         L.value = mb.text('< ' .. txt .. ' >', S, gc)
         L.h = max(L.label.h, L.value.h) + 2 * PAD
      elseif L.editing then
         L.th = mb.text('Ag', S, gc).h
         L.h = max(L.label.h, L.th + 4) + 2 * PAD
         local text = self:edit_text() or ''
         local wants = text ~= '' and (text:find('[/%^]') or text:find(sym.ROOT, 1, true)
                                       or text:find('sqrt') or text:find('integral') or text:find('abs'))
         if wants then
            local disp = self.input_display and self:input_display(r, text) or text
            L.preview = mb.layout(disp, S, gc)
            L.h = L.h + L.preview.h + 2
         end
      else
         local text = r.text or ''
         if text == '' then
            L.value = mb.text(r.hint or '', small, gc)
            L.hint = true
         else
            local disp = self.input_display and self:input_display(r, text) or text
            L.value = mb.layout(disp, S, gc)
         end
         L.h = max(L.label.h, L.value.h) + 2 * PAD
      end
      L.vw = vw
   elseif k == 'result' then
      local label = stack(seg_lines(gc, report.segments(r.label or ''), S, W * 0.5), 0)
      local val = self.value_text and self:value_text(r) or r.exact or ''
      local vb = mb.layout(val, S, gc)
      local eq = mb.text(r.mode == 'approx' and (' ' .. sym.APPROX .. ' ') or ' = ', S, gc)
      L.label, L.value, L.eq = label, vb, eq
      if label.w + eq.w + vb.w + 2 * PAD <= W then
         L.inline = true
         L.h = max(label.h, vb.h) + 2 * PAD
      else
         L.inline = false
         L.h = label.h + vb.h + 3 * PAD
      end
   elseif k == 'step' then
      local numw = r.num and mb.text(r.num .. '.', small, gc).w + 4 or 0
      L.numw = numw
      L.content = stack(seg_lines(gc, report.segments(r.text or ''), r.section and small or S, W - 2 * PAD - numw), 2)
      L.h = L.content.h + 2 * PAD
   elseif k == 'note' or k == 'text' then
      L.content = stack(seg_lines(gc, report.segments(r.text or ''), k == 'note' and small or S, W - 2 * PAD), 1)
      L.h = L.content.h + 2 * PAD
   elseif k == 'link' then
      L.title = mb.text(r.title or '', S, gc, 'b')
      L.desc = r.desc and stack(seg_lines(gc, report.segments(r.desc), small, W - 30), 0)
      L.key = r.key and mb.text(r.key, small, gc, 'b')
      L.h = L.title.h + (L.desc and L.desc.h or 0) + 2 * PAD
   elseif k == 'math' then
      L.content = mb.layout(r.m or '', S, gc)
      L.h = L.content.h + 2 * PAD + 2
   else
      L.h = 4
   end
   r._lay = L
   return L
end

function ui.sheet:layout_rows(gc)
   local W = self:frame().width - 2
   local y = 0
   for _, r in ipairs(self.rows) do
      local L = self:layout_row(gc, r, W)
      r._y = y
      y = y + L.h
   end
   self.content_h = y
end

function ui.sheet:with_layout(fn)
   return ui.GC.with_gc(function(g)
      self:layout_rows(g.gc)
      return fn(g.gc)
   end)
end

function ui.sheet:ensure_visible_sel()
   local r = self:selected()
   if not r then return end
   self:with_layout(function()
      local f = self:frame()
      local top, bottom = r._y, r._y + r._lay.h
      -- show the header above the first selectable row
      if self.sel and self.sel <= 3 then
         local first_sel = true
         for i = 1, self.sel - 1 do
            if self:is_selectable(self.rows[i]) then first_sel = false end
         end
         if first_sel then top = 0 end
      end
      if top < self.scroll_y then
         self.scroll_y = top
      elseif bottom > self.scroll_y + f.height then
         self.scroll_y = min(top, bottom - f.height)
      end
      self.scroll_y = max(0, self.scroll_y)
   end)
end

-- Drawing ---------------------------------------------------------------------------

local function set_color(g, c)
   g:setColorRGB(c)
end

function ui.sheet:draw_self(wgc)
   local g = wgc.gc
   local f = self:frame()
   set_color(g, C.bg)
   g:fillRect(f.x, f.y, f.width, f.height)
   self:layout_rows(g)

   local W = f.width - 2
   local x0 = f.x + 1
   for i, r in ipairs(self.rows) do
      local L = r._lay
      local y = f.y + r._y - self.scroll_y
      if y + L.h >= f.y and y <= f.y + f.height then
         self:draw_row(g, r, L, x0, y, W, i == self.sel)
      end
   end

   -- scroll indicator
   if self.content_h and self.content_h > f.height then
      local bar_h = max(10, floor(f.height * f.height / self.content_h))
      local bar_y = f.y + floor((f.height - bar_h) * self.scroll_y / max(1, self.content_h - f.height))
      set_color(g, 0xB0B0B0)
      g:fillRect(f.x + f.width - 3, bar_y, 2, bar_h)
   end
end

function ui.sheet:draw_row(g, r, L, x, y, W, selected)
   local k = r.kind
   if selected then
      set_color(g, C.sel)
      g:fillRect(x, y, W, L.h)
   end

   if k == 'header' then
      set_color(g, C.header_bg)
      g:fillRect(x, y, W, L.h)
      set_color(g, C.header)
      draw_stack(L.content, g, x + PAD, y + 2)
   elseif k == 'input' or k == 'choice' then
      set_color(g, C.label)
      draw_stack(L.label, g, x + PAD, y + PAD + floor((L.h - 2 * PAD - L.label.h) / 2))
      local vx = x + L.lw
      if k == 'input' and L.editing then
         local fh = L.th + 4
         set_color(g, C.field)
         g:fillRect(vx, y + PAD - 1, L.vw, fh)
         set_color(g, C.sel_border)
         g:drawRect(vx, y + PAD - 1, L.vw, fh)
         -- text with caret, scrolled to keep the caret visible
         local e = self.edit
         g:setFont('sansserif', 'r', self.font)
         local before = join(e.chars, 1, e.cur - 1)
         local cw = g:getStringWidth(before)
         local off = max(0, cw - (L.vw - 8))
         local tx = vx + 3 - off
         local text = join(e.chars)
         set_color(g, C.text)
         -- clip to field
         g:clipRect('set', vx + 1, y + PAD, L.vw - 2, fh - 1)
         g:drawString(text, tx, y + PAD + 1, 'top')
         set_color(g, C.caret)
         g:fillRect(tx + cw, y + PAD, 2, L.th + 2)
         g:clipRect('reset')
         local f = self:frame()
         g:clipRect('set', f.x, f.y, f.width + 1, f.height + 1)
         if text == '' and r.hint then
            set_color(g, C.hint)
            g:setFont('sansserif', 'r', mb.snap(max(7, self.font - 1)))
            g:drawString(r.hint, vx + 6, y + PAD + 2, 'top')
         end
         if L.preview then
            set_color(g, C.text)
            mb.draw(L.preview, g, vx + 3, y + PAD + fh + 2)
         end
      else
         set_color(g, L.hint and C.hint or C.text)
         local vy = y + PAD + floor((L.h - 2 * PAD - L.value.h) / 2)
         local vbox = L.value
         local cx = vx + 3
         if vbox.w > L.vw - 4 and selected then
            cx = cx - self.hscroll
         end
         mb.draw(vbox, g, cx, vy)
      end
   elseif k == 'result' then
      local lx = x + PAD
      if L.inline then
         local ly = y + PAD
         local h = L.h - 2 * PAD
         set_color(g, C.label)
         draw_stack(L.label, g, lx, ly + floor((h - L.label.h) / 2))
         set_color(g, r.mode == 'approx' and C.approx or C.text)
         mb.draw(L.eq, g, lx + L.label.w, ly + floor((h - L.eq.h) / 2))
         set_color(g, C.text)
         mb.draw(L.value, g, lx + L.label.w + L.eq.w, ly + floor((h - L.value.h) / 2))
      else
         set_color(g, C.label)
         draw_stack(L.label, g, lx, y + PAD)
         local vx = x + W - PAD - L.value.w
         if L.value.w > W - 2 * PAD then
            vx = x + PAD - (selected and self.hscroll or 0)
         end
         set_color(g, r.mode == 'approx' and C.approx or C.text)
         mb.draw(L.eq, g, max(x + PAD, vx - L.eq.w), y + 2 * PAD + L.label.h)
         set_color(g, C.text)
         mb.draw(L.value, g, vx, y + 2 * PAD + L.label.h)
      end
   elseif k == 'step' then
      if r.num then
         set_color(g, C.num)
         g:setFont('sansserif', 'r', mb.snap(max(7, self.font - 1)))
         g:drawString(r.num .. '.', x + PAD, y + PAD + 1, 'top')
      end
      set_color(g, r.section and C.header or C.text)
      local cx = x + PAD + L.numw
      if L.content.w > W - 2 * PAD - L.numw and selected then cx = cx - self.hscroll end
      draw_stack(L.content, g, cx, y + PAD)
   elseif k == 'note' then
      set_color(g, C[r.kind_color or r.level or 'info'] or C.info)
      draw_stack(L.content, g, x + PAD, y + PAD)
   elseif k == 'text' then
      set_color(g, C.text)
      draw_stack(L.content, g, x + PAD, y + PAD)
   elseif k == 'link' then
      local tx = x + PAD
      if L.key then
         set_color(g, C.link_key)
         g:drawRect(x + PAD, y + PAD, 14, L.title.h - 1)
         mb.draw(L.key, g, x + PAD + floor((15 - L.key.w) / 2), y + PAD)
         tx = x + PAD + 20
      end
      set_color(g, C.text)
      mb.draw(L.title, g, tx, y + PAD)
      if L.desc then
         set_color(g, C.info)
         draw_stack(L.desc, g, tx, y + PAD + L.title.h)
      end
   elseif k == 'math' then
      set_color(g, C.text)
      local cx = x + max(PAD, floor((W - L.content.w) / 2))
      if L.content.w > W - 2 * PAD and selected then cx = x + PAD - self.hscroll end
      mb.draw(L.content, g, cx, y + PAD + 1)
   end

   -- separator under results/inputs
   if k == 'input' or k == 'choice' or k == 'result' then
      set_color(g, 0xEEEEEE)
      g:drawLine(x, y + L.h - 1, x + W, y + L.h - 1)
   end
end

-- Width of the widest box in a row (for horizontal scrolling)
function ui.sheet:row_content_width(r)
   local L = r._lay
   if not L then return 0 end
   if r.kind == 'result' then
      return L.inline and (L.label.w + L.eq.w + L.value.w) or L.value.w
   elseif r.kind == 'step' then
      return L.content.w + L.numw
   elseif r.kind == 'math' then
      return L.content.w
   elseif r.kind == 'input' and L.value then
      return L.lw + L.value.w
   end
   return 0
end

function ui.sheet:hscroll_by(dir)
   local r = self:selected()
   if not r or not r._lay then return false end
   local W = self:frame().width - 2
   local cw = self:row_content_width(r)
   if cw <= W - 6 then return false end
   local maxs = cw - W + 12
   local ns = max(0, min(maxs, self.hscroll + dir * floor(W / 3)))
   if ns == self.hscroll then return false end
   self.hscroll = ns
   return true
end

-- Events ------------------------------------------------------------------------------

function ui.sheet:on_up()
   self:move(-1)
end

function ui.sheet:on_down()
   self:move(1)
end

function ui.sheet:on_tab()
   self:next_input(1)
end

function ui.sheet:on_backtab()
   self:next_input(-1)
end

local function cycle(self, r, dir)
   local n = #r.options
   r.index = ((r.index or 1) - 1 + dir) % n + 1
   r._lay = nil
   if self.on_choice then self:on_choice(r) end
end

function ui.sheet:toggle(r)
   r.mode = r.mode == 'approx' and 'exact' or 'approx'
   r._lay = nil
   self.hscroll = 0
   if self.on_toggle then self:on_toggle(r) end
end

function ui.sheet:on_left()
   local r = self:selected()
   if not r then return end
   if self.edit then
      self.edit.cur = max(1, self.edit.cur - 1)
   elseif r.kind == 'choice' then
      cycle(self, r, -1)
   elseif not self:hscroll_by(-1) and r.kind == 'result' then
      if r.mode == 'approx' then self:toggle(r) end
   end
end

function ui.sheet:on_right()
   local r = self:selected()
   if not r then return end
   if self.edit then
      self.edit.cur = min(#self.edit.chars + 1, self.edit.cur + 1)
   elseif r.kind == 'choice' then
      cycle(self, r, 1)
   elseif not self:hscroll_by(1) and r.kind == 'result' then
      if r.mode ~= 'approx' then self:toggle(r) end
   end
end

function ui.sheet:on_char(c)
   if self.edit then
      self:insert(c)
      return
   end
   if self.on_shortcut and self:on_shortcut(c) then return end
   -- typing on a non-input row jumps to the first empty input
   local r = self:selected()
   if r and r.kind == 'choice' then
      local d = tonumber(c)
      if d and r.options[d] then
         r.index = d
         r._lay = nil
         if self.on_choice then self:on_choice(r) end
      end
   end
end

function ui.sheet:on_backspace()
   if self.edit then
      self:delete_back()
      return
   end
   local r = self:selected()
   if self.on_delete then self:on_delete(r) end
end

function ui.sheet:on_clear()
   if self.edit then
      self.edit.chars = {}
      self.edit.cur = 1
   end
end

function ui.sheet:on_enter_key()
   local r = self:selected()
   if not r then return end
   if r.kind == 'input' then
      self:commit_edit()
      if self.on_submit then self:on_submit(r) end
   elseif r.kind == 'choice' then
      cycle(self, r, 1)
   elseif r.kind == 'result' then
      self:toggle(r)
   elseif r.kind == 'link' then
      if self.on_activate then self:on_activate(r) end
   end
end

function ui.sheet:on_return()
   self:on_enter_key()
end

function ui.sheet:on_escape()
   if self.edit and self:revert_edit() then return end
   if self.on_escape_cb then self:on_escape_cb() end
end

function ui.sheet:on_ctx()
   if self.on_context then self:on_context(self:selected()) end
end

function ui.sheet:row_at(py)
   local f = self:frame()
   local y = py - f.y + self.scroll_y
   self:with_layout(function() end)
   for i, r in ipairs(self.rows) do
      if r._y and y >= r._y and y < r._y + r._lay.h then
         return i, r
      end
   end
end

function ui.sheet:on_mouse_down(x, y)
   local i, r = self:row_at(y)
   if not i or not self:is_selectable(r) then return end
   local was = self.sel == i
   self:select(i)
   r = self:selected()
   if not r then return end
   if r.kind == 'result' then
      self:toggle(r)
   elseif r.kind == 'link' then
      if self.on_activate then self:on_activate(r) end
   elseif r.kind == 'choice' and was then
      cycle(self, r, 1)
   elseif r.kind == 'input' and self.edit and r._lay and r._lay.lw then
      -- place caret at the click position
      local f = self:frame()
      local rel = x - f.x - 1 - r._lay.lw - 3
      ui.GC.with_gc(function(g)
         g.gc:setFont('sansserif', 'r', self.font)
         local e = self.edit
         e.cur = #e.chars + 1
         for k = 1, #e.chars do
            if g.gc:getStringWidth(join(e.chars, 1, k)) > rel then
               e.cur = k
               break
            end
         end
      end)
   end
end

function ui.sheet:on_copy()
   local r = self:selected()
   if not r or not self.copy_text then return end
   local s = self:copy_text(r)
   if s and clipboard then clipboard.addText(s) end
end

function ui.sheet:on_cut()
   self:on_copy()
end

function ui.sheet:on_paste()
   if self.edit and clipboard then
      local s = clipboard.getText()
      if s then self:insert(s) end
   end
end

function ui.sheet:on_help()
   if self.on_help_cb then self:on_help_cb() end
end

return ui.sheet
