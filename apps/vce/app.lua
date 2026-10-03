-- VCE Specialist toolkit: screens, navigation, history and menus
local class = require 'class'
local ui = require 'ui'
require 'views.container'
require 'views.label'
require 'views.edit'
require 'views.list'
require 'views.menu'
require 'views.sheet'
local mb = require 'ui.mathbox'
local cas = require 'apps.vce.cas'
local fmt = require 'apps.vce.fmt'
local report = require 'apps.vce.report'
local solvers = require 'apps.vce.registry'
local History = require 'apps.vce.history'
local selftest = require 'apps.vce.selftest'
local sym = require 'ti.sym'

local A = {}

A.VERSION = '1.0'
A.settings = { dp = 4, font = 10, mode = 'exact' }
A.history = History.new()
A.screen = 'home'
A.filter = ''
A.host = nil

local FONT_SIZES = { small = 9, normal = 10, large = 12 }

-- Bar view (title / hint line) ------------------------------------------------------

local Bar = class(ui.view)

function Bar:init(layout, size, bg, fg)
   ui.view.init(self, layout)
   self.left, self.right = '', ''
   self.size, self.bg, self.fg = size, bg, fg
end

function Bar:draw_self(wgc)
   local g = wgc.gc
   local f = self:frame()
   g:setColorRGB(self.bg)
   g:fillRect(f.x, f.y, f.width, f.height)
   g:setColorRGB(self.fg)
   g:setFont('sansserif', self.bold and 'b' or 'r', self.size)
   local rw = self.right ~= '' and g:getStringWidth(self.right) or 0
   local th = g:getStringHeight('A')
   local ty = f.y + math.floor((f.height - th) / 2)
   g:clipRect('set', f.x, f.y, f.width - rw - 6, f.height)
   g:drawString(self.left, f.x + 3, ty, 'top')
   g:clipRect('set', f.x, f.y, f.width + 1, f.height + 1)
   if rw > 0 then
      g:drawString(self.right, f.x + f.width - rw - 3, ty, 'top')
   end
end

-- Helpers ---------------------------------------------------------------------------

local function trim(s)
   return (s or ''):match('^%s*(.-)%s*$')
end

local function errmsg(err)
   if type(err) == 'table' then return err.desc or tostring(err.code) end
   return tostring(err)
end

local function inputs_for(s, p)
   local I = {}
   for _, f in ipairs(s.fields) do
      local v = p.inputs[f.id]
      if f.kind == 'choice' then
         I[f.id] = v or f.options[1][1]
      elseif v and trim(v) ~= '' then
         I[f.id] = v
      end
   end
   return I
end

local function summary(p)
   local s = solvers.get(p.solver)
   if not s then return '' end
   local parts = {}
   for _, f in ipairs(s.fields) do
      local v = p.inputs[f.id]
      if v and trim(v) ~= '' and #parts < 4 then
         local label = type(f.label) == 'function' and f.label(inputs_for(s, p)) or f.label
         label = report.plain(label):gsub('%s*=$', '')
         table.insert(parts, label .. '=' .. v)
      end
   end
   return table.concat(parts, ', ')
end

local function problem_title(p)
   local s = solvers.get(p.solver)
   local t = s and s.short or p.solver
   if p.tag and p.tag ~= '' then
      return '[' .. p.tag .. '] ' .. t
   end
   return t
end

-- Main variable of a solver (for inserting document functions)
local function main_var(p)
   if p.solver == 'kinematics' then
      local t = p.inputs.type or 'a(t)'
      return t:match('%((%a)%)') or 't'
   end
   return 'x'
end

-- Value shown for a result row
function A.value_text(row)
   local e = row.exact or ''
   if row.mode == 'approx' then
      if fmt.has_decimal(e) then
         return e
      end
      if not row._approx then
         row._approx = cas.eval('approx(' .. e .. ')') or e
      end
      return fmt.round_expr(row._approx, A.settings.dp)
   end
   if fmt.has_decimal(e) then
      return fmt.round_expr(e, A.settings.dp)
   end
   return e
end

-- Build UI --------------------------------------------------------------------------

