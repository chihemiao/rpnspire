-- Unknown constants from conditions:
--   f(x) = a*x^3+b*x^2+c with f(1)=3, f'(2)=0, (0,1), tp(1,2), tangent y=2x+1 at x=1
-- Each condition becomes an equation; the equations are solved together.
local cas = require 'apps.vce.cas'
local U = require 'apps.vce.solvers.util'
local numeric = require 'apps.vce.numeric'

local M = U.M
local MAP = U.locals_map()
local NCOND = 6
local max, min, abs = math.max, math.min, math.abs

local HINTS = {
   "f(1)=3", "f'(2)=0", '(2,5)  = passes through', 'tp(1,2)  = turning point',
   'tangent y=2x+1 at x=1', 'asymptote x=2  or  y=3',
}

-- 'f(x)=...', 'y=...' or just the rule -> name, variable letter, rule text
local function split_rule(text)
   text = U.trim(text)
   local name, var, body = text:match('^(%a)%s*%(%s*(%a)%s*%)%s*=(.*)$')
   if name then return name, var:lower(), body end
   body = text:match('^[yY]%s*=(.*)$')
   if body then return 'y', 'x', body end
   return 'f', 'x', text
end

local function read_rule(text)
   local name, var, body = split_rule(text)
   local src = cas.input(body, MAP, false, true)
   return name, var, src, MAP[var] or 'q9x'
end

-- Unknown constants (local symbols other than the variable), sorted a, b, c
local function params_of(exprs, X)
   local set, list = {}, {}
   for _, e in ipairs(exprs) do
      for _, u in ipairs(U.unknowns(e)) do
         if u ~= X and not set[u] then
            set[u] = true
            table.insert(list, u)
         end
      end
   end
   table.sort(list)
   return list
end

local function count_params(I)
   if not I.f then return 0 end
   local ok, n = pcall(function()
      local _, _, src, X = read_rule(I.f)
      return #params_of({ src }, X)
   end)
   return ok and n or 0
end

local function cond_field(i)
   return {
      id = 'c' .. i, label = 'Condition ' .. i, hint = HINTS[i],
      show = i > 1 and function(I)
         return i <= count_params(I) or I['c' .. (i - 1)] ~= nil
      end or nil,
   }
end

local S = {
   id = 'params',
   title = 'Find unknown constants',
   short = 'Unknowns a, b, c',
   group = 'Functions',
   course = 'MM SM',
   desc = "f(x) with a, b, c and conditions like f(1)=3, f'(2)=0, (2,5)",
   fields = { { id = 'f', label = 'f(x) =', hint = 'a*x^3+b*x^2+c   a/(x-b)+c', implicit = true } },
   example = { f = 'a*x^3+b*x^2+c', c1 = 'f(1)=3', c2 = "f'(2)=0", c3 = '(0,1)' },
}
for i = 1, NCOND do table.insert(S.fields, cond_field(i)) end

-- Find the matching ')' for the '(' at position i
local function close_paren(s, i)
   local depth = 0
   for j = i, #s do
      local c = s:sub(j, j)
      if c == '(' then depth = depth + 1 elseif c == ')' then
         depth = depth - 1
         if depth == 0 then return j end
      end
   end
end

-- Builder for the values of f, f', f'' at a point
local function maker(src, X)
   local F = {}
   function F.at(a)
      return '(' .. cas.rename(src, { [X] = '(' .. a .. ')' }, true) .. ')'
   end
   function F.d(a, k)
      return '(derivative(' .. src .. ',' .. X .. (k == 2 and ',2' or '') .. ')|' .. X .. '=' .. U.par(a) .. ')'
   end
   return F
end

-- Replace calls name(a), name'(a), name''(a) in a raw condition with values
-- and normalize the rest. Returns the CAS text.
local function expand(raw, name, F)
   local holders, n = {}, 0
   local out, i = {}, 1
   while i <= #raw do
      local c = raw:sub(i, i)
      local prev = i > 1 and raw:sub(i - 1, i - 1) or ''
      if c == name and not prev:match('[%w_]') then
         local j = i + 1
         local primes = 0
         while raw:sub(j, j) == "'" do primes = primes + 1 j = j + 1 end
         if raw:sub(j, j) == '(' then
            local e = close_paren(raw, j)
            if not e then error({ desc = 'Missing ) in condition' }) end
            local arg = cas.input(raw:sub(j + 1, e - 1), MAP, false, true)
            if not arg then error({ desc = 'Missing value in ' .. raw:sub(i, e) }) end
            n = n + 1
            local key = 'q8' .. string.char(96 + n)
            holders[key] = primes == 0 and F.at(arg) or F.d(arg, primes)
            table.insert(out, '(' .. key .. ')')
            i = e + 1
         else
            table.insert(out, c)
            i = i + 1
         end
      else
         table.insert(out, c)
         i = i + 1
      end
   end
   local s = cas.input(table.concat(out), MAP, false, true)
   return s and cas.rename(s, holders, true)
