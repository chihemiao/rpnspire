-- Differential equation models (one screen, choose the type):
-- exponential growth/decay, Newton's law of cooling, logistic growth,
-- mixing tanks, general dy/dx = f(x, y) with Euler's method and slope
-- field, and related rates.
local cas = require 'apps.vce.cas'
local numeric = require 'apps.vce.numeric'
local fmt = require 'apps.vce.fmt'
local sym = require 'ti.sym'
local U = require 'apps.vce.solvers.util'

local M = U.M
local T = 'q9t'
local E = sym.EULER
local abs, max, min, floor = math.abs, math.max, math.min, math.floor

local TYPES = {
   { 'growth', 'growth/decay  dN/dt = kN' },
   { 'cooling', 'cooling  dT/dt = -k(T-Ts)' },
   { 'logistic', 'logistic  dP/dt = rP(1-P/K)' },
   { 'mixing', 'mixing tank (in/outflow)' },
   { 'general', 'dy/dx = f(x,y), Euler, slope field' },
   { 'related', 'related rates' },
}

local NAMES = { growth = 'N', cooling = 'T', logistic = 'P', mixing = 'Q' }

local function is(...)
   local set = {}
   for _, k in ipairs({ ... }) do set[k] = true end
   return function(I) return set[I.type or 'growth'] end
end

local function nm(I) return NAMES[I.type or 'growth'] or 'y' end

local S = {
   id = 'demodels',
   title = 'Differential equation models',
   short = 'DE models',
   group = 'Calculus',
   desc = 'Growth/decay, cooling, logistic, mixing, Euler & slope field, related rates',
   fields = {
      { id = 'type', label = 'Model', kind = 'choice', options = TYPES },
      -- growth / cooling / logistic / mixing
      { id = 'y0', label = function(I) return nm(I) .. '(0) =' end, hint = 'initial value',
        show = is('growth', 'cooling', 'logistic', 'mixing') },
      { id = 'k', label = function(I) return (I.type == 'logistic') and 'r =' or 'k =' end, hint = 'rate constant (if known)',
        show = is('growth', 'cooling', 'logistic') },
      { id = 'cap', label = function(I) return I.type == 'logistic' and 'K =' or 'Ts =' end,
        hint = 'carrying capacity / surrounding temp.', show = is('cooling', 'logistic') },
      { id = 't1', label = 't1 =', hint = 'time of a known value', show = is('growth', 'cooling', 'logistic') },
      { id = 'y1', label = function(I) return nm(I) .. '(t1) =' end, hint = 'value at t1 (finds k)',
        show = is('growth', 'cooling', 'logistic') },
      { id = 'half', label = 'half-life', hint = 'instead of k (decay)', show = is('growth') },
      { id = 'double', label = 'doubling', hint = 'doubling time (growth)', show = is('growth') },
      { id = 'V0', label = 'V(0) =', hint = 'initial volume', show = is('mixing') },
      { id = 'rin', label = 'rate in', hint = 'inflow rate (L/min)', show = is('mixing') },
      { id = 'cin', label = 'conc in', hint = 'concentration of inflow (kg/L)', show = is('mixing') },
      { id = 'rout', label = 'rate out', hint = 'outflow rate (L/min)', show = is('mixing') },
      -- general DE
      { id = 'f', label = 'dy/dx =', hint = 'x*y   x+y   y*(1-y)', show = is('general') },
      { id = 'x0', label = 'x0 =', hint = 'initial x', show = is('general') },
      { id = 'yg0', label = 'y(x0) =', hint = 'initial y', show = is('general') },
      { id = 'h', label = 'step h', hint = 'Euler step size', show = is('general') },
      { id = 'xn', label = 'Euler to x', hint = 'x value to approximate', show = is('general') },
      -- related rates
      { id = 'rel', label = 'Q =', hint = 'Q in terms of one variable, e.g. pi*h^2*10', show = is('related') },
      { id = 'given', label = 'Given', kind = 'choice', options = { { 'dQ', 'dQ/dt known' }, { 'dx', 'dx/dt known' } },
        show = is('related') },
      { id = 'rate', label = 'rate =', hint = 'value of the known rate', show = is('related') },
      { id = 'at', label = 'at =', hint = 'value of the variable', show = is('related') },
      -- queries
      { id = 'find', label = 'Find', hint = 't=5   or  N=200 (time)', show = is('growth', 'cooling', 'logistic', 'mixing') },
   },
   example = { type = 'growth', y0 = '100', t1 = '5', y1 = '150', find = 't=10' },
}