function A.build()
   local root = ui.container(ui.rel { top = 0, bottom = 0, left = 0, right = 0 })
   root.style = 'none'
   local title = Bar(ui.rel { top = 0, left = 0, right = 0, height = 17 }, 9, 0x24476B, 0xFFFFFF)
   title.bold = true
   local hint = Bar(ui.rel { bottom = 0, left = 0, right = 0, height = 13 }, 7, 0xEDEDED, 0x505050)
   local sheet = ui.sheet(ui.rel { top = 17, bottom = 13, left = 0, right = 0 })
   sheet:set_font(A.settings.font)
   root:add_child(title)
   root:add_child(sheet)
   root:add_child(hint)
   A.root, A.title, A.hint, A.sheet = root, title, hint, sheet

   sheet.value_text = function(_, row) return A.value_text(row) end
   sheet.input_display = function(_, _, text)
      return cas.input(text) or text
   end
   sheet.copy_text = function(_, row)
      if row.kind == 'result' then return fmt.plain(A.value_text(row)) end
      if row.kind == 'step' or row.kind == 'note' or row.kind == 'text' then return report.plain(row.text) end
      if row.kind == 'input' then return row.text end
      if row.kind == 'math' then return fmt.plain(row.m) end
   end
   sheet.on_select = function(_, row) A.update_hint(row) end
   sheet.on_commit = function(_, row) A.safe(A.on_commit, row) end
   sheet.on_submit = function(_, row) A.safe(A.on_submit, row) end
   sheet.on_choice = function(_, row) A.safe(A.on_choice, row) end
   sheet.on_activate = function(_, row) A.safe(A.on_activate, row) end
   sheet.on_toggle = function(_, row) A.safe(A.on_toggle, row) end
   sheet.on_escape_cb = function() A.safe(A.on_escape) end
   sheet.on_context = function(_, row) A.safe(A.on_context, row) end
   sheet.on_delete = function(_, row) A.safe(A.on_delete, row) end
   sheet.on_shortcut = function(_, c) return A.on_shortcut(c) end
   sheet.on_help_cb = function() A.show_help() end
   return root
end

function A.safe(fn, ...)
   local ok, err = pcall(fn, ...)
   if not ok then
      A.error(errmsg(err))
   end
   ui.update()
end

function A.error(msg)
   local dlg = require 'dialog.error'
   dlg.display('Error', msg)
end

function A.set_title(left, right)
   A.title.left = left or ''
   A.title.right = right or ''
end

local HINTS = {
   input = 'type value  ' .. sym.CDOT .. '  enter: solve  ' .. sym.CDOT .. '  tab: next  ' .. sym.CDOT .. '  esc: home',
   choice = 'left/right: change option  ' .. sym.CDOT .. '  menu: options',
   result = 'enter/click: exact ' .. sym.DLIMP .. ' decimal  ' .. sym.CDOT .. '  ctrl+C copy  ' .. sym.CDOT .. '  n/p: next/prev',
   step = 'up/down scroll  ' .. sym.CDOT .. '  right: long lines  ' .. sym.CDOT .. '  t: tag  h: history',
   link = 'enter: open  ' .. sym.CDOT .. '  digits: quick open',
   math = 'left/right: scroll',
}

function A.update_hint(row)
   if A.screen == 'history' then
      A.hint.left = 'enter: open  ' .. sym.CDOT .. '  type: filter  ' .. sym.CDOT .. '  del: delete  ' .. sym.CDOT .. '  esc: home'
   else
      A.hint.left = row and HINTS[row.kind] or 'menu: options  ' .. sym.CDOT .. '  esc: back'
   end
end

-- Home ------------------------------------------------------------------------------

