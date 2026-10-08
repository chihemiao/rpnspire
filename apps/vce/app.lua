-- VCE Maths toolkit (Methods + Specialist): screens, navigation, history and menus
local class = require 'class'
local ui = require 'ui'
require 'views.container'
require 'views.label'
require 'views.edit'
require 'views.list'
require 'views.menu'
require 'views.sheet'
require 'views.graphview'
local mb = require 'ui.mathbox'
local cas = require 'apps.vce.cas'
local fmt = require 'apps.vce.fmt'
local report = require 'apps.vce.report'
local solvers = require 'apps.vce.registry'
local History = require 'apps.vce.history'
local selftest = require 'apps.vce.selftest'
local i18n = require 'apps.vce.i18n'
local sym = require 'ti.sym'

local T = i18n.t

local A = {}

A.VERSION = '2.0'
A.settings = { dp = 4, font = 10, mode = 'exact', lang = nil, colors = 'comfort' }
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
         I[f.id] = v or (not f.pick and f.options[1][1]) or nil
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
   local I = inputs_for(s, p)
   for _, f in ipairs(s.fields) do
      local v = p.inputs[f.id]
      if s.is_group and f.id == 'type' then v = nil end
      if v and trim(v) ~= '' and #parts < 4 and (not f.show or f.show(I)) then
         local label = type(f.label) == 'function' and f.label(inputs_for(s, p)) or f.label
         label = report.plain(label):gsub('%s*=$', '')
         table.insert(parts, label .. '=' .. v)
      end
   end
   return table.concat(parts, ', ')
end

local function problem_title(p)
   local s = solvers.get(p.solver)
   local t = p.solver
   if s then
      local _, short = i18n.solver(s)
      t = short
      local m = s.member and s.member(p.inputs)
      if m then
         local _, mshort = i18n.solver(m)
         t = t .. ' ' .. sym.CDOT .. ' ' .. mshort
      end
   end
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
   if row.prose then return e end
   if row.pair and row.mode == 'approx' then
      local function r(v)
         local n = cas.n(v)
         return n and fmt.round(n, A.settings.dp) or fmt.round_expr(v, A.settings.dp)
      end
      return 'pt(' .. r(row.pair[1]) .. ',' .. r(row.pair[2]) .. ')'
   end
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
   sheet.input_display = function(_, row, text)
      -- fields that read 'kx' as k*x show it that way
      local f = A.screen == 'problem' and A.field_of(row)
      if f and f.implicit then
         return cas.input(text, require('apps.vce.solvers.util').locals_map(), false, true) or text
      end
      return cas.input(text) or text
   end
   sheet.copy_text = function(_, row)
      if row.kind == 'result' and row.prose then return report.plain(row.label .. ' ' .. row.exact) end
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
   sheet.on_detail = function(_, row) A.safe(A.show_detail, row) end
   sheet.on_pick = function(_, row) A.safe(A.pick_dialog, row) end
   sheet.on_toggle = function(_, row) A.safe(A.on_toggle, row) end
   sheet.on_escape_cb = function() A.safe(A.on_escape) end
   sheet.on_context = function(_, row) A.safe(A.on_context, row) end
   sheet.on_delete = function(_, row) A.safe(A.on_delete, row) end
   sheet.on_shortcut = function(_, c) return A.on_shortcut(c) end
   sheet.on_help_cb = function() A.show_help() end
   return root
end

-- Solver field of an input row in the current problem
function A.field_of(row)
   local p = A.current()
   local s = p and solvers.get(p.solver)
   for _, f in ipairs(s and s.fields or {}) do
      if f.id == row.id then return f end
   end
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
   -- the error dialog has one line: show the Chinese text in bilingual mode
   if i18n.bi() then
      local zh = i18n.UI[msg] or (i18n.note(msg) or ''):match('\n(.*)$')
      if zh then msg = zh end
   end
   dlg.display(T('Error'), msg)
end

function A.set_title(left, right)
   A.title.left = left or ''
   A.title.right = right or ''
end