-- Plot spec for a solution y(t) over [0, tmax]
local function time_graph(Y, tmax, extras)
   local spec = { xmin = -0.05 * tmax, xmax = tmax * 1.05, curves = { { fn = Y } }, asymptotes = {}, points = {} }
   for _, p in ipairs(extras.points or {}) do table.insert(spec.points, p) end
   for _, a in ipairs(extras.asymptotes or {}) do table.insert(spec.asymptotes, a) end
   return spec
end

-- Handle 'find' for y(t) (exact CAS expression in T)
local function answer_find(I, R, yexpr, name, spec)
   if not I.find or U.trim(I.find) == '' then return end
   local var, val = I.find:match('^%s*(%a)%s*=%s*(.-)%s*$')
   if not var then
      R:note('Find: use t=5 or ' .. name .. '=200', 'error')
      return
   end
   local v = U.read(val).val
   R:section('Find')
   if var:lower() == 't' then
      local y = U.simp(cas.with(yexpr, { { T, v } }))
      R:step(name .. '(' .. M(v) .. ') ' .. U.eq(y))
      R:result(name .. '(' .. U.txt(v) .. ')', y, { key = 'q_y' })
      local tn, yn = cas.n(v), cas.n(y)
      if tn and yn then table.insert(spec.points, { x = tn, y = yn, kind = 'point', label = name .. '=' .. fmt.plain(fmt.round(yn, 2)) }) end
   else
      local sols = cas.solve(yexpr .. '=' .. v, T)
      local ts = U.expand_solutions(sols, 0, nil, 3)
      if #ts == 0 then
         local n = cas.nsolve(yexpr .. '=' .. v, T, 0, 1e4)
         if n then ts = { n } end
      end
      if #ts == 0 then
         R:note(name .. ' never equals ' .. U.txt(v), 'warn')
         return
      end
      R:step(M(yexpr .. '=' .. v) .. ' ' .. U.IMPL .. ' t ' .. U.eq(ts[1]))
      R:result('t when ' .. name .. '=' .. U.txt(v), ts[1], { key = 'q_t' })
      local tn, yn = cas.n(ts[1]), cas.n(v)
      if tn and yn then table.insert(spec.points, { x = tn, y = yn, kind = 'point', label = 't=' .. fmt.plain(fmt.round(tn, 2)) }) end
   end
end