function A.show_home()
   A.screen = 'home'
   A.set_title('VCE Specialist Maths toolkit', 'menu: options')
   local rows = {}
   local group
   for i, s in ipairs(solvers.list) do
      if s.group ~= group then
         group = s.group
         table.insert(rows, { kind = 'header', text = group })
      end
      table.insert(rows, { kind = 'link', key = tostring(i % 10), title = s.title, desc = s.desc,
                           action = { 'new', s.id }, id = 'solver:' .. s.id })
   end
   local items = A.history.items
   if #items > 0 then
      table.insert(rows, { kind = 'header', text = 'Recent' })
      for i = #items, math.max(1, #items - 3), -1 do
         local p = items[i]
         table.insert(rows, { kind = 'link', title = problem_title(p), desc = summary(p),
                              action = { 'open', i }, id = 'recent:' .. p.id })
      end
   end
   table.insert(rows, { kind = 'header', text = 'More' })
   table.insert(rows, { kind = 'link', title = 'History (' .. #items .. ')', desc = 'all problems, tags, search',
                        action = { 'history' }, id = 'history' })
   table.insert(rows, { kind = 'link', title = 'Help & keys', action = { 'help' }, id = 'help' })
   table.insert(rows, { kind = 'link', title = 'Self-test', desc = 'check the solvers with this calculator\'s CAS',
                        action = { 'selftest' }, id = 'selftest' })
   A.sheet:set_rows(rows, true)
   A.update_hint(A.sheet:selected())
end

-- Problem ---------------------------------------------------------------------------

