-- Rectilinear motion with variable acceleration (differential equations):
-- given a(t), a(v), a(x), v(t), v(x), v²(x) or x(t) plus known values,
-- derive the other relations and answer "when ...?" questions.
local cas = require 'apps.vce.cas'
local U = require 'apps.vce.solvers.util'

local M = U.M
local T, X, V = 'q9t', 'q9x', 'q9v'
local DT, DX, DV = 'q8t', 'q8x', 'q8v'

local TYPES = {
   { 'a(t)', 'a = f(t)' }, { 'a(v)', 'a = f(v)' }, { 'a(x)', 'a = f(x)' },
   { 'v(t)', 'v = f(t)' }, { 'v(x)', 'v = f(x)' }, { 'v2(x)', 'v' .. U.SQ .. ' = f(x)' },
   { 'x(t)', 'x = f(t)' },
}

local S = {
   id = 'kinematics',
   title = 'Kinematics: a(t), a(v), a(x), v(t), v(x), x(t)',
   short = 'Kinematics',
   group = 'Mechanics',
   desc = 'Integrate/differentiate motion, solve for constants, find t, x, v',
   fields = {
      { id = 'type', label = 'Given', kind = 'choice', options = TYPES },
      { id = 'f', label = function(I)
           local t = I.type or 'a(t)'
           if t == 'v2(x)' then return 'v' .. U.SQ .. '(x) =' end
           return t .. ' ='
        end, hint = 'e.g. 6t   -(1+v^2)/10   f11(t)' },
      { id = 't0', label = 't0', hint = 'time of known values (default 0)' },
      { id = 'x0', label = 'x0', hint = 'position at t0' },
      { id = 'v0', label = 'v0', hint = 'velocity at t0' },
      { id = 'c2', label = 'also', hint = 'x(2)=5   v=2,x=1   a=-3.5,v=7 (finds k)' },
      { id = 'find', label = 'Find when', hint = 't=3   v=0   x=5   a=0' },
      { id = 't1', label = 'from t=', hint = 'displacement / distance' },
      { id = 't2', label = 'to t=', hint = '' },
   },
   example = { type = 'a(t)', f = '6t', t0 = '0', x0 = '1', v0 = '2', find = 't=2' },
}

local MAP = U.locals_map()

-- Variable of the given function: a(v) -> v, v(x) -> x, x(t) -> t
local function indep_of(kind)
   return kind:match('%((%a)%)$') or 't'
end

-- Parse conditions into a list of {t=, x=, v=, a=}. Conditions are separated
-- by ';' and the parts of one condition by ',' or 'when':
--   'x(2)=5', 'v=2,x=1', 'a=-3.5 when v=7', 'a(7)=-3.5' (for a(v): v = 7)
-- Function notation uses t, except for the given function's own letter,
-- which uses its variable (a(v): a(7) means v = 7).
local function parse_conds(text, kind)
   if not text or U.trim(text) == '' then return {} end
   local own, own_var = (kind or 'a(t)'):sub(1, 1), indep_of(kind or 'a(t)')
   local out = {}
   for _, one in ipairs(cas.split_top(text, ';')) do
      local c = {}
      one = one:gsub(' when ', ','):gsub(' at ', ','):gsub(' if ', ',')
      for _, part in ipairs(cas.split_top(one, ',')) do
         local var, arg, val = part:match('^%s*([txvaTXVA])%s*%((.-)%)%s*=%s*(.-)%s*$')
         if var then
            var = var:lower()
            c[var == own and own_var or 't'] = arg
            c[var] = val
         else
            var, val = part:match('^%s*([txvaTXVA])%s*=%s*(.-)%s*$')
            if var then c[var:lower()] = val end
         end
      end
      for k, v in pairs(c) do
         c[k] = U.read(v).val
      end
      if next(c) then table.insert(out, c) end
   end
   return out
end

-- Domain helpers -------------------------------------------------------------

-- 'lo<var≤hi' (nil bound = unbounded); nil when unbounded both ways
local function interval(lo, lo_inc, var, hi, hi_inc)
   if lo and hi then
      return lo .. (lo_inc and U.LEQ or '<') .. var .. (hi_inc and U.LEQ or '<') .. hi
   elseif lo then
      return var .. (lo_inc and U.GEQ or '>') .. lo
   elseif hi then
      return var .. (hi_inc and U.LEQ or '<') .. hi
   end
   return nil
end

-- Real roots of e = 0 in var: list of { e = exact, n = number }
local function real_roots(e, var)
   local out = {}
   local sols = cas.solve(e .. '=0', var)
   for _, r in ipairs(sols or {}) do
      if not r:find('@', 1, true) then
         local n = cas.n(r)
         if n then table.insert(out, { e = r, n = n }) end
      end
   end
   return out
end

-- Where a rate g(var) is zero (closed = reached) or undefined (open)
local function barriers(g, var, zero_closed)
   local out = {}
   for _, r in ipairs(real_roots(g, var)) do
      r.closed = zero_closed
      table.insert(out, r)
   end
   local den = cas.eval('getDenom(' .. g .. ')')
   if den and not den:find('getDenom', 1, true) and cas.uses(den, { var }) then
      for _, r in ipairs(real_roots(den, var)) do
         r.closed = false
         table.insert(out, r)
      end
   end
   return out