local function solve_growth(I, R)
   local N0 = U.read(I.y0)
   if not N0 then
      R:note('Enter N(0) and k (or a second value, half-life or doubling time)')
      return
   end
   R:step('dN/dt = kN ' .. U.IMPL .. ' ' .. M('integral(1/N,N)') .. ' = ' .. M('integral(k,t)') .. ' ' .. U.IMPL
          .. ' ln|N| = kt + c ' .. U.IMPL .. ' N = ' .. M('A*' .. E .. '^(k*t)'))
   R:step('N(0) = ' .. M(N0.val) .. ' ' .. U.IMPL .. ' A = ' .. M(N0.val))
   local k
   if I.k then
      k = U.read(I.k).val
   elseif I.t1 and I.y1 then
      local t1, N1 = U.read(I.t1).val, U.read(I.y1).val
      k = U.simp('ln(' .. U.par(N1) .. '/' .. U.par(N0.val) .. ')/' .. U.par(t1))
      R:step('N(' .. M(t1) .. ') = ' .. M(N1) .. ' ' .. U.IMPL .. ' ' .. M(N0.val .. '*' .. E .. '^(' .. U.par(t1) .. '*k)=' .. N1)
             .. ' ' .. U.IMPL .. ' k = ' .. M('ln(' .. U.par(N1) .. '/' .. U.par(N0.val) .. ')/' .. U.par(t1)) .. ' ' .. U.eq(k))
   elseif I.half then
      local h = U.read(I.half).val
      k = U.simp(U.NEG .. 'ln(2)/' .. U.par(h))
      R:step('Half-life ' .. M(h) .. ': ' .. M(E .. '^(k*' .. U.par(h) .. ')=1/2') .. ' ' .. U.IMPL .. ' k = '
             .. M(U.NEG .. 'ln(2)/' .. U.par(h)) .. ' ' .. U.eq(k))
   elseif I.double then
      local d = U.read(I.double).val
      k = U.simp('ln(2)/' .. U.par(d))
      R:step('Doubling time ' .. M(d) .. ': ' .. M(E .. '^(k*' .. U.par(d) .. ')=2') .. ' ' .. U.IMPL .. ' k = '
             .. M('ln(2)/' .. U.par(d)) .. ' ' .. U.eq(k))
   else
      R:note('Enter k, or t1 and N(t1), or a half-life/doubling time')
      return
   end
   local Nt = U.simp(N0.val .. '*' .. E .. '^(' .. U.par(k) .. '*' .. T .. ')')
   R:step('N = ' .. M(Nt))
   R:result('k', k, { key = 'k' })
   R:result('N(t)', Nt, { key = 'yt' })
   local kn = cas.n(k)
   if kn and kn ~= 0 then
      local ch = U.simp('ln(2)/abs(' .. k .. ')')
      R:result(kn > 0 and 'doubling time' or 'half-life', ch, { key = kn > 0 and 'double' or 'half' })
      R:step((kn > 0 and 'Doubling time' or 'Half-life') .. ' = ' .. M('ln(2)/abs(k)') .. ' ' .. U.eq(ch))
   end
   local Y = numeric.compile_or_cas(Nt, { T })
   local tmax = (kn and kn ~= 0) and (3 / abs(kn)) or 10
   local spec = time_graph(Y, tmax, { points = { { x = 0, y = N0.num or 0, kind = 'point', label = 'N(0)' } } })
   if kn and kn < 0 then table.insert(spec.asymptotes, { kind = 'h', y = 0 }) end
   answer_find(I, R, Nt, 'N', spec)
   R.graph = spec
end

local function solve_cooling(I, R)
   local T0, Ts = U.read(I.y0), U.read(I.cap)
   if not (T0 and Ts) then
      R:note('Enter T(0), Ts and k (or a second reading)')
      return
   end
   R:step('dT/dt = ' .. U.NEG .. 'k(T ' .. U.NEG .. ' Ts) ' .. U.IMPL .. ' ' .. M('integral(1/(T-Ts),T)') .. ' = '
          .. M('integral(' .. U.NEG .. 'k,t)') .. ' ' .. U.IMPL .. ' T = ' .. M('Ts+A*' .. E .. '^(' .. U.NEG .. 'k*t)'))
   local A = U.simp(U.par(T0.val) .. '-' .. U.par(Ts.val))
   R:step('T(0) = ' .. M(T0.val) .. ' ' .. U.IMPL .. ' A = ' .. M(U.par(T0.val) .. '-' .. U.par(Ts.val)) .. ' ' .. U.eq(A))
   local k
   if I.k then
      k = U.read(I.k).val
   elseif I.t1 and I.y1 then
      local t1, T1 = U.read(I.t1).val, U.read(I.y1).val
      local kexpr = U.NEG .. 'ln((' .. T1 .. '-' .. U.par(Ts.val) .. ')/(' .. A .. '))/' .. U.par(t1)
      k = U.simp(kexpr)
      R:step('T(' .. M(t1) .. ') = ' .. M(T1) .. ' ' .. U.IMPL .. ' k = ' .. M(kexpr) .. ' ' .. U.eq(k))
   else
      R:note('Enter k, or t1 and T(t1)')
      return
   end
   local Tt = U.simp(U.par(Ts.val) .. '+' .. U.par(A) .. '*' .. E .. '^(' .. U.NEG .. U.par(k) .. '*' .. T .. ')')
   R:step('T = ' .. M(Tt) .. ',  T ' .. '\226\134\146' .. ' ' .. M(Ts.val) .. ' as t ' .. '\226\134\146' .. ' ' .. U.INF)
   R:result('k', k, { key = 'k' })
   R:result('T(t)', Tt, { key = 'yt' })
   local kn = cas.n(k)
   local Y = numeric.compile_or_cas(Tt, { T })
   local spec = time_graph(Y, (kn and kn > 0) and 4 / kn or 10,
      { asymptotes = { { kind = 'h', y = Ts.num or 0 } }, points = { { x = 0, y = T0.num or 0, kind = 'point', label = 'T(0)' } } })
   answer_find(I, R, Tt, 'T', spec)
   R.graph = spec
