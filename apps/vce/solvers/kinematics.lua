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
      { id = 'c2', label = 'also', hint = 'x(2)=5   v(1)=3   v=2,x=1' },
      { id = 'find', label = 'Find when', hint = 't=3   v=0   x=5   a=0' },
      { id = 't1', label = 'from t=', hint = 'displacement / distance' },
      { id = 't2', label = 'to t=', hint = '' },
   },
   example = { type = 'a(t)', f = '6t', t0 = '0', x0 = '1', v0 = '2', find = 't=2' },
}

local MAP = U.locals_map()

-- Parse 'x(2)=5', 'v(1)=3', 'v=2,x=1', 't=1,x=0' into {t=, x=, v=}
local function parse_cond(text)
   if not text or U.trim(text) == '' then return nil end
   local c = {}
   text = text:gsub(' when ', ','):gsub(' at ', ',')
   for _, part in ipairs(cas.split_top(text, ',')) do
      local var, arg, val = part:match('^%s*([txvTXV])%s*%((.-)%)%s*=%s*(.-)%s*$')
      if var then
         c.t = arg
         c[var:lower()] = val
      else
         var, val = part:match('^%s*([txvTXV])%s*=%s*(.-)%s*$')
         if var then c[var:lower()] = val end
      end
   end
   for k, v in pairs(c) do
      c[k] = U.read(v).val
   end
   return next(c) and c or nil
end