local DOT = '  ' .. sym.CDOT .. '  '
local HINTS = {
   input = 'type here' .. DOT .. 'enter: next box' .. DOT .. 'esc: back',
   choice = 'left/right: change' .. DOT .. 'enter: choose',
   result = 'enter: exact ' .. sym.DLIMP .. ' decimal' .. DOT .. 'ctrl+C: copy',
   step = 'up/down: read the working' .. DOT .. 'esc: back',
   link = 'enter: open' .. DOT .. 'or press its number',
   math = 'left/right: scroll',
   graph = 'enter: full screen',
   formula = 'enter: working for this formula' .. DOT .. 'left/right: exact ' .. sym.DLIMP .. ' decimal',
   detail = 'esc: back to the problem' .. DOT .. 'enter: exact ' .. sym.DLIMP .. ' decimal',
   example = 'enter: fill in a sample question',
   prose = 'up/down: read' .. DOT .. 'ctrl+C: copy',
   pick = 'enter: choose' .. DOT .. 'or press its number',
   settings = 'left/right: change' .. DOT .. 'esc: home',
}

function A.update_hint(row)
   if A.screen == 'history' then
      A.hint.left = i18n.hint('history', 'enter: open' .. DOT .. 'type: search' .. DOT .. 'del: delete' .. DOT .. 'esc: home')
   elseif A.screen == 'detail' then
      A.hint.left = i18n.hint('detail', HINTS.detail)
   elseif A.screen == 'settings' and row and row.kind == 'choice' then
      A.hint.left = i18n.hint('settings', HINTS.settings)
   elseif row and row.hkind and HINTS[row.hkind] then
      A.hint.left = i18n.hint(row.hkind, HINTS[row.hkind])
   elseif row and row.kind == 'result' and row.prose then
      A.hint.left = i18n.hint('prose', HINTS.prose)
   elseif row and row.kind == 'result' and row.detail then
      A.hint.left = i18n.hint('formula', HINTS.formula)
   elseif row and HINTS[row.kind] then
      A.hint.left = i18n.hint(row.kind, HINTS[row.kind])
   else
      A.hint.left = i18n.hint('default', 'menu: more options' .. DOT .. 'esc: back')
   end
end

-- Home ------------------------------------------------------------------------------

local GROUP_TITLES = { Functions = 'Functions & graphs', Probability = 'Probability & statistics' }