end

local function solve_logistic(I, R)
   local P0, K = U.read(I.y0), U.read(I.cap)
   if not (P0 and K) then
      R:note('Enter P(0), K and r (or a second value)')
      return
   end
   R:step('dP/dt = rP(1 ' .. U.NEG .. ' P/K) ' .. U.IMPL .. ' (partial fractions) ' .. M('integral(1/P+1/(K-P),P)')
          .. ' = rt + c ' .. U.IMPL .. ' P = ' .. M('K/(1+A*' .. E .. '^(' .. U.NEG .. 'r*t))'))
   local A = U.simp('(' .. K.val .. '-' .. U.par(P0.val) .. ')/' .. U.par(P0.val))
   R:step('P(0) = ' .. M(P0.val) .. ' ' .. U.IMPL .. ' A = ' .. M('(K-P(0))/P(0)') .. ' ' .. U.eq(A))
   local r
   if I.k then
      r = U.read(I.k).val
   elseif I.t1 and I.y1 then
      local t1, P1 = U.read(I.t1).val, U.read(I.y1).val
      local rexpr = U.NEG .. 'ln((' .. U.par(K.val) .. '/' .. U.par(P1) .. '-1)/' .. U.par(A) .. ')/' .. U.par(t1)
      r = U.simp(rexpr)
      R:step('P(' .. M(t1) .. ') = ' .. M(P1) .. ' ' .. U.IMPL .. ' r = ' .. M(rexpr) .. ' ' .. U.eq(r))
   else
      R:note('Enter r, or t1 and P(t1)')
      return
   end
   local Pt = U.simp(U.par(K.val) .. '/(1+' .. U.par(A) .. '*' .. E .. '^(' .. U.NEG .. U.par(r) .. '*' .. T .. '))')
   R:step('P = ' .. M(Pt) .. ',  P ' .. '\226\134\146' .. ' ' .. M(K.val) .. ' as t ' .. '\226\134\146' .. ' ' .. U.INF)
   R:result('r', r, { key = 'k' })
   R:result('P(t)', Pt, { key = 'yt' })
   -- fastest growth at P = K/2
   local An = cas.n(A)
   local spec_pts = { { x = 0, y = P0.num or 0, kind = 'point', label = 'P(0)' } }
   if An and An > 0 then
      local ti = U.simp('ln(' .. A .. ')/' .. U.par(r))
      local rate = U.simp(U.par(r) .. '*' .. U.par(K.val) .. '/4')
      R:step('Fastest growth when P = K/2 = ' .. M(U.simp(K.val .. '/2')) .. ' at t = ' .. M('ln(A)/r') .. ' ' .. U.eq(ti)
             .. ',  dP/dt = rK/4 ' .. U.eq(rate))
      R:result('t of fastest growth', ti, { key = 'tinf' })
      R:result('max dP/dt', rate, { key = 'maxrate' })
      local tn = cas.n(ti)
      if tn and K.num then table.insert(spec_pts, { x = tn, y = K.num / 2, kind = 'inflect', label = 'P=K/2' }) end
   end
   local rn = cas.n(r)
   local Y = numeric.compile_or_cas(Pt, { T })
   local tmax = (rn and rn > 0) and (2 * max(0, math.log(max(An or 1, 1))) + 6) / rn or 10
   local spec = time_graph(Y, tmax, { asymptotes = { { kind = 'h', y = K.num or 0 } }, points = spec_pts })
   answer_find(I, R, Pt, 'P', spec)
   R.graph = spec