function A.new_problem(sid, inputs)
   -- reuse a trailing empty problem of the same type
   local last = A.history.items[#A.history.items]
   if last and last.solver == sid and History.is_empty(last) and not inputs then
      A.show_problem(#A.history.items)
      return
   end
   local _, idx = A.history:add(sid, inputs)
   A.show_problem(idx)
end

function A.current()
   return A.history:get()
end

function A.build_problem_rows(p, R, I)
   local s = solvers.get(p.solver)
   local rows = {}
   table.insert(rows, { kind = 'header', text = s.title })
   for _, f in ipairs(s.fields) do
      if not f.show or f.show(I) then
         local label = type(f.label) == 'function' and f.label(I) or f.label
         if f.kind == 'choice' then
            local cur = p.inputs[f.id] or f.options[1][1]
            local idx = 1
            for k, o in ipairs(f.options) do
               if o[1] == cur then idx = k end
            end
            table.insert(rows, { kind = 'choice', id = f.id, label = label, options = f.options, index = idx })
         else
            table.insert(rows, { kind = 'input', id = f.id, label = label, text = p.inputs[f.id] or '', hint = f.hint })
         end
      end
   end
   if R.display then
      table.insert(rows, { kind = 'math', m = R.display, key = 'display' })
   end
   for i, n in ipairs(R.notes) do
      table.insert(rows, { kind = 'note', text = n.text, level = n.kind, key = 'note' .. i })
   end
   p.modes = p.modes or {}
   if #R.results > 0 then
      table.insert(rows, { kind = 'header', text = 'Results' })
      for _, r in ipairs(R.results) do
         local key = 'res:' .. (r.key or r.label)
         table.insert(rows, { kind = 'result', key = key, label = r.label, exact = r.exact,
                              mode = p.modes[key] or A.settings.mode })
      end
   end
   if #R.steps > 0 then
      table.insert(rows, { kind = 'header', text = 'Working' })
      local n = 0
      for i, st in ipairs(R.steps) do
         if st.section then
            table.insert(rows, { kind = 'step', text = st.text, section = true, key = 'step' .. i })
         else
            n = n + 1
            table.insert(rows, { kind = 'step', text = st.text, num = n, key = 'step' .. i })
         end
      end
   end
   return rows
end

function A.solve(p)
   local s = solvers.get(p.solver)
   local I = inputs_for(s, p)
   local R = report.new()
   fmt.dp = A.settings.dp
   local ok, err = pcall(s.solve, I, R)
   if not ok then
      R:note('Error: ' .. errmsg(err), 'error')
   end
   return R, I
end

function A.refresh_problem(keep)
   local p = A.current()
   if not p then return A.show_home() end
   local R, I = A.solve(p)
   A.last_report = R
   A.sheet:set_rows(A.build_problem_rows(p, R, I), keep)
   A.update_problem_title()
   A.update_hint(A.sheet:selected())
end

function A.update_problem_title()
   local p = A.current()
   A.set_title(problem_title(p), tostring(A.history.current) .. '/' .. tostring(#A.history.items))
end

function A.show_problem(idx)
   A.screen = 'problem'
   A.history.current = idx
   A.refresh_problem(false)
end

function A.on_commit(row)
   if A.screen ~= 'problem' then return end
   local p = A.current()
   p.inputs[row.id] = row.text
   A.refresh_problem(true)
end

function A.on_submit(_)
   if A.screen ~= 'problem' then return end
   local sh = A.sheet
   -- move to the next input; after the last one jump to the results
   local i = sh.sel or 0
   for k = i + 1, #sh.rows do
      local r = sh.rows[k]
      if r.kind == 'input' or r.kind == 'choice' then
         sh:select(k)
         return
      end
      if r.kind == 'result' then break end
   end
   for k = 1, #sh.rows do
      if sh.rows[k].kind == 'result' then
         sh:select(k)
         return
      end
   end
end

function A.on_choice(row)
   if A.screen ~= 'problem' then return end
   local p = A.current()
   p.inputs[row.id] = row.options[row.index][1]
   A.refresh_problem(true)
end

function A.on_toggle(row)
   local p = A.current()
   if A.screen == 'problem' and p and row.key then
      p.modes = p.modes or {}
      p.modes[row.key] = row.mode
   end
end

function A.on_activate(row)
   local a = row.action
   if not a then return end
   if a[1] == 'new' then
      A.new_problem(a[2])
   elseif a[1] == 'open' then
      A.show_problem(a[2])
   elseif a[1] == 'history' then
      A.show_history()
   elseif a[1] == 'help' then
      A.show_help()
   elseif a[1] == 'selftest' then
      A.show_selftest()
   end
end

function A.on_escape()
   if A.screen == 'home' then
      if A.host and A.close then A.close() end
      return
   end
   if A.screen == 'history' and A.filter ~= '' then
      A.filter = ''
      A.show_history()
      return
   end
   A.show_home()
end

function A.go(delta)
   local n = #A.history.items
   if n == 0 then return end
   local i = (A.history.current or n) + delta
   if i < 1 then i = 1 end
   if i > n then i = n end
   A.show_problem(i)
end

function A.on_shortcut(c)
   if A.screen == 'home' then
      local d = tonumber(c)
      if d then
         local idx = d == 0 and 10 or d
         local s = solvers.list[idx]
         if s then
            A.safe(A.new_problem, s.id)
            return true
         end
      end
      if c == 'h' then A.safe(A.show_history) return true end
      return false
   elseif A.screen == 'history' then
      if c:match('^[%w%s%.%-]$') then
         A.filter = A.filter .. c
         A.show_history()
         return true
      end
      return false
   elseif A.screen == 'problem' then
      local map = {
         n = function() A.go(1) end,
         p = function() A.go(-1) end,
         t = function() A.tag_dialog() end,
         h = function() A.show_history() end,
         d = function() A.set_all_modes('approx') end,
         e = function() A.set_all_modes('exact') end,
      }
      local f = map[c]
      if f then
         A.safe(f)
         return true
      end
   end
   return false
end

function A.on_delete(row)
   if A.screen == 'history' then
      if A.filter ~= '' then
         A.filter = A.filter:sub(1, -2)
         A.show_history()
         return
      end
      if row and row.action and row.action[1] == 'open' then
         A.confirm('Delete ' .. row.title .. '?', function()
            A.history:remove(row.action[2])
            A.show_history()
         end)
      end
   end
end

function A.set_all_modes(mode)
   A.settings.mode = mode
   local p = A.current()
   if p then p.modes = {} end
   if A.screen == 'problem' then A.refresh_problem(true) end
end

-- Dialogs ---------------------------------------------------------------------------

function A.confirm(title, yes)
   local dlg = require('dialog.list').display({
      title = title,
      items = { { title = 'Yes', result = true }, { title = 'No', result = false } },
   })
   dlg.on_done = function(row)
      if row and row.result then A.safe(yes) end
   end
end

function A.tag_dialog()
   local p = A.current()
   if not p then return end
   local dlg = require('dialog.input').display({ title = 'Tag / label (e.g. 2023 E2 Q5b)', text = p.tag or '' })
   dlg.on_done = function(text)
      p.tag = trim(text)
      if A.screen == 'problem' then A.update_problem_title() end
      ui.update()
   end
end

function A.store_dialog()
   local row = A.sheet:selected()
   if not row or row.kind ~= 'result' then
      A.error('Select a result first')
      return
   end
   local dlg = require('dialog.input').display({ title = 'Store ' .. fmt.plain(A.value_text(row)) .. ' to variable' })
   dlg.on_done = function(name)
      name = trim(name)
      if name == '' then return end
      local value = row.mode == 'approx' and A.value_text(row) or row.exact
      local res, err = cas.eval(cas.p(value) .. sym.STORE .. name)
      if not res then A.error('Could not store (' .. tostring(err) .. ')') end
   end
end

-- Insert text into the selected input row
function A.insert(text)
   local sh = A.sheet
   if sh.edit then
      sh:insert(text)
      ui.update()
      return true
   end
   return false
end

function A.function_menu()
   if not A.sheet.edit then
      A.error('Select an input field first')
      return
   end
   local p = A.current()
   local v = p and main_var(p) or 'x'
   local items = {}
   local names = (var and var.list and var.list()) or {}
   table.sort(names)
   for _, name in ipairs(names) do
      if cas.eval('getType(' .. name .. ')') == '"FUNC"' then
         local body = cas.eval(name .. '(' .. v .. ')') or ''
         local title = name .. '(' .. v .. ')'
         if #body < 28 then title = title .. ' = ' .. fmt.plain(body) end
         table.insert(items, { title = title, action = function() A.insert(name .. '(' .. v .. ')') end })
      end
   end
   if #items == 0 then
      A.error('No functions defined in this problem (e.g. f11(x):=...)')
      return
   end
   ui.menu.menu_at_point(A.sheet, items, ui.point(20, 40))
end

function A.symbol_menu()
   local syms = {
      { sym.LEQ, 'less or equal' }, { sym.GEQ, 'greater or equal' }, { sym.NEQ, 'not equal' },
      { sym.INFTY, 'infinity' }, { sym.pi, 'pi' }, { sym.ROOT .. '(', 'square root' },
      { sym.EULER .. '^(', 'e^' }, { 'ln(', 'natural log' }, { '|', 'given (conditional)' },
      { 'integral(', 'integral(f,x,a,b)' }, { 'abs(', 'absolute value' },
   }
   local items = {}
   for _, s in ipairs(syms) do
      table.insert(items, { title = s[1] .. '   ' .. s[2], action = function() A.insert(s[1]) end })
   end
   ui.menu.menu_at_point(A.sheet, items, ui.point(20, 40))
end

function A.on_context(row)
   if not row then return end
   local items = {}
   if row.kind == 'result' then
      table.insert(items, { title = 'Exact ' .. sym.DLIMP .. ' decimal', action = function() A.sheet:toggle(row) ui.update() end })
      table.insert(items, { title = 'Copy value', action = function() A.sheet:on_copy() end })
      table.insert(items, { title = 'Store to variable...', action = function() A.store_dialog() end })
      if A.host and A.host.push then
         table.insert(items, { title = 'Send to RPN stack', action = function() A.host.push(A.value_text(row)) end })
      end
   elseif row.kind == 'input' then
      table.insert(items, { title = 'Insert document function...', action = function() A.function_menu() end })
      table.insert(items, { title = 'Insert symbol...', action = function() A.symbol_menu() end })
      table.insert(items, { title = 'Clear field', action = function() A.sheet:on_clear() ui.update() end })
   else
      table.insert(items, { title = 'Copy line', action = function() A.sheet:on_copy() end })
   end
   if A.screen == 'problem' then
      table.insert(items, { title = 'Tag problem...', action = function() A.tag_dialog() end })
   end
   local f = A.sheet:frame()
   local y = f.y + (row._y or 0) - A.sheet.scroll_y + 10
   ui.menu.menu_at_point(A.sheet, items, ui.point(f.x + 30, math.max(f.y, y)))
end

-- History ---------------------------------------------------------------------------

function A.show_history()
   A.screen = 'history'
   local rows = {}
   local items = A.history.items
   local filt = A.filter:lower()
   for i = #items, 1, -1 do
      local p = items[i]
      local title = problem_title(p)
      local desc = summary(p)
      if filt == '' or (title .. ' ' .. desc):lower():find(filt, 1, true) then
         table.insert(rows, { kind = 'link', key = nil, title = '#' .. i .. ' ' .. title, desc = desc ~= '' and desc or '(empty)',
                              action = { 'open', i }, id = 'hist:' .. p.id })
      end
   end
   if #rows == 0 then
      table.insert(rows, { kind = 'note', text = filt ~= '' and ('No match for "' .. A.filter .. '"') or 'No problems yet', level = 'info' })
   end
   A.set_title('History' .. (A.filter ~= '' and ('  /' .. A.filter) or ''), #items .. ' problems')
   A.sheet:set_rows(rows, true)
   A.update_hint(A.sheet:selected())
end

-- Help -----------------------------------------------------------------------------

A.HELP = {
   { 'header', 'Using a solver' },
   { 'text', 'Type the values you know into the fields and press enter: everything that can be worked out is shown under Results, with the Working underneath (written the way VCE marking expects).' },
   { 'text', 'Leave unknowns empty. Events are typed like the question: `45<X<55`, X>k (unknown k), X' .. sym.GEQ .. '3, X>2|X' .. sym.GEQ .. '1 (conditional).' },
   { 'text', 'Use functions from other pages of the same problem, e.g. a(t) = f11(t) or u = f11(2). ctrl+menu on a field lists them.' },
   { 'header', 'Keys' },
   { 'text', 'up/down: move  ' .. sym.CDOT .. '  tab / shift+tab: next/previous field  ' .. sym.CDOT .. '  enter: solve and go to next field' },
   { 'text', 'On a result: enter or click switches exact ' .. sym.DLIMP .. ' decimal; left/right also switch or scroll long answers.' },
   { 'text', 'On results/working: n / p next or previous problem, t tag, h history, d all decimal, e all exact.' },
   { 'text', 'ctrl+C copies the selected value or working line. menu opens the toolbar menu (new problem, tag, settings). ctrl+menu opens the context menu.' },
   { 'header', 'Tips' },
   { 'text', 'Decimal places: menu > Settings. Answers are rounded only for display; values keep full precision.' },
   { 'text', 'Kinematics: pick what is given (a(t), a(v), a(x), v(t), v(x), v' .. sym.SQUARED .. '(x), x(t)), enter t0, x0, v0 (one known state) and optionally a second condition like x(2)=5. "Find when" accepts t=3, v=0, x=5 or a=0.' },
   { 'text', 'Run Self-test once on your calculator to check the solvers with its CAS.' },
}

function A.show_help()
   A.screen = 'help'
   A.set_title('Help', 'v' .. A.VERSION)
   local rows = {}
   for i, h in ipairs(A.HELP) do
      if h[1] == 'header' then
         table.insert(rows, { kind = 'header', text = h[2] })
      else
         table.insert(rows, { kind = 'step', text = h[2], key = 'help' .. i })
      end
   end
   A.sheet:set_rows(rows, false)
   A.update_hint(A.sheet:selected())
end

function A.show_selftest()
   A.screen = 'selftest'
   A.set_title('Self-test', 'running...')
   local rows = {}
   local passed = 0
   for i, c in ipairs(selftest.cases) do
      local ok, _, exact, err = selftest.run_case(c)
      if ok then passed = passed + 1 end
      local text = (ok and 'OK  ' or 'FAIL  ') .. c[1] .. ' ' .. c[3] .. ': '
      if err then
         text = text .. err
      else
         text = text .. '`' .. (exact and fmt.round_expr(exact, 6) or '?') .. '`  (want ' .. c[4] .. ')'
      end
      table.insert(rows, { kind = 'step', text = text, num = i, key = 'st' .. i })
   end
   table.insert(rows, 1, { kind = 'note', text = passed .. ' of ' .. #selftest.cases .. ' checks passed',
                           level = passed == #selftest.cases and 'info' or 'error' })
   A.set_title('Self-test', passed .. '/' .. #selftest.cases)
   A.sheet:set_rows(rows, false)
   A.update_hint(A.sheet:selected())
end

-- Settings ---------------------------------------------------------------------------

function A.set_dp(n)
   A.settings.dp = n
   fmt.dp = n
   A.redraw_current()
end

function A.set_font(name)
   A.settings.font = FONT_SIZES[name] or 10
   A.sheet:set_font(A.settings.font)
   mb.clear_cache()
   A.redraw_current()
end

function A.redraw_current()
   if A.screen == 'problem' then
      A.refresh_problem(true)
   elseif A.screen == 'home' then
      A.show_home()
   else
      A.sheet:invalidate_layout()
   end
end

-- Toolpalette menu --------------------------------------------------------------------

local function item(title, fn)
   return { title, function() A.safe(fn) end }
end

function A.menu()
   local solver_items = { 'Solvers' }
   for _, s in ipairs(solvers.list) do
      table.insert(solver_items, item(s.title, function() A.new_problem(s.id) end))
   end
   local m = {
      { 'Problem',
        item('Home', A.show_home),
        item('New (same type)', function()
           local p = A.current()
           if p then
              local _, idx = A.history:add(p.solver)
              A.show_problem(idx)
           end
        end),
        item('Duplicate', function()
           local p = A.current()
           if p then
              local inputs = {}
              for k, v in pairs(p.inputs) do inputs[k] = v end
              local _, idx = A.history:add(p.solver, inputs, p.tag)
              A.show_problem(idx)
           end
        end),
        item('Tag / label...', A.tag_dialog),
        item('Clear inputs', function()
           local p = A.current()
           if p and A.screen == 'problem' then
              p.inputs = {}
              A.refresh_problem(false)
           end
        end),
        item('Previous problem', function() A.go(-1) end),
        item('Next problem', function() A.go(1) end),
        item('Delete problem', function()
           local idx = A.history.current
           if idx and A.screen == 'problem' then
              A.history:remove(idx)
              A.show_home()
           end
        end),
      },
      solver_items,
      { 'History',
        item('Open history', A.show_history),
        item('Search (type in history)', function()
           A.filter = ''
           A.show_history()
        end),
      },
      { 'Result',
        item('Copy value / line', function() A.sheet:on_copy() end),
        item('Store value to variable...', A.store_dialog),
        item('Insert document function...', A.function_menu),
        item('Insert symbol...', A.symbol_menu),
        item('All exact', function() A.set_all_modes('exact') end),
        item('All decimal', function() A.set_all_modes('approx') end),
      },
      { 'Settings',
        item('2 decimal places', function() A.set_dp(2) end),
        item('3 decimal places', function() A.set_dp(3) end),
        item('4 decimal places', function() A.set_dp(4) end),
        item('5 decimal places', function() A.set_dp(5) end),
        item('6 decimal places', function() A.set_dp(6) end),
        item('Font small', function() A.set_font('small') end),
        item('Font normal', function() A.set_font('normal') end),
        item('Font large', function() A.set_font('large') end),
      },
      { 'Help',
        item('Help & keys', A.show_help),
        item('Self-test', A.show_selftest),
      },
   }
   if A.host and A.close then
      table.insert(m[1], item('Back to rpnspire', A.close))
   end
   return m
end

function A.register_menu()
   -- luacheck: ignore toolpalette
   if toolpalette and toolpalette.register then
      pcall(toolpalette.register, A.menu())
   end
end

-- Persistence --------------------------------------------------------------------------

function A.save_state()
   return {
      v = 1,
      history = A.history:save(),
      settings = { dp = A.settings.dp, font = A.settings.font, mode = A.settings.mode },
   }
end

function A.restore_state(state)
   if type(state) ~= 'table' then return end
   A.history = History.load(state.history)
   local s = state.settings
   if type(s) == 'table' then
      A.settings.dp = tonumber(s.dp) or A.settings.dp
      A.settings.font = tonumber(s.font) or A.settings.font
      if s.mode == 'approx' or s.mode == 'exact' then A.settings.mode = s.mode end
   end
   fmt.dp = A.settings.dp
   if A.sheet then
      A.sheet:set_font(A.settings.font)
      A.show_home()
   end
end

-- Open ----------------------------------------------------------------------------------

-- Open the toolkit. host (optional, when started inside rpnspire):
--   { push = function(value) ... end }  -- send a value to the RPN stack
function A.open(host)
   cas.init()
   mb.rename = cas.display_name
   fmt.dp = A.settings.dp
   A.host = host
   local root = A.root or A.build()
   local session = ui.push_modal(root)
   A.session = session
   if host then
      A.close = function()
         if toolpalette and toolpalette.register then pcall(toolpalette.register, nil) end
         ui.pop_modal(session)
         A.root = nil
         if host.on_close then host.on_close() end
      end
   end
   ui.set_focus(A.sheet)
   A.register_menu()
   A.show_home()
   return root
end

return A