end

-- Keywords at the start (or end) of a condition
local KEYS = {
   { 'tangent', 'tangent' },
   { 'turning point', 'tp' }, { 'stationary point', 'tp' }, { 'turning', 'tp' }, { 'stationary', 'tp' },
   { 'maximum', 'tp' }, { 'minimum', 'tp' }, { 'max', 'tp' }, { 'min', 'tp' }, { 'tp', 'tp' }, { 'sp', 'tp' },
   { 'point of inflection', 'infl' }, { 'inflection point', 'infl' }, { 'inflection', 'infl' },
   { 'poi', 'infl' }, { 'infl', 'infl' },
   { 'asymptote', 'asym' }, { 'asym', 'asym' }, { 'va', 'asym' }, { 'ha', 'asym' },
   { 'passes through', 'pt' }, { 'through', 'pt' }, { 'passes', 'pt' }, { 'point', 'pt' },
}

local function keyword(text)
   local low = text:lower()
   for _, k in ipairs(KEYS) do
      local w = k[1]
      if low:sub(1, #w) == w and not low:sub(#w + 1, #w + 1):match('%a') then
         return k[2], U.trim(text:sub(#w + 1))
      end
      if low:sub(-#w) == w and not low:sub(-#w - 1, -#w - 1):match('%a') then
         return k[2], U.trim(text:sub(1, -#w - 1))
      end
   end
end

-- '(p, q)' -> p, q ; 'x=p' or 'p' -> p
local function point_of(rest)
   rest = U.trim((rest or ''):gsub('^[Aa][Tt]%s+', ''):gsub('^:%s*', ''))
   local inner = rest:match('^pt%s*(%b())$') or rest:match('^(%b())$')
   if inner then
      local parts = cas.split_top(inner:sub(2, -2), ',')
      if #parts == 2 then return U.trim(parts[1]), U.trim(parts[2]) end
   end
   local p = rest:match('^[xX]%s*=%s*(.+)$')
   if p then return U.trim(p) end
   if rest ~= '' and not rest:find('=') then return rest end
end

local function num(e)
   return cas.n(e)
end

-- '→' arrow for limits
local function sym_to()
   return '\226\134\146'
end

-- Expression that is zero at a vertical asymptote: a denominator or log
-- argument containing the variable (falls back to 1/f -> 0)
local function asym_zero(src, X)
   for _, sp in ipairs(U.special_subexprs(src)) do
      if sp.kind == 'zero' and cas.uses(sp.expr, { X }) then return sp.expr end
   end
end

-- Equations for one condition: list of { eq = 'lhs=rhs', why = text }, marks
local function cond_eqs(raw, name, F, src, X)
   local out, marks = {}, {}
   local nm = name
   local function v(e) return cas.input(e, MAP, false, true) end
   local function add(lhs, rhs, why) table.insert(out, { eq = lhs .. '=' .. U.par(rhs), why = why }) end
   local kind, rest = keyword(raw)
   if not kind and raw:match('^%s*pt%s*%b()%s*$') or (not kind and raw:match('^%s*%b()%s*$')) then
      kind, rest = 'pt', raw
   end
   if kind == 'pt' or kind == 'tp' or kind == 'infl' then
      local p, q = point_of(rest)
      if not p then error({ desc = 'Write the point as (2,5) or x=2' }) end
      p, q = v(p), q and v(q)
      local pt_text = q and ('(' .. U.txt(p) .. ', ' .. U.txt(q) .. ')') or ('x = ' .. U.txt(p))
      if q then
         add(F.at(p), q, pt_text .. ' is on the graph: ' .. nm .. '(' .. U.txt(p) .. ') = ' .. U.txt(q))
      end
      if kind == 'tp' then
         add(F.d(p, 1), '0', 'stationary at ' .. pt_text .. ': ' .. nm .. "'(" .. U.txt(p) .. ') = 0')
      elseif kind == 'infl' then
         add(F.d(p, 2), '0', 'inflection at ' .. pt_text .. ': ' .. nm .. "''(" .. U.txt(p) .. ') = 0')
      end
      table.insert(marks, { x = p, y = q, kind = kind == 'tp' and 'max' or (kind == 'infl' and 'inflect' or 'point') })
   elseif kind == 'tangent' then
      local line, at
      for _, part in ipairs(cas.split_top((rest:gsub(' at ', ',', 1):gsub(' is ', ',', 1)), ',')) do
         part = U.trim(part:gsub('^[Aa][Tt]%s+', ''))
         if part:match('^[yY]%s*=') then line = part:match('^[yY]%s*=(.*)$')
         elseif part:match('^[xX]%s*=') then at = part:match('^[xX]%s*=(.*)$') end
      end
      if not (line and at) then error({ desc = 'Write a tangent as tangent y=2x+1 at x=1' }) end
      local L, p = v(line), v(at)
      local Lp = U.simp(cas.rename(L, { [X] = '(' .. p .. ')' }, true))
      local m = U.simp('derivative(' .. L .. ',' .. X .. ')|' .. X .. '=' .. U.par(p))
      add(F.at(p), Lp, 'tangent touches at x = ' .. U.txt(p) .. ': ' .. nm .. '(' .. U.txt(p) .. ') = ' .. U.txt(Lp))
      add(F.d(p, 1), m, 'same gradient: ' .. nm .. "'(" .. U.txt(p) .. ') = ' .. U.txt(m))
      table.insert(marks, { x = p, y = Lp, kind = 'point', line = L })
   elseif kind == 'asym' then
      local p = rest:match('^[xX]%s*=%s*(.+)$')
      local q = rest:match('^[yY]%s*=%s*(.+)$')
      if p then
         p = v(p)
         local z = asym_zero(src, X)
         local lhs = z and ('(' .. cas.rename(z, { [X] = '(' .. p .. ')' }, true) .. ')')
            or ('limit(1/' .. U.par(src) .. ',' .. X .. ',' .. p .. ')')
         add(lhs, '0',
             'vertical asymptote x = ' .. U.txt(p) .. ': ' .. nm .. '(x) ' .. U.IMPL .. ' ' .. U.PM .. U.INF
             .. ' as x ' .. sym_to() .. ' ' .. U.txt(p))
         table.insert(marks, { vx = p })
      elseif q then
         q = v(q)
         local dir = U.INF
         local lim = cas.eval('limit(' .. src .. ',' .. X .. ',' .. U.INF .. ')')
         if lim and not lim:find('limit', 1, true) and (lim:find(U.INF, 1, true) or lim:find('undef')) then
            dir = U.NEGINF
         end
         add('limit(' .. src .. ',' .. X .. ',' .. dir .. ')', q,
             'horizontal asymptote y = ' .. U.txt(q) .. ': ' .. nm .. '(x) ' .. sym_to() .. ' ' .. U.txt(q)
             .. ' as x ' .. sym_to() .. ' ' .. (dir == U.INF and U.INF or (U.NEG .. U.INF)))
         table.insert(marks, { hy = q })
      else
         error({ desc = 'Write an asymptote as x=2 or y=3' })
      end
   else
      if not raw:find('=') then error({ desc = 'A condition needs = (e.g. f(1)=3)' }) end
      local e = expand(raw, name, F)
      table.insert(out, { eq = e, why = raw })
   end
   return out, marks
end

local function assignments(res, params)
   local sols = {}
   if not res or res == 'false' then return sols end
   for _, alt in ipairs(cas.split_top(res, 'or')) do
      local a = {}
      for _, conj in ipairs(cas.split_top(alt, 'and')) do
         local lhs, rhs = conj:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
         if lhs then a[lhs] = rhs end
      end
      local ok = true
      for _, p in ipairs(params) do if not a[p] then ok = false end end
      if ok then table.insert(sols, a) end
   end
   return sols
end

function S.solve(I, R)
   if not I.f then
      R:note("Type f(x) with its unknown constants, e.g. a*x^3+b*x^2+c")
      return
   end
   local name, var, src, X = read_rule(I.f)
   if not src then return end
   local F = maker(src, X)
   local disp = name .. '(' .. var .. ')'

   -- Equations from the conditions ------------------------------------------
   local eqs, marks = {}, {}
   local given = 0
   for i = 1, NCOND do
      local raw = I['c' .. i]
      if raw and U.trim(raw) ~= '' then
         given = given + 1
         local ok, list, mk = pcall(cond_eqs, raw, name, F, src, X)
         if not ok then
            local msg = type(list) == 'table' and list.desc or tostring(list)
            R:note('Condition ' .. i .. ': ' .. msg, 'error')
         else
            for _, e in ipairs(list) do table.insert(eqs, e) end
            for _, m in ipairs(mk) do table.insert(marks, m) end
         end
      end
   end

   local exprs = { src }
   for _, e in ipairs(eqs) do table.insert(exprs, e.eq) end
   local params = params_of(exprs, X)
   local names = {}
   for _, p in ipairs(params) do table.insert(names, cas.display_name(p)) end

   R:step(disp .. ' = ' .. M(src))
   if #params == 0 then
      R:note('No unknown constants: use letters such as a, b, c in ' .. disp)
   end

   R:section('Equations')
   local sys = {}
   for _, e in ipairs(eqs) do
      local s = cas.eval(e.eq) or e.eq
      if s == 'true' then
         R:step(e.why .. ' (always true)')
      elseif s == 'false' then
         R:step(e.why .. ' (impossible)')
         R:note('A condition can never hold: check the conditions', 'error')
      else
         R:step(e.why .. ':  ' .. M(s))
         table.insert(sys, s)
      end
   end

   if #params == 0 then return end
   if #sys < #params then
      R:note(#params .. ' unknowns (' .. table.concat(names, ', ') .. ') need ' .. #params
             .. ' conditions: add ' .. (#params - #sys) .. ' more')
      return
   end

   -- Solve ----------------------------------------------------------------------
   R:section('Solve')
   local system = table.concat(sys, ' and ')
   local res
   if #params == 1 then
      local list = cas.solve(system, params[1])
      if list then
         local alts = {}
         for _, v in ipairs(list) do table.insert(alts, params[1] .. '=' .. v) end
         res = #alts > 0 and table.concat(alts, ' or ') or 'false'
      end
   else
      res = cas.eval('solve(' .. system .. ',{' .. table.concat(params, ',') .. '})')
   end
   local sols = assignments(res, params)
   if #sys == 1 then
      R:step('Solve for ' .. table.concat(names, ', '))
   else
      R:step('Solve the ' .. #sys .. ' equations simultaneously for ' .. table.concat(names, ', '))
   end
   if #sols == 0 then
      R:note('No values of ' .. table.concat(names, ', ') .. ' satisfy all the conditions', 'error')
      return
   end

   local first
   for k, a in ipairs(sols) do
      local parts, map = {}, {}
      for _, p in ipairs(params) do
         local val = a[p]
         table.insert(parts, M(p .. '=' .. val))
         map[p] = '(' .. val .. ')'
         local label = cas.display_name(p) .. (#sols > 1 and (' (solution ' .. k .. ')') or '')
         R:result(label, val, { key = 'param_' .. cas.display_name(p) .. (#sols > 1 and k or '') })
      end
      local fsub = U.simp(cas.rename(src, map, true))
      R:step(U.IMPL .. ' ' .. table.concat(parts, ', ') .. ',  so ' .. disp .. ' = ' .. M(fsub))
      R:result(disp .. (#sols > 1 and (' (solution ' .. k .. ')') or ''), fsub, { key = 'fx' .. (#sols > 1 and k or '') })
      first = first or { map = map, f = fsub }
   end

   -- Check (first solution) ---------------------------------------------------------
   R:section('Check')
   for _, e in ipairs(eqs) do
      local sides = cas.split_top(e.eq, '=')
      local lhs, rhs = sides[1], sides[2]
      if #sides == 2 then
         local l = cas.n(cas.rename(lhs, first.map, true))
         local r = cas.n(cas.rename(rhs, first.map, true))
         if l and r then
            local okc = abs(l - r) <= 1e-6 * max(1, abs(r))
            R:step(e.why:gsub(':.*$', '') .. ': ' .. U.D(okc and r or l) .. (okc and ' = ' or ' ' .. U.NEQ .. ' ') .. U.D(r))
         end
      end
   end

   -- Graph -----------------------------------------------------------------------------
   local Fn = numeric.compile(first.f, { X }) or numeric.compile_or_cas(first.f, { X })
   local spec = { curves = { { fn = Fn } }, points = {}, asymptotes = {} }
   local xs = {}
   for _, m in ipairs(marks) do
      local mx = m.x and num(cas.rename(m.x, first.map, true))
      if mx then
         table.insert(xs, mx)
         local my = Fn(mx)
         if my then
            table.insert(spec.points, { x = mx, y = my, kind = m.kind,
                                        label = '(' .. U.txt(m.x) .. ', ' .. U.txt(m.y or tostring(my)) .. ')' })
         end
         if m.line then
            local L = numeric.compile(m.line, { X })
            if L then table.insert(spec.curves, { fn = L }) end
         end
      end
      local vx = m.vx and num(m.vx)
      if vx then
         table.insert(xs, vx)
         table.insert(spec.asymptotes, { kind = 'v', x = vx })
      end
      local hy = m.hy and num(m.hy)
      if hy then table.insert(spec.asymptotes, { kind = 'h', y = hy }) end
   end
   -- window around the given points (or -5..5)
   local lo, hi = math.huge, -math.huge
   for _, x in ipairs(xs) do lo, hi = min(lo, x - 2), max(hi, x + 2) end
   if lo > hi then lo, hi = -5, 5 end
   if hi - lo < 6 then
      local mid = (lo + hi) / 2
      lo, hi = mid - 3, mid + 3
   end
   spec.xmin, spec.xmax = lo, hi
   R.graph = spec
end

S.count_params = count_params

return S