end

local function solve_mixing(I, R)
   local Q0, V0 = U.read(I.y0), U.read(I.V0)
   local rin, cin, rout = U.read(I.rin), U.read(I.cin), U.read(I.rout)
   if not (Q0 and V0 and rin and cin and rout) then
      R:note('Enter Q(0), V(0), rate in, concentration in and rate out')
      return
   end
   local c = U.simp(U.par(rin.val) .. '-' .. U.par(rout.val))
   local Vt = U.simp(U.par(V0.val) .. '+' .. U.par(c) .. '*' .. T)
   local inflow = U.simp(U.par(rin.val) .. '*' .. U.par(cin.val))
   R:step('dQ/dt = (rate in)(conc in) ' .. U.NEG .. ' (rate out)' .. M('Q/V'))
   R:step('V = ' .. M('V(0)+(rin-rout)*t') .. ' = ' .. M(Vt))
   local de = U.simp(inflow .. '-' .. U.par(rout.val) .. '*q7q/(' .. Vt .. ')')
   R:step('dQ/dt = ' .. M(de))
   R:result('dQ/dt', de, { key = 'de' })
   local Qt
   local cn = cas.n(c)
   local base = U.simp(U.par(Q0.val) .. '-' .. U.par(cin.val) .. '*' .. U.par(V0.val))
   if cn and abs(cn) < 1e-12 then
      Qt = U.simp(U.par(cin.val) .. '*' .. U.par(V0.val) .. '+' .. U.par(base) .. '*' .. E .. '^(' .. U.NEG .. U.par(rout.val) .. '*' .. T .. '/' .. U.par(V0.val) .. ')')
      R:step('Constant volume: ' .. M('dQ/dt+' .. U.par(rout.val) .. '/' .. U.par(V0.val) .. '*Q=' .. inflow) .. ' '
             .. U.IMPL .. ' Q = ' .. M(Qt))
      R:step('As t ' .. '\226\134\146' .. ' ' .. U.INF .. ', Q ' .. '\226\134\146' .. ' ' .. M(U.simp(U.par(cin.val) .. '*' .. U.par(V0.val))))
      R:result('Q as t ' .. '\226\134\146' .. ' ' .. U.INF, U.simp(U.par(cin.val) .. '*' .. U.par(V0.val)), { key = 'qlim' })
   else
      local p = U.simp(U.par(rout.val) .. '/' .. U.par(c))
      Qt = U.simp(U.par(cin.val) .. '*(' .. Vt .. ')+' .. U.par(base) .. '*(' .. U.par(V0.val) .. '/(' .. Vt .. '))^' .. U.par(p))
      R:step('Integrating factor ' .. M('V^(rout/(rin-rout))') .. ' ' .. U.IMPL .. ' Q = ' .. M(Qt))
      if cn and cn < 0 then
         local tend = U.simp(U.par(V0.val) .. '/' .. U.par(U.simp(U.NEG .. U.par(c))))
         R:step('The tank is empty when V = 0: t = ' .. M(tend))
         R:result('tank empty at t', tend, { key = 'tend' })
      end
   end
   R:result('Q(t)', Qt, { key = 'yt' })
   local conc = U.simp('(' .. Qt .. ')/(' .. Vt .. ')')
   R:result('concentration Q/V', conc, { key = 'conc' })
   local Y = numeric.compile_or_cas(Qt, { T })
   local tmax
   if cn and cn < 0 then
      tmax = 0.98 * (V0.num or 1) / -cn
   else
      tmax = 4 * (V0.num or 1) / max(1e-9, rout.num or 1)
   end
   local extras = { points = { { x = 0, y = Q0.num or 0, kind = 'point', label = 'Q(0)' } } }
   if cn and abs(cn) < 1e-12 and cin.num and V0.num then
      extras.asymptotes = { { kind = 'h', y = cin.num * V0.num } }
   end
   local spec = time_graph(Y, tmax, extras)
   answer_find(I, R, Qt, 'Q', spec)
   R.graph = spec