function A.show_home()
   A.screen = 'home'
   if i18n.bi() then
      A.set_title('VCE ' .. i18n.UI['VCE Maths toolkit'] .. ' ' .. sym.CDOT .. ' Tech Active', 'MM + SM')
   else
      A.set_title('VCE Maths ' .. sym.CDOT .. ' Tech Active', 'MM + SM')
   end
   local rows = {}
   -- badge legend (Chinese only in bilingual mode: the badge already says MM / SM)
   table.insert(rows, { kind = 'legend', items = { { 'MM', i18n.z('Maths Methods') }, { 'SM', i18n.z('Specialist Maths') } } })
   local group
   for i, s in ipairs(solvers.home) do
      if s.group ~= group then
         group = s.group
         table.insert(rows, { kind = 'header', text = T(GROUP_TITLES[group] or group) })
      end
      local title, _, desc = i18n.solver(s)
      table.insert(rows, { kind = 'link', key = i <= 10 and tostring(i % 10) or nil, title = title,
                           desc = i18n.blurb(s) or desc,
                           badges = solvers.badges(s), action = { 'new', s.id }, id = 'solver:' .. s.id })
   end
   local items = A.history.items
   if #items > 0 then
      table.insert(rows, { kind = 'header', text = T('Recent') })
      for i = #items, math.max(1, #items - 2), -1 do
         local p = items[i]
         table.insert(rows, { kind = 'link', title = problem_title(p), desc = summary(p),
                              action = { 'open', i }, id = 'recent:' .. p.id })
      end
   end
   table.insert(rows, { kind = 'header', text = T('More') })
   table.insert(rows, { kind = 'link', title = T('History') .. ' (' .. #items .. ')', desc = T('all problems, tags, search'),
                        action = { 'history' }, id = 'history' })
   local set_desc = i18n.has_zh and 'decimal places, text size, colours, language' or 'decimal places, text size, colours'
   table.insert(rows, { kind = 'link', title = T('Settings'), desc = T(set_desc), action = { 'settings' }, id = 'settings' })
   table.insert(rows, { kind = 'link', title = T('Help & keys'), desc = T('how to use this in 3 steps'),
                        action = { 'help' }, id = 'help' })
   table.insert(rows, { kind = 'link', title = T('Self-test'), desc = T('check the solvers with this calculator\'s CAS'),
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

-- A result that is a formula (uses t, x, v, ...) rather than a number
local function is_formula(e)
   local _, ids = cas.identifiers(e or '')
   for _, id in ipairs(ids) do
      if id:match('^q[79]%a$') then return true end
   end
   return false
end

-- Solver that owns a field (group members keep their own translations)
local function field_owner(s, f)
   return f.owner or s.id, { id = f.base or f.id }
end

-- Example inputs of a problem's solver (nil if none)
local function example_of(s, p)
   if s.is_group then
      local m = s.member(p.inputs)
      return m and s.example_for(m.id)
   end
   return s.example
end

-- True when the user has not typed anything yet (a group's type does not count)
local function no_inputs(s, p)
   for k, v in pairs(p.inputs) do
      if not (s.is_group and k == 'type') and trim(v) ~= '' then return false end
   end
   return true
end

function A.build_problem_rows(p, R, I)
   local s = solvers.get(p.solver)
   local rows = {}
   local title = i18n.solver(s)
   table.insert(rows, { kind = 'header', text = title })

   -- a group without a type: choose one from a list first
   if s.is_group and not I.type then
      table.insert(rows, { kind = 'note', level = 'info', key = 'pick-note',
                           text = i18n.note('Step 1: choose the kind of question') })
      for i, m in ipairs(s.members) do
         local mt, _, mdesc = i18n.solver(m)
         table.insert(rows, { kind = 'link', key = i <= 10 and tostring(i % 10) or nil, title = mt, desc = mdesc,
                              badges = solvers.badges(m), action = { 'pick', 'type', m.id }, id = 'pick:' .. m.id,
                              hkind = 'pick' })
      end
      return rows
   end

   for _, f in ipairs(s.fields) do
      if not f.show or f.show(I) then
         local label = type(f.label) == 'function' and f.label(I) or f.label
         local hint
         local owner, fid = field_owner(s, f)
         label, hint = i18n.field(owner, fid, label, f.hint)
         if f.kind == 'choice' then
            local cur = p.inputs[f.id] or f.options[1][1]
            local idx = 1
            local options = {}
            for k, o in ipairs(f.options) do
               if o[1] == cur then idx = k end
               local text, full
               if s.is_group and f.id == 'type' then
                  local m = s.by_member[o[1]]
                  local mt, ms = i18n.solver(m)
                  text, full = ms, mt .. '  (' .. (m.course or '') .. ')'
               else
                  text = i18n.option(owner, fid.id, o[1], o[2] or o[1])
               end
               options[k] = { o[1], text, full }
            end
            table.insert(rows, { kind = 'choice', id = f.id, label = label, options = options, index = idx })
         else
            table.insert(rows, { kind = 'input', id = f.id, label = label, text = p.inputs[f.id] or '', hint = hint })
         end
      end
   end
   if no_inputs(s, p) and example_of(s, p) then
      table.insert(rows, { kind = 'link', title = T('Try an example'), desc = T('fills in a sample question so you can see how it works'),
                           action = { 'example' }, id = 'example', hkind = 'example' })
   end
   if R.display then
      table.insert(rows, { kind = 'math', m = R.display, key = 'display' })
   end
   for i, n in ipairs(R.notes) do
      table.insert(rows, { kind = 'note', text = i18n.note(n.text), level = n.kind, key = 'note' .. i })
   end
   if #R.notes == 0 and #R.results == 0 then
      table.insert(rows, { kind = 'note', level = 'info', key = 'note-wait',
                           text = i18n.note('Answers appear here as soon as there is enough information') })
   end
   if R.graph then
      table.insert(rows, { kind = 'header', text = T('Graph') .. '  (' .. T('enter: full screen') .. ')' })
      table.insert(rows, { kind = 'graph', spec = R.graph, labels = R.graph_labels, key = 'graph' })
   end
   p.modes = p.modes or {}
   local tsid = s.member and (s.member(I) or {}).id or s.id
   if #R.results > 0 then
      table.insert(rows, { kind = 'header', text = T('Answers'), style = 'answers' })
      local seen = {}
      for _, r in ipairs(R.results) do
         local key = 'res:' .. (r.key or r.label)
         seen[key] = (seen[key] or 0) + 1
         if seen[key] > 1 then key = key .. ':' .. seen[key] end
         table.insert(rows, { kind = 'result', key = key, label = r.label, exact = r.exact, pair = r.pair,
                              prose = r.text, mode = p.modes[key] or A.settings.mode, term = i18n.term(tsid, r.key),
                              rkey = r.key, caption = r.domain and (T('domain') .. ': `' .. r.domain .. '`'),
                              detail = is_formula(r.exact) and R:steps_for(r.key) ~= nil })
      end
   end
   if #R.steps > 0 then
      table.insert(rows, { kind = 'header', text = T('Working') })
      local n = 0
      for i, st in ipairs(R.steps) do
         if st.section then
            table.insert(rows, { kind = 'step', text = i18n.section(st.text), section = true, key = 'step' .. i })
         else
            n = n + 1
            table.insert(rows, { kind = 'step', text = st.text, num = n, key = 'step' .. i })
         end
      end
   end
   return rows
end

-- Solving is cached per problem. The key holds every input that changes the
-- maths; inputs a solver lists in `view_fields` (graph window, show/hide
-- options) only change the picture and are applied by `s.view` to a copy, so
-- moving through fields or toggling an option does not solve again.
local function solve_key(s, I)
   local parts = { s.id, tostring(A.settings.dp) }
   for _, f in ipairs(s.fields) do
      if not (s.view_fields and s.view_fields[f.id]) then
         table.insert(parts, f.id .. '=' .. tostring(I[f.id] or ''))
      end
   end
   return table.concat(parts, '\1')
end

local function copy_report(R)
   local C = report.new()
   for k, v in pairs(R) do C[k] = v end
   C.results, C.steps, C.notes = {}, {}, {}
   for i, v in ipairs(R.results) do C.results[i] = v end
   for i, v in ipairs(R.steps) do C.steps[i] = v end
   for i, v in ipairs(R.notes) do C.notes[i] = v end
   if R.graph then
      local g = {}
      for k, v in pairs(R.graph) do g[k] = v end
      g._plot_cache = nil
      C.graph = g
   end
   return C
end

function A.solve(p)
   local s = solvers.get(p.solver)
   local I = inputs_for(s, p)
   fmt.dp = A.settings.dp
   local key = solve_key(s, I)
   local c = p._cache
   if not (c and c.key == key) then
      local R = report.new()
      local ok, err = pcall(s.solve, I, R)
      if not ok then
         R:note('Error: ' .. errmsg(err), 'error')
      end
      c = { key = key, R = R }
      p._cache = c
   end
   local R = copy_report(c.R)
   if s.view then pcall(s.view, I, R) end
   return R, I
end

-- Forget cached results (document functions such as f11 may have changed)
function A.invalidate()
   cas.clear_memo()
   for _, p in ipairs(A.history and A.history.items or {}) do p._cache = nil end
end

-- True if a problem's inputs refer to the document (f11(t), stored values)
function A.uses_document(p)
   local s = solvers.get(p.solver)
   local map = require('apps.vce.solvers.util').locals_map()
   for _, f in ipairs(s and s.fields or {}) do
      local v = f.kind ~= 'choice' and p.inputs[f.id]
      local e = v and cas.input(v, map)
      if e and not cas.pure(e) then return true end
   end
   return false
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
   local s = solvers.get(p.solver)
   local m = s and s.member and s.member(p.inputs)
   local course = (m or s or {}).course or ''
   A.set_title(problem_title(p), course .. '  ' .. tostring(A.history.current) .. '/' .. tostring(#A.history.items))
end

function A.show_problem(idx)
   A.screen = 'problem'
   A.history.current = idx
   A.refresh_problem(false)
end

function A.on_commit(row)
   if A.screen ~= 'problem' then return end
   local p = A.current()
   if (p.inputs[row.id] or '') == (row.text or '') then return end
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
   -- no answer: show the note that says what is missing
   for k = (sh.sel or 0) + 1, #sh.rows do
      if sh.rows[k].kind == 'note' then
         sh:reveal(k)
         return
      end
   end
end

function A.on_choice(row)
   if A.screen == 'settings' then return A.apply_setting(row) end
   if A.screen ~= 'problem' then return end
   local p = A.current()
   p.inputs[row.id] = row.options[row.index][1]
   A.refresh_problem(true)
end

-- Choice with many options: pick from a list
function A.pick_dialog(row)
   local items = {}
   for k, o in ipairs(row.options) do
      table.insert(items, { title = k .. '  ' .. report.plain(o[3] or o[2] or o[1]), result = k })
   end
   local dlg = require('dialog.list').display({ title = report.plain(row.label or ''), items = items,
                                                selection = row.index or 1 })
   dlg.on_done = function(item)
      if item and item.result then
         row.index = item.result
         row._lay = nil
         A.safe(A.on_choice, row)
      end
   end
end

-- Fill in the solver's example (a sample question)
function A.fill_example()
   local p = A.current()
   local s = p and solvers.get(p.solver)
   local ex = s and example_of(s, p)
   if not ex then return end
   for k, v in pairs(ex) do p.inputs[k] = v end
   A.refresh_problem(false)
   A.focus_answers()
end

-- Select the first answer and scroll so the Answers heading is at the top
function A.focus_answers()
   local sh = A.sheet
   for i, r in ipairs(sh.rows) do
      if r.kind == 'result' then
         sh:select(i)
         sh:with_layout(function()
            local top = sh.rows[i - 1] and sh.rows[i - 1]._y or r._y
            local maxs = math.max(0, (sh.content_h or 0) - sh:frame().height)
            sh.scroll_y = math.max(0, math.min(top, maxs))
         end)
         break
      end
   end
   A.update_hint(sh:selected())
end

function A.on_toggle(row)
   local p = A.current()
   if (A.screen == 'problem' or A.screen == 'detail') and p and row.key then
      p.modes = p.modes or {}
      p.modes[row.key] = row.mode
   end
end

function A.open_graph(row)
   local hint = i18n.bi() and i18n.HINTS.graphview or nil
   ui.graphview.open(row.spec, { hint = hint, labels = row.labels }, function()
      ui.set_focus(A.sheet)
      ui.update()
   end)
end

function A.on_activate(row)
   if row.kind == 'graph' then
      return A.open_graph(row)
   end
   local a = row.action
   if not a then return end
   if a[1] == 'new' then
      A.new_problem(a[2])
   elseif a[1] == 'pick' then
      local p = A.current()
      p.inputs[a[2]] = a[3]
      A.refresh_problem(false)
   elseif a[1] == 'example' then
      A.fill_example()
   elseif a[1] == 'settings' then
      A.show_settings()
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

-- Working for one formula only (enter on a formula result)
function A.show_detail(row)
   local R = A.last_report
   local steps = R and R:steps_for(row.rkey)
   if not steps then return end
   A.screen = 'detail'
   A.detail_key = row.key
   local rows = {}
   table.insert(rows, { kind = 'header', text = T('Working for') .. ' ' .. (row.label or '') })
   table.insert(rows, { kind = 'result', key = row.key, label = row.label, exact = row.exact, pair = row.pair,
                        mode = row.mode, term = row.term, rkey = row.rkey, caption = row.caption })
   table.insert(rows, { kind = 'header', text = T('Working') })
   local n = 0
   for i, st in ipairs(steps) do
      if st.section then
         table.insert(rows, { kind = 'step', text = i18n.section(st.text), section = true, key = 'dstep' .. i })
      else
         n = n + 1
         table.insert(rows, { kind = 'step', text = st.text, num = n, key = 'dstep' .. i })
      end
   end
   A.sheet:set_rows(rows, true)
   local p = A.current()
   A.set_title(problem_title(p), T('esc: back'))
   A.update_hint(A.sheet:selected())
end

function A.on_escape()
   if A.screen == 'detail' then
      -- back to the problem with the same formula selected
      A.screen = 'problem'
      A.refresh_problem(true)
      for i, r in ipairs(A.sheet.rows) do
         if r.key == A.detail_key then
            A.sheet:select(i)
            A.update_hint(r)
            break
         end
      end
      return
   end
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
         local s = solvers.home[idx]
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
   elseif A.screen == 'problem' or A.screen == 'detail' then
      -- digits choose from a list shown in the problem (kind of question)
      if tonumber(c) then
         for _, r in ipairs(A.sheet.rows) do
            if r.kind == 'link' and r.key == c and r.action then
               A.safe(A.on_activate, r)
               return true
            end
         end
      end
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
         A.confirm(T('Delete') .. ' ' .. row.title .. '?', function()
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
   if A.screen == 'problem' then
      A.refresh_problem(true)
   elseif A.screen == 'detail' then
      A.refresh_detail()
   end
end

-- Rebuild the formula working screen (after a settings change)
function A.refresh_detail()
   local cur = A.sheet.rows[2]
   local key = cur and cur.key
   A.screen = 'problem'
   A.refresh_problem(true)
   for _, r in ipairs(A.sheet.rows) do
      if r.key == key and r.detail then return A.show_detail(r) end
   end
end

-- Dialogs ---------------------------------------------------------------------------

function A.confirm(title, yes)
   local dlg = require('dialog.list').display({
      title = title,
      items = { { title = T('Yes'), result = true }, { title = T('No'), result = false } },
   })
   dlg.on_done = function(row)
      if row and row.result then A.safe(yes) end
   end
end

function A.tag_dialog()
   local p = A.current()
   if not p then return end
   local title = 'Tag / label (e.g. 2023 E2 Q5b)'
   if i18n.bi() then title = 'Tag ' .. i18n.z(title) end
   local dlg = require('dialog.input').display({ title = title, text = p.tag or '' })
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
   local dlg = require('dialog.input').display({ title = 'Store ' .. fmt.plain(A.value_text(row)) .. ' ' .. T('to variable') })
   dlg.on_done = function(name)
      name = trim(name)
      if name == '' then return end
      local value = row.mode == 'approx' and A.value_text(row) or row.exact
      local res, err = cas.eval(cas.p(value) .. sym.STORE .. name)
      if not res then A.error(T('Could not store') .. ' (' .. tostring(err) .. ')') end
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
      { sym.LEQ, 'less or equal' }, { sym.GEQ, 'greater or equal' },
      { sym.NEQ, 'not equal' }, { sym.INFTY, 'infinity' }, { sym.pi, 'pi' },
      { sym.ROOT .. '(', 'square root' }, { sym.EULER .. '^(', 'e^' },
      { 'ln(', 'natural log' }, { '|', 'given (conditional)' },
      { 'integral(', 'integral(f,x,a,b)' }, { 'abs(', 'absolute value' },
   }
   local items = {}
   for _, s in ipairs(syms) do
      local title = s[1] .. '   ' .. T(s[2])
      table.insert(items, { title = title, action = function() A.insert(s[1]) end })
   end
   ui.menu.menu_at_point(A.sheet, items, ui.point(20, 40))
end

function A.on_context(row)
   if not row then return end
   local items = {}
   if row.kind == 'result' then
      table.insert(items, { title = T('Exact ' .. sym.DLIMP .. ' decimal'), action = function() A.sheet:toggle(row) ui.update() end })
      table.insert(items, { title = T('Copy value'), action = function() A.sheet:on_copy() end })
      table.insert(items, { title = T('Store to variable...'), action = function() A.store_dialog() end })
      if A.host and A.host.push then
         table.insert(items, { title = T('Send to RPN stack'), action = function() A.host.push(A.value_text(row)) end })
      end
   elseif row.kind == 'input' then
      table.insert(items, { title = T('Insert document function...'), action = function() A.function_menu() end })
      table.insert(items, { title = T('Insert symbol...'), action = function() A.symbol_menu() end })
      table.insert(items, { title = T('Clear field'), action = function() A.sheet:on_clear() ui.update() end })
   else
      table.insert(items, { title = T('Copy line'), action = function() A.sheet:on_copy() end })
   end
   if A.screen == 'problem' then
      table.insert(items, { title = T('Tag problem...'), action = function() A.tag_dialog() end })
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
         table.insert(rows, { kind = 'link', key = nil, title = '#' .. i .. ' ' .. title, desc = desc ~= '' and desc or T('(empty)'),
                              action = { 'open', i }, id = 'hist:' .. p.id })
      end
   end
   if #rows == 0 then
      local nomatch = 'No match for "' .. A.filter .. '"' .. (i18n.bi() and ('\n' .. i18n.z('No match')) or '')
      table.insert(rows, { kind = 'note', text = filt ~= '' and nomatch or T('No problems yet', '\n'), level = 'info' })
   end
   local count = i18n.bi() and (#items .. ' ' .. i18n.UI['problems']) or (#items .. ' problems')
   A.set_title(T('History') .. (A.filter ~= '' and ('  /' .. A.filter) or ''), count)
   A.sheet:set_rows(rows, true)
   A.update_hint(A.sheet:selected())
end

-- Help -----------------------------------------------------------------------------

function A.show_help()
   A.screen = 'help'
   A.set_title(T('Help'), 'v' .. A.VERSION)
   local rows = {}
   for i, h in ipairs(i18n.help()) do
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
   A.set_title(T('Self-test'), T('running...'))
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
   local summary_text = passed .. ' of ' .. #selftest.cases .. ' checks passed'
   if i18n.bi() then
      summary_text = summary_text .. '\n' .. passed .. '/' .. #selftest.cases .. ' ' .. i18n.UI['checks passed']
   end
   table.insert(rows, 1, { kind = 'note', text = summary_text,
                           level = passed == #selftest.cases and 'info' or 'error' })
   A.set_title(T('Self-test'), passed .. '/' .. #selftest.cases)
   A.sheet:set_rows(rows, false)
   A.update_hint(A.sheet:selected())
end

-- Settings ---------------------------------------------------------------------------

local SETTINGS = {
   { id = 'dp', label = 'Decimal places', options = { { 2, '2' }, { 3, '3' }, { 4, '4' }, { 5, '5' }, { 6, '6' } } },
   { id = 'mode', label = 'Answers start as', options = { { 'exact', 'exact' }, { 'approx', 'decimal' } } },
   { id = 'font', label = 'Text size', options = { { 'small', 'small' }, { 'normal', 'normal' }, { 'large', 'large' } } },
   { id = 'colors', label = 'Colours', options = { { 'comfort', 'soft cream' }, { 'plain', 'plain white' } } },
   { id = 'lang', label = 'Language', options = { { 'en', 'English' }, { 'bi', 'Chinese + English' } } },
}

local function setting_value(id)
   if id == 'font' then
      for name, size in pairs(FONT_SIZES) do
         if size == A.settings.font then return name end
      end
      return 'normal'
   elseif id == 'lang' then
      return i18n.lang
   end
   return A.settings[id]
end

-- Settings as a screen of choices (also in menu > Settings)
function A.show_settings()
   A.screen = 'settings'
   A.set_title(T('Settings'), T('esc: back'))
   local rows = { { kind = 'header', text = T('Settings') } }
   for _, st in ipairs(SETTINGS) do
      -- the English-only documents have no language to choose
      if st.id ~= 'lang' or i18n.has_zh then
         local cur = setting_value(st.id)
         local idx, options = 1, {}
         for k, o in ipairs(st.options) do
            if o[1] == cur then idx = k end
            options[k] = { o[1], T(o[2]) }
         end
         table.insert(rows, { kind = 'choice', id = st.id, label = T(st.label), options = options, index = idx })
      end
   end
   table.insert(rows, { kind = 'note', level = 'info', key = 'set-note',
                        text = i18n.note('Changes apply at once and are saved with the document') })
   A.sheet:set_rows(rows, true)
   A.update_hint(A.sheet:selected())
end

function A.apply_setting(row)
   local v = row.options[row.index][1]
   if row.id == 'dp' then
      A.settings.dp = v
      fmt.dp = v
   elseif row.id == 'mode' then
      A.settings.mode = v
   elseif row.id == 'font' then
      A.settings.font = FONT_SIZES[v] or 10
      A.sheet:set_font(A.settings.font)
      mb.clear_cache()
   elseif row.id == 'colors' then
      A.set_colors(v)
   elseif row.id == 'lang' then
      A.settings.lang = i18n.set(v)
      A.register_menu()
      A.sheet:invalidate_layout()
   end
   A.show_settings()
end

function A.set_colors(name)
   A.settings.colors = name
   ui.sheet.set_palette(name)
end

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

function A.set_lang(lang)
   A.settings.lang = i18n.set(lang)
   A.register_menu()
   A.sheet:invalidate_layout()
   if A.screen == 'history' then
      A.show_history()
   elseif A.screen == 'help' then
      A.show_help()
   elseif A.screen == 'selftest' then
      A.show_home()
   elseif A.screen == 'settings' then
      A.show_settings()
   else
      A.redraw_current()
   end
end

function A.redraw_current()
   if A.screen == 'problem' then
      A.refresh_problem(true)
   elseif A.screen == 'detail' then
      A.refresh_detail()
   elseif A.screen == 'home' then
      A.show_home()
   else
      A.sheet:invalidate_layout()
   end
end

-- Toolpalette menu --------------------------------------------------------------------

local function item(title, fn)
   return { T(title), function() A.safe(fn) end }
end

local function dp_item(n)
   local title = n .. ' decimal places'
   if i18n.bi() then title = title .. ' ' .. n .. ' ' .. i18n.UI['decimal places'] end
   return { title, function() A.safe(A.set_dp, n) end }
end

function A.menu()
   local solver_items = { T('Solvers') }
   for _, s in ipairs(solvers.home) do
      local title = i18n.solver(s)
      table.insert(solver_items, { title, function() A.safe(A.new_problem, s.id) end })
   end
   local settings_items = {
      T('Settings'),
      item('All settings...', A.show_settings),
      dp_item(2), dp_item(3), dp_item(4), dp_item(5), dp_item(6),
      item('Font small', function() A.set_font('small') end),
      item('Font normal', function() A.set_font('normal') end),
      item('Font large', function() A.set_font('large') end),
   }
   if i18n.has_zh then
      table.insert(settings_items, item('Language: English', function() A.set_lang('en') end))
      table.insert(settings_items, item('Language: Chinese + English', function() A.set_lang('bi') end))
   end
   table.insert(settings_items, item('Colours: soft cream', function() A.set_colors('comfort') A.redraw_current() end))
   table.insert(settings_items, item('Colours: plain white', function() A.set_colors('plain') A.redraw_current() end))
   local m = {
      { T('Problem'),
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
      { T('History'),
        item('Open history', A.show_history),
        item('Search (type in history)', function()
           A.filter = ''
           A.show_history()
        end),
      },
      { T('Result'),
        item('Copy value / line', function() A.sheet:on_copy() end),
        item('Store value to variable...', A.store_dialog),
        item('Insert document function...', A.function_menu),
        item('Try an example', A.fill_example),
        item('Insert symbol...', A.symbol_menu),
        item('All exact', function() A.set_all_modes('exact') end),
        item('All decimal', function() A.set_all_modes('approx') end),
      },
      settings_items,
      { T('Help'),
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
      settings = { dp = A.settings.dp, font = A.settings.font, mode = A.settings.mode, lang = A.settings.lang,
                   colors = A.settings.colors },
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
      if s.lang == 'en' or s.lang == 'bi' then A.settings.lang = i18n.set(s.lang) end
      if s.colors == 'comfort' or s.colors == 'plain' then A.set_colors(s.colors) end
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
   A.invalidate()
   i18n.set(A.settings.lang or i18n.default)
   mb.rename = cas.display_name
   fmt.dp = A.settings.dp
   ui.sheet.set_palette(A.settings.colors)
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