end

-- Nearest barrier strictly beyond start in direction dir (+1/-1)
local function nearest(list, start, dir)
   local best
   for _, b in ipairs(list) do
      local d = (b.n - start) * dir
      if d > 1e-12 and (not best or d < (best.n - start) * dir) then best = b end
   end
   return best
end

-- One-sided limit of e as var -> point from the side opposite to dir
-- (approaching while moving in direction dir); nil if unknown
local function limit_toward(e, var, point, dir)
   local where = point or (dir > 0 and U.INF or U.NEGINF)
   local q = 'limit(' .. e .. ',' .. var .. ',' .. where .. (point and (',' .. (dir > 0 and '-1' or '1')) or '') .. ')'
   local L = cas.eval(q)
   if not L or L:find('limit', 1, true) or L:find('undef', 1, true) then return nil end
   return L, cas.n(L)
end

function S.solve(I, R)
   local kind = I.type or 'a(t)'
   if not I.f then
      R:note('Enter ' .. kind .. ' and any known values')
      return
   end
   local f = cas.input(I.f, MAP)
   local fv = U.simp(f)
   local base = ({ ['a(t)'] = 'at', ['a(v)'] = 'av', ['a(x)'] = 'ax', ['v(t)'] = 'vt', ['v(x)'] = 'vx',
                   ['v2(x)'] = 'v2x', ['x(t)'] = 'xt' })[kind]

   -- Known values -----------------------------------------------------------
   local conds = {}
   local x0, v0 = U.read(I.x0), U.read(I.v0)
   local t0 = U.read(I.t0)
   if x0 or v0 or t0 then
      table.insert(conds, { t = t0 and t0.val or ((x0 or v0) and '0' or nil),
                            x = x0 and x0.val, v = v0 and v0.val })
   end
   for _, c in ipairs(parse_conds(I.c2, kind)) do table.insert(conds, c) end

   local function find_cond(a, b)
      for _, c in ipairs(conds) do
         if c[a] and c[b] then return c end
      end
   end

   local K = {}  -- derived relations
   local function show_given(name)
      R:step('Given ' .. name .. ' = ' .. M(fv))
   end

   local function res(key, label, value)
      K[key] = value
      R:result(label, value, { key = key })
   end

   local function dummy(e, from, to)
      return cas.rename(e, { [from] = to }, true)
   end

   -- Unknown constants (k, g, ...) from conditions such as a=-3.5 when v=7 ------
   R:tag(base)
   local motion = { [T] = true, [X] = true, [V] = true }
   local params = {}
   for _, u in ipairs(U.unknowns(fv)) do
      if not motion[u] then table.insert(params, u) end
   end
   if #params > 0 then
      local own = kind:sub(1, 1)
      local ivar = ({ t = T, x = X, v = V })[indep_of(kind)]
      show_given(kind == 'v2(x)' and ('v' .. U.SQ) or own)
      local eqs = {}
      for _, c in ipairs(conds) do
         local dep = c[own]
         if kind == 'v2(x)' and c.v then dep = U.par(c.v) .. '^2' end
         local at = c[indep_of(kind)]
         if dep and at then
            local lhs = cas.rename(fv, { [ivar] = U.par(at) }, true)
            lhs = cas.eval(lhs) or lhs
            R:step('When ' .. indep_of(kind) .. ' = ' .. M(at) .. ', ' .. (kind == 'v2(x)' and ('v' .. U.SQ) or own)
                   .. ' = ' .. M(dep) .. ':  ' .. M(lhs .. '=' .. dep))
            table.insert(eqs, U.par(lhs) .. '=' .. U.par(dep))
         end
      end
      local names = {}
      for _, p in ipairs(params) do table.insert(names, cas.display_name(p)) end
      if #eqs >= #params then
         local assigns = {}
         if #params == 1 then
            local sols = cas.solve(table.concat(eqs, ' and '), params[1])
            if sols and sols[1] then assigns[1] = { params[1], sols[1] } end
         else
            local res_s = cas.eval('solve(' .. table.concat(eqs, ' and ') .. ',{' .. table.concat(params, ',') .. '})')
            local first = res_s and cas.split_top(res_s, 'or')[1]
            for _, conj in ipairs(first and cas.split_top(first, 'and') or {}) do
               local lhs, rhs = conj:match('^([%w_]+)%s*=%s*(.+)$')
               if lhs then table.insert(assigns, { lhs, rhs }) end
            end
         end
         if #assigns == #params then
            local parts = {}
            for _, a in ipairs(assigns) do
               table.insert(parts, M(a[1] .. '=' .. a[2]))
               R:result(cas.display_name(a[1]), a[2], { key = 'param_' .. cas.display_name(a[1]) })
            end
            local map = {}
            for _, a in ipairs(assigns) do map[a[1]] = U.par(a[2]) end
            fv = U.simp(cas.rename(fv, map, true))
            R:step(U.IMPL .. ' ' .. table.concat(parts, ', ') .. ',  so ' .. (kind == 'v2(x)' and ('v' .. U.SQ) or own)
                   .. ' = ' .. M(fv))
         else
            R:note('Could not find ' .. table.concat(names, ', ') .. ' from the conditions', 'warn')
         end
      else
         R:note('Unknown constant ' .. table.concat(names, ', ') .. ': add a condition such as a=-3.5 when v=7', 'warn')
      end
   end
   local given_shown = #params > 0
   local function given(name)
      if not given_shown then show_given(name) end
   end

   -- integrate: result(var) = c[b] + ∫_{c[a]}^{var} g d(var)
   -- g in terms of integration variable `ivar` with dummy `dvar`
   local function integrate(g, ivar, dvar, lname, gname, var_key, val_key)
      local c = find_cond(var_key, val_key)
      if c then
         local expr = U.par(c[val_key]) .. '+integral(' .. dummy(g, ivar, dvar) .. ',' .. dvar .. ',' .. c[var_key] .. ',' .. ivar .. ')'
         local r = U.simp(expr)
         R:step(lname .. ' = ' .. M(c[val_key]) .. ' + ' .. M('integral(' .. dummy(g, ivar, dvar) .. ',' .. dvar .. ',' .. c[var_key] .. ',' .. ivar .. ')')
                .. ' = ' .. M(r))
         return r
      end
      local F = U.simp('integral(' .. g .. ',' .. ivar .. ')')
      R:step(lname .. ' = ' .. M('integral(' .. g .. ',' .. ivar .. ')') .. ' = ' .. M(F .. '+c'))
      R:note('Need ' .. val_key .. ' at a known ' .. var_key .. ' to find c for ' .. gname, 'warn')
      return nil
   end

   -- choose solution of var that matches the condition (indep=a -> value b)
   local function pick(sols, indep, a, b)
      if not sols or #sols == 0 then return nil end
      if #sols == 1 or not (a and b) then return sols[1] end
      local bn = cas.n(b)
      for _, sv in ipairs(sols) do
         local v = cas.n(cas.with(sv, { { indep, a } }))
         if v and bn and math.abs(v - bn) < 1e-6 * (1 + math.abs(bn)) then
            return sv
         end
      end
      return sols[1]
   end

   -- x(t) from v(t) by integration
   local function x_from_vt()
      if K.vt and not K.xt then
         R:tag('xt', { 'vt' })
         local r = integrate(K.vt, T, DT, 'x = x0 + ' .. U.INTG .. 'v dt', 'x(t)', 't', 'x')
         if r then res('xt', 'x(t)', r) end
      end
   end

   -- t(x) from v(x), then x(t) by solving
   local function t_from_vx()
      if not K.vx then return end
      local c = find_cond('t', 'x')
      if not c then
         R:note('Need x at a known t to find t(x) and x(t)', 'warn')
         return
      end
      R:tag('tx', { 'vx' })
      R:step('dt/dx = 1/v')
      local tx = U.simp(U.par(c.t) .. '+integral(1/(' .. dummy(K.vx, X, DX) .. '),' .. DX .. ',' .. c.x .. ',' .. X .. ')')
      R:step('t = ' .. M(c.t) .. ' + ' .. M('integral(1/(' .. dummy(K.vx, X, DX) .. '),' .. DX .. ',' .. c.x .. ',' .. X .. ')') .. ' = ' .. M(tx))
      res('tx', 't(x)', tx)
      local sols = cas.solve(T .. '=' .. tx, X)
      local xt = pick(sols, T, c.t, c.x)
      if xt then
         R:tag('xt', { 'tx' })
         R:step('Solve for x: x = ' .. M(xt))
         res('xt', 'x(t)', xt)
         R:tag('vt', { 'xt' })
         K.vt = K.vt or U.simp('derivative(' .. xt .. ',' .. T .. ')')
         R:step('v = dx/dt = ' .. M(K.vt))
         R:result('v(t)', K.vt, { key = 'vt' })
      end
   end

   -- v(x) from v²(x) with the sign from the known motion
   local function v_from_v2x()
      if not K.v2x or K.vx then return end
      R:tag('vx', { 'v2x' })
      local sign = 1
      local c = find_cond('x', 'v')
      local reason = ''
      if c then
         local vn = cas.n(c.v)
         if vn and vn < 0 then
            sign, reason = -1, 'v < 0 initially'
         elseif vn and vn > 0 then
            reason = 'v > 0 initially'
         elseif vn == 0 then
            -- starts at rest: moves in the direction of the acceleration
            local acc = K.ax and cas.n(cas.with(K.ax, { { X, c.x } }))
            if acc and acc < 0 then
               sign, reason = -1, 'starts at rest with a < 0'
            else
               reason = 'starts at rest with a > 0'
            end
         end
      end
      local root = U.ROOT .. '(' .. K.v2x .. ')'
      local vx = U.simp((sign < 0 and U.NEG or '') .. root)
      R:step('v = ' .. (sign < 0 and '-' or '') .. M(root) .. (reason ~= '' and ('  (' .. reason .. ')') or '  (taking v > 0)'))
      res('vx', 'v(x)', vx)
      K.vsign = sign
   end

   -- Derivations by type -------------------------------------------------------
   if kind == 'x(t)' then
      given('x')
      res('xt', 'x(t)', fv)
      R:tag('vt', { 'xt' })
      local vt = U.simp('derivative(' .. fv .. ',' .. T .. ')')
      R:step('v = dx/dt = ' .. M(vt))
      res('vt', 'v(t)', vt)
      R:tag('at', { 'vt' })
      local at = U.simp('derivative(' .. vt .. ',' .. T .. ')')
      R:step('a = dv/dt = ' .. M(at))
      res('at', 'a(t)', at)
   elseif kind == 'v(t)' then
      given('v')
      res('vt', 'v(t)', fv)
      R:tag('at', { 'vt' })
      local at = U.simp('derivative(' .. fv .. ',' .. T .. ')')
      R:step('a = dv/dt = ' .. M(at))
      res('at', 'a(t)', at)
      x_from_vt()
   elseif kind == 'a(t)' then
      given('a')
      res('at', 'a(t)', fv)
      R:tag('vt', { 'at' })
      local vt = integrate(fv, T, DT, 'v = v0 + ' .. U.INTG .. 'a dt', 'v(t)', 't', 'v')
      if vt then
         res('vt', 'v(t)', vt)
         x_from_vt()
      end
   elseif kind == 'v(x)' then
      given('v')
      res('vx', 'v(x)', fv)
      R:tag('ax', { 'vx' })
      local ax = U.simp(U.par(fv) .. '*derivative(' .. fv .. ',' .. X .. ')')
      R:step('a = v' .. '\194\183' .. 'dv/dx = ' .. M(ax))
      res('ax', 'a(x)', ax)
      t_from_vx()
   elseif kind == 'v2(x)' then
      given('v' .. U.SQ)
      res('v2x', 'v' .. U.SQ .. '(x)', fv)
      R:tag('ax', { 'v2x' })
      local ax = U.simp('derivative(' .. fv .. ',' .. X .. ')/2')
      R:step('a = d/dx(' .. M('1/2*v^2') .. ') = ' .. M(ax))
      res('ax', 'a(x)', ax)
      v_from_v2x()
      if K.vx then t_from_vx() end
   elseif kind == 'a(x)' then
      given('a')
      res('ax', 'a(x)', fv)
      R:tag('v2x', { 'ax' })
      R:step('a = d/dx(' .. M('1/2*v^2') .. ')')
      local c = find_cond('x', 'v')
      if c then
         local expr = U.par(c.v) .. '^2+2*integral(' .. dummy(fv, X, DX) .. ',' .. DX .. ',' .. c.x .. ',' .. X .. ')'
         local v2 = U.simp(expr)
         R:step(M('1/2*v^2') .. ' = ' .. M('1/2*' .. U.par(c.v) .. '^2') .. ' + ' .. M('integral(' .. dummy(fv, X, DX) .. ',' .. DX .. ',' .. c.x .. ',' .. X .. ')'))
         R:step(U.IMPL .. ' v' .. U.SQ .. ' = ' .. M(v2))
         res('v2x', 'v' .. U.SQ .. '(x)', v2)
         v_from_v2x()
         t_from_vx()
      else
         local F = U.simp('integral(' .. fv .. ',' .. X .. ')')
         R:step(M('1/2*v^2') .. ' = ' .. M('integral(' .. fv .. ',' .. X .. ')') .. ' = ' .. M(F .. '+c'))
         R:note('Need v at a known x to find c', 'warn')
      end
   elseif kind == 'a(v)' then
      given('a')
      res('av', 'a(v)', fv)
      -- terminal (limiting) velocity: equilibrium approached from v0
      local roots = cas.solve(fv .. '=0', V)
      if roots and #roots > 0 then
         R:tag('vterm', { 'av' })
         local c0 = find_cond('t', 'v') or find_cond('x', 'v')
         local vterm = roots[1]
         if c0 and #roots > 1 then
            local v0n = cas.n(c0.v)
            local a0 = cas.n(cas.with(fv, { { V, c0.v } }))
            local best
            for _, r in ipairs(roots) do
               local rn = cas.n(r)
               if rn and v0n and a0 then
                  if (a0 > 0 and rn > v0n) or (a0 < 0 and rn < v0n) or a0 == 0 then
                     if not best or math.abs(rn - v0n) < math.abs(cas.n(best) - v0n) then best = r end
                  end
               end
            end
            vterm = best or vterm
         end
         R:step('a = 0 when v = ' .. M(vterm) .. ' (limiting/terminal velocity)')
         R:result('v terminal', vterm, { key = 'vterm' })
      end
      local c = find_cond('t', 'v')
      if c then
         R:tag('tv', { 'av' })
         R:step('dv/dt = a ' .. U.IMPL .. ' dt/dv = 1/a')
         local tv = U.simp(U.par(c.t) .. '+integral(1/(' .. dummy(fv, V, DV) .. '),' .. DV .. ',' .. c.v .. ',' .. V .. ')')
         R:step('t = ' .. M(c.t) .. ' + ' .. M('integral(1/(' .. dummy(fv, V, DV) .. '),' .. DV .. ',' .. c.v .. ',' .. V .. ')') .. ' = ' .. M(tv))
         res('tv', 't(v)', tv)
         local sols = cas.solve(T .. '=' .. tv, V)
         local vt = pick(sols, T, c.t, c.v)
         if vt then
            R:tag('vt', { 'tv' })
            R:step('Solve for v: v = ' .. M(vt))
            res('vt', 'v(t)', vt)
            R:tag('at', { 'vt' })
            local at = U.simp(cas.rename(fv, { [V] = U.par(vt) }, true))
            R:step('a = a(v(t)) = ' .. M(at))
            res('at', 'a(t)', at)
            x_from_vt()
         end
      end
      local cx = find_cond('x', 'v')
      if cx then
         R:tag('xv', { 'av' })
         R:step('v' .. '\194\183' .. 'dv/dx = a ' .. U.IMPL .. ' dx/dv = v/a')
         local xv = U.simp(U.par(cx.x) .. '+integral(' .. DV .. '/(' .. dummy(fv, V, DV) .. '),' .. DV .. ',' .. cx.v .. ',' .. V .. ')')
         R:step('x = ' .. M(cx.x) .. ' + ' .. M('integral(' .. DV .. '/(' .. dummy(fv, V, DV) .. '),' .. DV .. ',' .. cx.v .. ',' .. V .. ')') .. ' = ' .. M(xv))
         res('xv', 'x(v)', xv)
         local sols = cas.solve(X .. '=' .. xv, V)
         local vx = pick(sols, X, cx.x, cx.v)
         if vx then
            R:tag('vx', { 'xv' })
            R:step('Solve for v: v = ' .. M(vx))
            res('vx', 'v(x)', vx)
         end
      end
      if not c and not cx then
         -- general solutions: the constant needs v at a known t or x
         R:tag('tv', { 'av' })
         local Ft = U.simp('integral(1/(' .. fv .. '),' .. V .. ')')
         R:step('dt/dv = 1/a ' .. U.IMPL .. ' t = ' .. M('integral(1/(' .. fv .. '),' .. V .. ')') .. ' = ' .. M(Ft .. '+c'))
         R:tag('xv', { 'av' })
         local Fx = U.simp('integral(' .. V .. '/(' .. fv .. '),' .. V .. ')')
         R:step('dx/dv = v/a ' .. U.IMPL .. ' x = ' .. M('integral(' .. V .. '/(' .. fv .. '),' .. V .. ')') .. ' = ' .. M(Fx .. '+c'))
         R:note('Enter v0 (and x0) to integrate', 'warn')
      end
   end
   K.fv = fv

   -- Domains -------------------------------------------------------------------
   -- From the motion: start at the known state and move until v reaches a
   -- terminal value or 0 (a(v)), a turning point (v² = 0) or a singularity.
   local doms, dom_why = {}, {}
   local state = find_cond('t', 'v') or find_cond('x', 'v') or find_cond('t', 'x') or conds[1]
   local tstart = (state and state.t) or '0'
   local function set_dom(key, d, why)
      if K[key] and d then doms[key], dom_why[key] = d, why end
   end
   -- formulas in t: t ≥ t0, cut where the formula stops being defined
   local function t_dom(e, tend, tend_inc)
      local d = interval(tstart, true, T, tend, tend_inc)
      local cd = e and cas.eval('domain(' .. e .. ',' .. T .. ')')
      if cd and not cd:find('domain', 1, true) and not cd:find('@', 1, true) and cas.uses(cd, { T }) then
         local both = cas.eval('solve(' .. d .. ' and ' .. U.par(cd) .. ',' .. T .. ')')
         if both and not both:find('solve', 1, true) and both ~= 'false' and both ~= 'true' then d = both end
      end
      return d
   end
   local ok_dom = pcall(function()
      if kind == 'a(v)' then
         local c = find_cond('t', 'v') or find_cond('x', 'v')
         local v0s = c and c.v
         local v0n = v0s and cas.n(v0s)
         local a0 = v0s and cas.n(cas.with(fv, { { V, v0s } }))
         if v0n and a0 and a0 ~= 0 then
            local dir = a0 > 0 and 1 or -1
            local stop = nearest(barriers(fv, V, false), v0n, dir)
            local vend = stop and stop.e
            local vdom = dir < 0 and interval(vend, false, V, v0s, true) or interval(v0s, true, V, vend, false)
            local why = 'a ' .. (dir < 0 and '< 0' or '> 0') .. ': v ' .. (dir < 0 and 'decreases' or 'increases')
                        .. ' from ' .. M(v0s) .. (vend and (' towards ' .. M(vend)) or '')
            set_dom('tv', vdom, why)
            set_dom('xv', vdom, why)
            if K.tv then
               local tend, tn = limit_toward(K.tv, V, vend, dir)
               if tn and math.abs(tn) == math.huge then tend = nil end
               for _, k in ipairs({ 'vt', 'at', 'xt' }) do set_dom(k, t_dom(K[k], tend, false), why) end
            end
            if K.xv then
               -- v(x) is single valued until the particle stops (v = 0)
               -- (passing through v = 0 before the terminal value)
               local vsn = stop and stop.n
               local crosses = false
               if v0n ~= 0 then
                  if vsn then
                     crosses = vsn ~= 0 and (vsn < 0) ~= (v0n < 0)
                  else
                     crosses = (dir < 0) == (v0n > 0)
                  end
               end
               local x0s = (find_cond('x', 'v') or {}).x
               local xend, xn
               if crosses then
                  xend = U.simp(cas.with(K.xv, { { V, '0' } }))
                  xn = cas.n(xend)
               else
                  xend, xn = limit_toward(K.xv, V, vend, dir)
               end
               if xn and math.abs(xn) == math.huge then xend = nil end
               local reached = crosses
               local x0n = x0s and cas.n(x0s)
               if x0s and x0n then
                  local up = xend and (xn or 0) > x0n or (not xend and v0n > 0)
                  set_dom('vx', up and interval(x0s, true, X, xend, reached) or interval(xend, reached, X, x0s, true), why)
               end
            end
         end
      elseif K.v2x or (kind == 'v(x)') then
         local c = find_cond('x', 'v') or find_cond('t', 'x')
         local x0s = c and c.x
         local x0n = x0s and cas.n(x0s)
         if x0n then
            local g = K.v2x or K.vx
            local list = barriers(g, X, K.v2x ~= nil)
            local lo, hi = nearest(list, x0n, -1), nearest(list, x0n, 1)
            -- starting at rest: only the side where v² > 0
            local G = K.v2x and function(x) return cas.n(cas.with(K.v2x, { { X, cas.num(x) } })) end
            if G and math.abs(G(x0n) or 1) < 1e-12 then
               local h = 1e-6 * math.max(1, math.abs(x0n))
               if (G(x0n + h) or -1) < 0 then hi = { e = x0s, closed = true } end
               if (G(x0n - h) or -1) < 0 then lo = { e = x0s, closed = true } end
            end
            local why
            if K.v2x then
               set_dom('v2x', interval(lo and lo.e, lo and lo.closed, X, hi and hi.e, hi and hi.closed),
                       'v' .. U.SQ .. ' ' .. U.GEQ .. ' 0')
            end
            -- moving away from x0 in the direction of v until the next barrier
            local vdir = K.vsign
            if not vdir and K.vx then
               local vv = cas.n(cas.with(K.vx, { { X, x0s } }))
               vdir = vv and (vv < 0 and -1 or 1)
            end
            if vdir then
               local d
               if vdir > 0 then
                  d = interval(x0s, true, X, hi and hi.e, hi and hi.closed)
               else
                  d = interval(lo and lo.e, lo and lo.closed, X, x0s, true)
               end
               why = 'moving ' .. (vdir > 0 and 'right' or 'left') .. ' from x = ' .. M(x0s)
               if kind ~= 'v(x)' then set_dom('vx', d, why) end
               set_dom('tx', d, why)
               if kind == 'v(x)' then set_dom('vx', d, why) set_dom('ax', d, why) end
            end
            for _, k in ipairs({ 'xt', 'vt' }) do set_dom(k, t_dom(K[k])) end
         end
      else
         -- given or derived in t
         for _, k in ipairs({ 'at', 'vt', 'xt' }) do set_dom(k, t_dom(K[k])) end
      end
   end)
   if not ok_dom then doms = {} end
   local dom_order = { 'xt', 'vt', 'at', 'tv', 'xv', 'v2x', 'vx', 'tx', 'ax' }
   local any = false
   for _, k in ipairs(dom_order) do if doms[k] then any = true end end
   if any then
      R:tag(nil)
      R:section('Domains')
      local labels = { xt = 'x(t)', vt = 'v(t)', at = 'a(t)', tv = 't(v)', xv = 'x(v)', vx = 'v(x)',
                       v2x = 'v' .. U.SQ .. '(x)', tx = 't(x)', ax = 'a(x)' }
      for _, k in ipairs(dom_order) do
         if doms[k] then
            R:tag(k)
            R:step(labels[k] .. ':  ' .. M(doms[k]) .. (dom_why[k] and ('  (' .. dom_why[k] .. ')') or ''))
            R:domain(k, doms[k])
         end
      end
   end

   -- Questions ---------------------------------------------------------------
   local find = I.find and U.trim(I.find) ~= '' and I.find or nil
   if find then
      local var, val = find:match('^%s*([txvaTXVA])%s*=%s*(.-)%s*$')
      if not var then
         R:note('Find: use t=3, v=0, x=5 or a=0', 'error')
      else
         var = var:lower()
         local value = U.read(val).val
         R:tag('q')
         R:section('When ' .. var .. ' = ' .. U.txt(value))
         local tmin = conds[1] and conds[1].t or '0'
         local function eval_at(e, v, at)
            return U.simp(cas.with(e, { { v, at } }))
         end
         local function report_at_t(tv)
            local parts = {}
            local xval
            if K.xt then
               xval = eval_at(K.xt, T, tv)
            elseif K.tx then
               -- moving in the direction of v from the known position
               local c = find_cond('t', 'x')
               local cons
               if c and K.vx then
                  local vc = cas.n(cas.with(K.vx, { { X, c.x } }))
                  local later = (cas.n(tv) or 0) >= (cas.n(c.t) or 0)
                  if vc and vc ~= 0 then
                     local up = (vc > 0) == later
                     cons = X .. (up and U.GEQ or U.LEQ) .. c.x
                  end
               end
               local sols = cas.solve(tv .. '=' .. K.tx, X, cons)
               if sols and #sols > 1 and c then
                  local xc = cas.n(c.x) or 0
                  table.sort(sols, function(p, q)
                     return math.abs((cas.n(p) or 1e300) - xc) < math.abs((cas.n(q) or 1e300) - xc)
                  end)
               end
               xval = sols and sols[1]
            end
            if xval then
               table.insert(parts, 'x ' .. U.eq(xval))
               R:result('x', xval, { key = 'q_x' })
            end
            local vval
            if K.vt then
               vval = eval_at(K.vt, T, tv)
            elseif K.vx and xval then
               vval = eval_at(K.vx, X, xval)
            end
            if vval then
               table.insert(parts, 'v ' .. U.eq(vval))
               R:result('v', vval, { key = 'q_v' })
            end
            local at = K.at or (K.vt and U.simp('derivative(' .. K.vt .. ',' .. T .. ')'))
            local aval
            if at then
               aval = eval_at(at, T, tv)
            elseif K.ax and xval then
               aval = eval_at(K.ax, X, xval)
            elseif K.av and vval then
               aval = eval_at(K.av, V, vval)
            end
            if aval then
               table.insert(parts, 'a ' .. U.eq(aval))
               R:result('a', aval, { key = 'q_a' })
            end
            if #parts > 0 then R:step('At t = ' .. M(tv) .. ':  ' .. table.concat(parts, ',  ')) end
         end
         local function times_where(e)
            local sols = cas.solve(e .. '=' .. value, T, T .. U.GEQ .. tmin)
            return U.expand_solutions(sols, cas.n(tmin) or 0, nil, 4)
         end

         if var == 't' then
            report_at_t(value)
         else
            local by_t = (var == 'x' and K.xt) or (var == 'v' and K.vt) or (var == 'a' and (K.at or K.vt))
            local e = by_t
            if var == 'a' and not K.at and K.vt then
               e = U.simp('derivative(' .. K.vt .. ',' .. T .. ')')
            end
            local done = false
            if e then
               local ts = times_where(e)
               if #ts > 0 then
                  R:step('Solve ' .. M(e .. '=' .. value) .. ' for t ' .. U.GEQ .. ' ' .. M(tmin) .. ':  t ' .. U.eq(ts[1]))
                  R:result('t', ts[1], { key = 'q_t' })
                  for k = 2, #ts do
                     R:step('also t ' .. U.eq(ts[k]))
                     R:result('t' .. k, ts[k], { key = 'q_t' .. k })
                  end
                  report_at_t(ts[1])
                  done = true
               end
            end
            if not done then
               -- relations in v and x
               if var == 'v' and K.tv then
                  local tv = eval_at(K.tv, V, value)
                  R:step('t = t(' .. M(value) .. ') ' .. U.eq(tv))
                  R:result('t', tv, { key = 'q_t' })
                  done = true
               end
               if var == 'v' and K.xv then
                  local xv = eval_at(K.xv, V, value)
                  R:step('x = x(' .. M(value) .. ') ' .. U.eq(xv))
                  R:result('x', xv, { key = 'q_x' })
                  done = true
               end
               if var == 'v' and K.av then
                  local av = eval_at(K.av, V, value)
                  R:step('a = a(' .. M(value) .. ') ' .. U.eq(av))
                  R:result('a', av, { key = 'q_a' })
                  done = true
               end
               if var == 'x' and (K.vx or K.v2x) then
                  if K.vx then
                     local vv = eval_at(K.vx, X, value)
                     R:step('v = v(' .. M(value) .. ') ' .. U.eq(vv))
                     R:result('v', vv, { key = 'q_v' })
                  else
                     local v2 = eval_at(K.v2x, X, value)
                     R:step('v' .. U.SQ .. ' = ' .. M(v2) .. ' ' .. U.IMPL .. ' v = ' .. U.PM .. M(U.ROOT .. '(' .. v2 .. ')'))
                     R:result('v', U.simp(U.ROOT .. '(' .. v2 .. ')'), { key = 'q_v' })
                  end
                  if K.ax then
                     local av = eval_at(K.ax, X, value)
                     R:step('a = a(' .. M(value) .. ') ' .. U.eq(av))
                     R:result('a', av, { key = 'q_a' })
                  end
                  if K.tx then
                     local tv = eval_at(K.tx, X, value)
                     R:step('t = t(' .. M(value) .. ') ' .. U.eq(tv))
                     R:result('t', tv, { key = 'q_t' })
                  end
                  done = true
               end
               if var == 'v' and K.vx and not done then
                  local sols = cas.solve(K.vx .. '=' .. value, X)
                  if sols and sols[1] then
                     R:step('Solve ' .. M(K.vx .. '=' .. value) .. ':  x ' .. U.eq(sols[1]))
                     R:result('x', sols[1], { key = 'q_x' })
                     done = true
                  end
               end
               if var == 'a' and K.av and not done then
                  local sols = cas.solve(K.av .. '=' .. value, V)
                  if sols and sols[1] then
                     local shown = {}
                     for k, sv in ipairs(sols) do
                        table.insert(shown, M(sv))
                        R:result('v', sv, { key = k == 1 and 'q_v' or ('q_v' .. k) })
                     end
                     R:step('Solve ' .. M(K.av .. '=' .. value) .. ':  v = ' .. table.concat(shown, ' or '))
                     done = true
                  end
               end
               if var == 'a' and K.ax and not done then
                  local sols = cas.solve(K.ax .. '=' .. value, X)
                  if sols and sols[1] then
                     R:step('Solve ' .. M(K.ax .. '=' .. value) .. ':  x ' .. U.eq(sols[1]))
                     R:result('x', sols[1], { key = 'q_x' })
                     done = true
                  end
               end
            end
            if not done then
               R:note('Not enough information to find when ' .. var .. ' = ' .. U.txt(value), 'warn')
            end
         end
      end
   end

   -- Displacement and distance between t1 and t2 ---------------------------------
   local t1, t2 = U.read(I.t1), U.read(I.t2)
   if t1 and t2 then
      R:tag('disp')
      R:section('From t = ' .. U.txt(t1.val) .. ' to t = ' .. U.txt(t2.val))
      if K.vt then
         local vd = dummy(K.vt, T, DT)
         local disp_expr = 'integral(' .. vd .. ',' .. DT .. ',' .. t1.val .. ',' .. t2.val .. ')'
         local disp = K.xt and U.simp(U.par(cas.with(K.xt, { { T, t2.val } })) .. '-' .. U.par(cas.with(K.xt, { { T, t1.val } })))
                      or U.simp(disp_expr)
         if K.xt then
            R:step('Displacement = x(' .. M(t2.val) .. ') - x(' .. M(t1.val) .. ') ' .. U.eq(disp))
         else
            R:step('Displacement = ' .. M(disp_expr) .. ' ' .. U.eq(disp))
         end
         R:result('displacement', disp, { key = 'disp' })

         -- turning points inside (t1, t2)
         local zs = cas.solve(K.vt .. '=0', T, T .. '>' .. t1.val .. ' and ' .. T .. '<' .. t2.val)
         local turns = {}
         for _, z in ipairs(U.expand_solutions(zs, t1.num, t2.num, 20)) do
            local n = cas.n(z)
            if n and n > (t1.num or -math.huge) + 1e-12 and n < (t2.num or math.huge) - 1e-12 then
               table.insert(turns, z)
            end
         end
         local dist
         if #turns > 0 then
            local tl = {}
            for _, z in ipairs(turns) do table.insert(tl, M(z)) end
            R:step('v = 0 at t = ' .. table.concat(tl, ', ') .. ' (changes direction)')
         end
         local dist_expr = 'integral(abs(' .. vd .. '),' .. DT .. ',' .. t1.val .. ',' .. t2.val .. ')'
         if K.xt and #turns > 0 then
            local pts = { t1.val }
            for _, z in ipairs(turns) do table.insert(pts, z) end
            table.insert(pts, t2.val)
            local parts = {}
            for k = 1, #pts - 1 do
               table.insert(parts, 'abs(' .. U.par(cas.with(K.xt, { { T, pts[k + 1] } })) .. '-' .. U.par(cas.with(K.xt, { { T, pts[k] } })) .. ')')
            end
            dist = U.simp(table.concat(parts, '+'))
         else
            dist = cas.eval(dist_expr)
            if not dist or not cas.n(dist) then
               dist = U.simp('nInt(abs(' .. vd .. '),' .. DT .. ',' .. t1.val .. ',' .. t2.val .. ')')
            end
         end
         R:step('Distance = ' .. M(dist_expr) .. ' ' .. U.eq(dist))
         R:result('distance', dist, { key = 'dist' })
         local dt = U.simp(U.par(t2.val) .. '-' .. U.par(t1.val))
         local avgv = U.simp(U.par(disp) .. '/' .. U.par(dt))
         local avgs = U.simp(U.par(dist) .. '/' .. U.par(dt))
         R:step('Average velocity = ' .. M('displacement/time') .. ' ' .. U.eq(avgv) .. ',  average speed ' .. U.eq(avgs))
         R:result('avg velocity', avgv, { key = 'avgv' })
         R:result('avg speed', avgs, { key = 'avgs' })
      elseif K.tx then
         R:note('Displacement over time needs v(t); use Find with t=...', 'warn')
      else
         R:note('Need v(t) for displacement over a time interval', 'warn')
      end
   end
end

return S