function S.solve(I, R)
   local kind = I.type or 'a(t)'
   if not I.f then
      R:note('Enter ' .. kind .. ' and any known values')
      return
   end
   local f = cas.input(I.f, MAP)
   local fv = U.simp(f)

   -- Known values -----------------------------------------------------------
   local conds = {}
   local x0, v0 = U.read(I.x0), U.read(I.v0)
   local t0 = U.read(I.t0)
   if x0 or v0 or t0 then
      table.insert(conds, { t = t0 and t0.val or ((x0 or v0) and '0' or nil),
                            x = x0 and x0.val, v = v0 and v0.val })
   end
   local c2 = parse_cond(I.c2)
   if c2 then table.insert(conds, c2) end

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
      for _, s in ipairs(sols) do
         local v = cas.n(cas.with(s, { { indep, a } }))
         if v and bn and math.abs(v - bn) < 1e-6 * (1 + math.abs(bn)) then
            return s
         end
      end
      return sols[1]
   end

   -- x(t) from v(t) by integration
   local function x_from_vt()
      if K.vt and not K.xt then
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
      R:step('dt/dx = 1/v')
      local tx = U.simp(U.par(c.t) .. '+integral(1/(' .. dummy(K.vx, X, DX) .. '),' .. DX .. ',' .. c.x .. ',' .. X .. ')')
      R:step('t = ' .. M(c.t) .. ' + ' .. M('integral(1/(' .. dummy(K.vx, X, DX) .. '),' .. DX .. ',' .. c.x .. ',' .. X .. ')') .. ' = ' .. M(tx))
      res('tx', 't(x)', tx)
      local sols = cas.solve(T .. '=' .. tx, X)
      local xt = pick(sols, T, c.t, c.x)
      if xt then
         R:step('Solve for x: x = ' .. M(xt))
         res('xt', 'x(t)', xt)
         K.vt = K.vt or U.simp('derivative(' .. xt .. ',' .. T .. ')')
         R:step('v = dx/dt = ' .. M(K.vt))
         R:result('v(t)', K.vt, { key = 'vt' })
      end
   end

   -- v(x) from v²(x) with the sign from the known motion
   local function v_from_v2x()
      if not K.v2x or K.vx then return end
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
   end

   -- Derivations by type -------------------------------------------------------
   if kind == 'x(t)' then
      show_given('x')
      res('xt', 'x(t)', fv)
      local vt = U.simp('derivative(' .. fv .. ',' .. T .. ')')
      R:step('v = dx/dt = ' .. M(vt))
      res('vt', 'v(t)', vt)
      local at = U.simp('derivative(' .. vt .. ',' .. T .. ')')
      R:step('a = dv/dt = ' .. M(at))
      res('at', 'a(t)', at)
   elseif kind == 'v(t)' then
      show_given('v')
      res('vt', 'v(t)', fv)
      local at = U.simp('derivative(' .. fv .. ',' .. T .. ')')
      R:step('a = dv/dt = ' .. M(at))
      res('at', 'a(t)', at)
      x_from_vt()
   elseif kind == 'a(t)' then
      show_given('a')
      res('at', 'a(t)', fv)
      local vt = integrate(fv, T, DT, 'v = v0 + ' .. U.INTG .. 'a dt', 'v(t)', 't', 'v')
      if vt then
         res('vt', 'v(t)', vt)
         x_from_vt()
      end
   elseif kind == 'v(x)' then
      show_given('v')
      res('vx', 'v(x)', fv)
      local ax = U.simp(U.par(fv) .. '*derivative(' .. fv .. ',' .. X .. ')')
      R:step('a = v' .. '\194\183' .. 'dv/dx = ' .. M(ax))
      res('ax', 'a(x)', ax)
      t_from_vx()
   elseif kind == 'v2(x)' then
      show_given('v' .. U.SQ)
      res('v2x', 'v' .. U.SQ .. '(x)', fv)
      local ax = U.simp('derivative(' .. fv .. ',' .. X .. ')/2')
      R:step('a = d/dx(' .. M('1/2*v^2') .. ') = ' .. M(ax))
      res('ax', 'a(x)', ax)
      v_from_v2x()
      if K.vx then t_from_vx() end
   elseif kind == 'a(x)' then
      show_given('a')
      res('ax', 'a(x)', fv)
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
      show_given('a')
      res('av', 'a(v)', fv)
      -- terminal (limiting) velocity: equilibrium approached from v0
      local roots = cas.solve(fv .. '=0', V)
      if roots and #roots > 0 then
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
         R:step('dv/dt = a ' .. U.IMPL .. ' dt/dv = 1/a')
         local tv = U.simp(U.par(c.t) .. '+integral(1/(' .. dummy(fv, V, DV) .. '),' .. DV .. ',' .. c.v .. ',' .. V .. ')')
         R:step('t = ' .. M(c.t) .. ' + ' .. M('integral(1/(' .. dummy(fv, V, DV) .. '),' .. DV .. ',' .. c.v .. ',' .. V .. ')') .. ' = ' .. M(tv))
         res('tv', 't(v)', tv)
         local sols = cas.solve(T .. '=' .. tv, V)
         local vt = pick(sols, T, c.t, c.v)
         if vt then
            R:step('Solve for v: v = ' .. M(vt))
            res('vt', 'v(t)', vt)
            local at = U.simp(cas.rename(fv, { [V] = U.par(vt) }, true))
            res('at', 'a(t)', at)
            x_from_vt()
         end
      end
      local cx = find_cond('x', 'v')
      if cx then
         R:step('v' .. '\194\183' .. 'dv/dx = a ' .. U.IMPL .. ' dx/dv = v/a')
         local xv = U.simp(U.par(cx.x) .. '+integral(' .. DV .. '/(' .. dummy(fv, V, DV) .. '),' .. DV .. ',' .. cx.v .. ',' .. V .. ')')
         R:step('x = ' .. M(cx.x) .. ' + ' .. M('integral(' .. DV .. '/(' .. dummy(fv, V, DV) .. '),' .. DV .. ',' .. cx.v .. ',' .. V .. ')') .. ' = ' .. M(xv))
         res('xv', 'x(v)', xv)
         local sols = cas.solve(X .. '=' .. xv, V)
         local vx = pick(sols, X, cx.x, cx.v)
         if vx then
            R:step('Solve for v: v = ' .. M(vx))
            res('vx', 'v(x)', vx)
         end
      end
      if not c and not cx then
         R:note('Enter v0 (and x0) to integrate', 'warn')
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
                     R:step('Solve ' .. M(K.av .. '=' .. value) .. ':  v ' .. U.eq(sols[1]))
                     R:result('v', sols[1], { key = 'q_v' })
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