end

local function solve_general(I, R)
   if not I.f then
      R:note('Enter dy/dx = f(x, y)')
      return
   end
   local map = U.locals_map()
   local f = U.simp(cas.input(I.f, map))
   local X, Y = 'q9x', 'q9y'
   local Fxy = numeric.compile_or_cas(f, { X, Y })
   R:step('dy/dx = ' .. M(f))
   local spec = { field = { fn = Fxy }, curves = {}, points = {} }
   local x0, y0 = U.read(I.x0), U.read(I.yg0)
   local xn = U.read(I.xn)
   local h = U.read(I.h)
   local xs = { x0 and x0.num, xn and xn.num }
   local lo, hi = 1e300, -1e300
   for _, v in ipairs(xs) do if v then lo, hi = min(lo, v), max(hi, v) end end
   if lo > hi then lo, hi = -5, 5 end
   if hi - lo < 1 then lo, hi = lo - 2, hi + 2 end
   local pad = (hi - lo) * 0.3
   spec.xmin, spec.xmax = lo - pad, hi + pad

   if not (x0 and y0) then
      R:note('Enter x0 and y(x0) for a particular solution and Euler\'s method')
      R.graph = spec
      return
   end

   -- exact solution (CAS)
   local exact
   local res = cas.eval('deSolve(' .. Y .. "'=" .. f .. ' and ' .. Y .. '(' .. x0.val .. ')=' .. y0.val .. ',' .. X .. ',' .. Y .. ')')
   local sols = res and cas.solutions(res, Y)
   if sols and sols[1] and not sols[1]:find('@', 1, true) then
      exact = sols[1]
      R:step('Solve the DE with ' .. M('y(' .. x0.val .. ')=' .. y0.val) .. ': y = ' .. M(exact))
      R:result('y(x)', exact, { key = 'yx' })
      local Ex = numeric.compile_or_cas(exact, { X })
      table.insert(spec.curves, { fn = Ex })
   end

   -- Euler's method
   if h and xn and h.num and h.num ~= 0 then
      local n = floor((xn.num - x0.num) / h.num + 0.5)
      if n < 1 or n > 2000 then
         R:note('Euler: (x - x0)/h must give 1 to 2000 steps', 'error')
      else
         R:section('Euler' .. "'" .. 's method, h = ' .. U.txt(h.val))
         R:step('y(n+1) = y(n) + h' .. sym.CDOT .. 'f(x(n), y(n))')
         local xv, yv = x0.num, y0.num
         local pts = { { xv, yv } }
         for i = 1, n do
            local slope = Fxy(xv, yv)
            if not slope then
               R:note('f(x, y) undefined at step ' .. i, 'error')
               break
            end
            local ny = yv + h.num * slope
            if i <= 4 or i == n then
               R:step(string.format('x%d = %s:  y%d = %s + %s' .. sym.CDOT .. '%s = %s', i, fmt.plain(fmt.round(xv + h.num, 6)), i,
                  fmt.plain(fmt.round(yv, 6)), fmt.plain(fmt.round(h.num, 6)), fmt.plain(fmt.round(slope, 6)), fmt.plain(fmt.round(ny, 6))))
            elseif i == 5 then
               R:step('...')
            end
            xv, yv = x0.num + i * h.num, ny
            table.insert(pts, { xv, yv })
         end
         R:result('Euler y(' .. U.txt(xn.val) .. ')', cas.num(yv), { key = 'euler' })
         table.insert(spec.curves, { pts = pts, dots = true, line = true, color = 0xD2691E })
         if exact then
            local ev = cas.n(cas.with(exact, { { X, xn.val } }))
            if ev then
               R:step('Exact y(' .. M(xn.val) .. ') ' .. U.APPROX .. ' ' .. U.D(ev) .. ',  error ' .. U.APPROX .. ' ' .. U.D(abs(ev - yv)))
               R:result('exact y(' .. U.txt(xn.val) .. ')', cas.num(ev), { key = 'exact_y' })
            end
         end
      end
   end
   table.insert(spec.points, { x = x0.num, y = y0.num, kind = 'point', label = '(x0, y0)' })
   R.graph = spec
end

local function solve_related(I, R)
   if not (I.rel and I.rate and I.at) then
      R:note('Enter Q in terms of one variable, the known rate and the value')
      return
   end
   local map = U.locals_map()
   local q = U.simp(cas.input(I.rel, map))
   local vars = {}
   for _, u in ipairs(U.unknowns(q)) do table.insert(vars, u) end
   if #vars ~= 1 then
      R:note('Q must depend on exactly one variable', 'error')
      return
   end
   local v = vars[1]
   local vn = cas.display_name(v)
   local rate, at = U.read(I.rate).val, U.read(I.at).val
   local dq = U.simp('derivative(' .. q .. ',' .. v .. ')')
   local dqa = U.simp(cas.with(dq, { { v, at } }))
   R:step('Q = ' .. M(q) .. ' ' .. U.IMPL .. ' dQ/d' .. vn .. ' = ' .. M(dq))
   R:step('At ' .. vn .. ' = ' .. M(at) .. ': dQ/d' .. vn .. ' ' .. U.eq(dqa))
   R:result('dQ/d' .. vn, dqa, { key = 'dq' })
   if (I.given or 'dQ') == 'dQ' then
      local res = U.simp(U.par(rate) .. '/' .. U.par(dqa))
      R:step('dQ/dt = dQ/d' .. vn .. sym.CDOT .. 'd' .. vn .. '/dt ' .. U.IMPL .. ' d' .. vn .. '/dt = '
             .. M('(dQ/dt)/(dQ/d' .. vn .. ')') .. ' = ' .. M(U.par(rate) .. '/' .. U.par(dqa)) .. ' ' .. U.eq(res))
      R:result('d' .. vn .. '/dt', res, { key = 'rate' })
   else
      local res = U.simp(U.par(dqa) .. '*' .. U.par(rate))
      R:step('dQ/dt = dQ/d' .. vn .. sym.CDOT .. 'd' .. vn .. '/dt = ' .. M(U.par(dqa) .. '*' .. U.par(rate)) .. ' ' .. U.eq(res))
      R:result('dQ/dt', res, { key = 'rate' })
   end
   local Qf = numeric.compile_or_cas(q, { v })
   local atn = cas.n(at) or 1
   local span = max(1, abs(atn) * 1.5)
   R.graph = { xmin = min(0, atn - span), xmax = atn + span, curves = { { fn = Qf } },
               points = { { x = atn, y = Qf(atn) or 0, kind = 'point', label = vn .. '=' .. fmt.plain(fmt.round(atn, 2)) } } }
end

function S.solve(I, R)
   local kind = I.type or 'growth'
   if kind == 'growth' then return solve_growth(I, R) end
   if kind == 'cooling' then return solve_cooling(I, R) end
   if kind == 'logistic' then return solve_logistic(I, R) end
   if kind == 'mixing' then return solve_mixing(I, R) end
   if kind == 'general' then return solve_general(I, R) end
   if kind == 'related' then return solve_related(I, R) end
end

return S
