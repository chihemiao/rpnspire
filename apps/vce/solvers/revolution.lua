-- Areas, volumes of revolution, arc length and surface area for
-- y = f(x), x = g(y) or parametric curves, with a shaded graph.
local cas = require 'apps.vce.cas'
local numeric = require 'apps.vce.numeric'
local U = require 'apps.vce.solvers.util'

local M = U.M
local PI = '\207\128'
local abs, max, min = math.abs, math.max, math.min

-- '= value' (or '= ?' when it could not be found)
local function EQ(v)
   return v and U.eq(v) or '= ?'
end

local has_constants -- defined with the inputs below

local TYPES = { { 'y', 'y = f(x)' }, { 'x', 'x = g(y)' }, { 'param', 'parametric x(t), y(t)' } }

local S = {
   id = 'revolution',
   title = 'Area, volume, arc length, surface area',
   short = 'Area/volume',
   group = 'Calculus',
   desc = 'y=f(x), x=g(y) or parametric: area, solid of revolution, arc length, surface area',
   fields = {
      { id = 'type', label = 'Curve', kind = 'choice', options = TYPES },
      { id = 'f', label = function(I)
           local t = I.type or 'y'
           return t == 'x' and 'x = g(y)' or (t == 'param' and 'x(t) =' or 'y = f(x)')
        end, hint = 'x^2   sqrt(x)   2cos(t)' },
      { id = 'g', label = function(I)
           local t = I.type or 'y'
           return t == 'x' and 'inner x =' or (t == 'param' and 'y(t) =' or 'lower y =')
        end, hint = 'optional second curve (between curves)' },
      -- y = f(x) with limits given as y values (region beside the y-axis)
      { id = 'lim', label = 'Limits are', kind = 'choice', options = { { 'x', 'x values' }, { 'y', 'y values' } },
        show = function(I) return (I.type or 'y') == 'y' end },
      { id = 'a', label = function(I)
           local t = I.type or 'y'
           return (t == 'x' and 'y' or (t == 'param' and 't' or (I.lim == 'y' and 'y' or 'x'))) .. ' from'
        end, hint = 'lower limit (a letter such as a is fine)' },
      { id = 'b', label = function(I)
           local t = I.type or 'y'
           return (t == 'x' and 'y' or (t == 'param' and 't' or (I.lim == 'y' and 'y' or 'x'))) .. ' to'
        end, hint = 'upper limit' },
      { id = 'axis', label = 'Rotate about', kind = 'choice', options = { { 'x', 'x-axis' }, { 'y', 'y-axis' } } },
      -- with a letter (e.g. a): a known volume or area finds it
      { id = 'known', label = 'given', hint = 'V=16pi   or   A=4   (finds a)',
        show = function(I) return has_constants(I) end },
   },
   example = { type = 'y', f = 'sqrt(x)', a = '0', b = '4', axis = 'x' },
}

-- Integrate exactly when possible, otherwise numerically.
-- Returns value string, display integral, numeric flag
local function integrate(e, var, a, b, R)
   local disp = 'integral(' .. e .. ',' .. var .. ',' .. a .. ',' .. b .. ')'
   local res = cas.eval(disp)
   if res and not res:find('integral(', 1, true) and cas.n(res) then
      return res, disp, false
   end
   res = cas.eval('nInt(' .. e .. ',' .. var .. ',' .. a .. ',' .. b .. ')')
   if res and cas.n(res) then return res, disp, true end
   -- last resort: Simpson in Lua
   local f = numeric.compile(e, { var })
   local an, bn = cas.n(a), cas.n(b)
   if f and an and bn then
      local v = numeric.integrate(f, an, bn, 200)
      if v then return cas.num(v), disp, true end
   end
   if R then R:note('Could not integrate ' .. e, 'warn') end
   return nil, disp, true
end

-- Split [a, b] at zeros of e (for areas with sign changes)
local function split_points(e, var, a, b)
   local an, bn = cas.n(a), cas.n(b)
   local pts = { a }
   local sols = cas.solve(e .. '=0', var, var .. '>' .. a .. ' and ' .. var .. '<' .. b)
   for _, s in ipairs(U.expand_solutions(sols, an, bn, 20)) do
      local v = cas.n(s)
      if v and v > an + 1e-12 and v < bn - 1e-12 then table.insert(pts, s) end
   end
   table.insert(pts, b)
   return pts
end

-- Sign of e on [a, b]: 1 (>= 0), -1 (<= 0) or 0 (changes)
local function sign_on(f, a, b)
   local pos, neg = false, false
   for i = 0, 40 do
      local v = f(a + (b - a) * i / 40)
      if v and v > 1e-12 then pos = true end
      if v and v < -1e-12 then neg = true end
   end
   if pos and neg then return 0 end
   return neg and -1 or 1
end

local VARS = { y = 'q9x', x = 'q9y', param = 'q9t' }
local NAMES = { y = 'x', x = 'y', param = 't' }

-- Everything with number limits: areas, volumes, arc length, surface area, graph
local function solve_numeric(R, kind, f, g, a, b, axis)
   local var, vname = VARS[kind], NAMES[kind]
   local an, bn = cas.n(a), cas.n(b)
   if not (an and bn) or bn <= an then
      R:note('The lower limit must be less than the upper limit', 'error')
      return
   end
   local F = numeric.compile_or_cas(f, { var })
   local G = g and numeric.compile_or_cas(g, { var }) or nil
   local spec = { curves = {}, shade = {}, vlines = {}, hlines = {}, axis = axis }

   local function result(label, key, value)
      if value then
         R:result(label, value, { key = key })
      end
   end

   if kind == 'param' then
      -- Parametric curve --------------------------------------------------------
      local x, y = f, g
      local dx = U.simp('derivative(' .. x .. ',' .. var .. ')')
      local dy = U.simp('derivative(' .. y .. ',' .. var .. ')')
      R:step('x = ' .. M(x) .. ',  y = ' .. M(y) .. ',  ' .. M(a) .. ' ' .. U.LEQ .. ' t ' .. U.LEQ .. ' ' .. M(b))
      R:step('dx/dt = ' .. M(dx) .. ',  dy/dt = ' .. M(dy))
      local FX, FY = F, G

      local speed = U.ROOT .. '((' .. dx .. ')^2+(' .. dy .. ')^2)'
      local L, Ld = integrate(speed, var, a, b, R)
      R:section('Arc length')
      R:step('L = ' .. M(Ld) .. ' ' .. EQ(L))
      result('arc length', 'len', L)

      R:section('Area')
      local ae = '(' .. y .. ')*(' .. dx .. ')'
      local A, Ad = integrate(ae, var, a, b, R)
      if A then
         local An = cas.n(A)
         R:step('A = ' .. M('abs(' .. Ad .. ')') .. ' ' .. U.eq(An and An < 0 and U.simp(U.NEG .. U.par(A)) or A))
         result('area', 'area', An and An < 0 and U.simp(U.NEG .. U.par(A)) or A)
      end

      R:section('Volume')
      local ve, vlabel
      if axis == 'x' then
         ve = PI .. '*(' .. y .. ')^2*(' .. dx .. ')'
         vlabel = 'V = ' .. M(PI .. '*integral(y^2*dx/dt,t,' .. a .. ',' .. b .. ')')
      else
         ve = PI .. '*(' .. x .. ')^2*(' .. dy .. ')'
         vlabel = 'V = ' .. M(PI .. '*integral(x^2*dy/dt,t,' .. a .. ',' .. b .. ')')
      end
      local V = integrate(ve, var, a, b, R)
      if V then
         local Vn = cas.n(V)
         if Vn and Vn < 0 then V = U.simp(U.NEG .. U.par(V)) end
         R:step(vlabel .. ' ' .. U.eq(V))
         result('volume about ' .. axis .. '-axis', 'vol', V)
      end

      R:section('Surface area')
      local radius = axis == 'x' and y or x
      local Rf = axis == 'x' and FY or FX
      local sgn = sign_on(Rf, an, bn)
      local rad = sgn == 0 and ('abs(' .. radius .. ')') or (sgn < 0 and (U.NEG .. '(' .. radius .. ')') or ('(' .. radius .. ')'))
      local SA, SAd = integrate('2*' .. PI .. '*' .. rad .. '*' .. speed, var, a, b, R)
      R:step('S = ' .. M(SAd) .. ' ' .. EQ(SA))
      result('surface area about ' .. axis .. '-axis', 'sa', SA)

      table.insert(spec.curves, { kind = 'param', fx = FX, fy = FY, tmin = an, tmax = bn })
      -- window from the curve
      local xl, xh, yl, yh = 1e300, -1e300, 1e300, -1e300
      for i = 0, 100 do
         local t = an + (bn - an) * i / 100
         local xv, yv = FX(t), FY(t)
         if xv and yv then
            xl, xh, yl, yh = min(xl, xv), max(xh, xv), min(yl, yv), max(yh, yv)
         end
      end
      if xl < xh then
         local px, py = max(0.5, (xh - xl) * 0.2), max(0.5, (yh - yl) * 0.2)
         spec.xmin, spec.xmax = min(xl - px, -px / 2), max(xh + px, px / 2)
         spec.ymin, spec.ymax = min(yl - py, -py / 2), max(yh + py, py / 2)
      else
         spec.xmin, spec.xmax = -5, 5
      end
      R.graph = spec
      return
   end

   -- y = f(x) or x = g(y) -----------------------------------------------------------
   local d = U.simp('derivative(' .. f .. ',' .. var .. ')')
   local dname = kind == 'x' and 'dx/dy' or 'dy/dx'
   local other = kind == 'x' and 'x' or 'y'
   R:step(other .. ' = ' .. M(f) .. (g and (',  second curve ' .. other .. ' = ' .. M(g)) or '')
          .. ',  ' .. M(a) .. ' ' .. U.LEQ .. ' ' .. vname .. ' ' .. U.LEQ .. ' ' .. M(b))
   R:step(dname .. ' = ' .. M(d))

   -- Area
   R:section('Area')
   local diff = g and ('(' .. f .. ')-(' .. g .. ')') or f
   local pts = split_points(diff, var, a, b)
   if #pts == 2 then
      local A, Ad = integrate(diff, var, a, b, R)
      if A then
         local An = cas.n(A)
         local Aabs = (An and An < 0) and U.simp(U.NEG .. U.par(A)) or A
         R:step('A = ' .. M(Ad) .. ' ' .. U.eq(A) .. ((An and An < 0) and ' (below the axis: area = ' .. M(Aabs) .. ')' or ''))
         result('area', 'area', Aabs)
      end
   else
      local parts, total = {}, {}
      for i = 1, #pts - 1 do
         local Ai, Aid = integrate(diff, var, pts[i], pts[i + 1], R)
         if Ai then
            local An = cas.n(Ai)
            table.insert(parts, (An and An < 0) and (U.NEG .. Aid) or Aid)
            table.insert(total, (An and An < 0) and ('-' .. U.par(Ai)) or ('+' .. U.par(Ai)))
         end
      end
      local A = U.simp('0' .. table.concat(total))
      local cross = {}
      for i = 2, #pts - 1 do table.insert(cross, M(pts[i])) end
      R:step((g and 'Curves cross' or 'Curve crosses the axis') .. ' at ' .. vname .. ' = ' .. table.concat(cross, ', '))
      R:step('A = ' .. M(table.concat(parts, '+')) .. ' ' .. U.eq(A))
      result('area', 'area', A)
      local signed = integrate(diff, var, a, b)
      if signed then result('signed integral', 'area_signed', signed) end
   end

   -- Volume
   R:section('Volume')
   local same_axis = (kind == 'y' and axis == 'x') or (kind == 'x' and axis == 'y')
   if same_axis then
      local ve = g and (PI .. '*abs((' .. f .. ')^2-(' .. g .. ')^2)') or (PI .. '*(' .. f .. ')^2')
      if g then
         local sg = sign_on(function(t)
            local p, q = F(t), G(t)
            return p and q and (p * p - q * q)
         end, an, bn)
         if sg ~= 0 then
            ve = PI .. '*' .. (sg < 0 and U.NEG or '') .. '((' .. f .. ')^2-(' .. g .. ')^2)'
         end
      end
      local V, Vd = integrate(ve, var, a, b, R)
      local formula = g and (PI .. '*integral(' .. other .. '1^2-' .. other .. '2^2,' .. vname .. ',' .. a .. ',' .. b .. ')')
                       or (PI .. '*integral(' .. other .. '^2,' .. vname .. ',' .. a .. ',' .. b .. ')')
      R:step('V = ' .. M(formula) .. ' = ' .. M(Vd) .. ' ' .. EQ(V))
      result('volume about ' .. axis .. '-axis', 'vol', V)
   else
      -- rotating about the other axis
      local ovar = kind == 'y' and 'q9y' or 'q9x'
      local oname = kind == 'y' and 'y' or 'x'
      local fa = U.simp(cas.with(f, { { var, a } }))
      local fb = U.simp(cas.with(f, { { var, b } }))
      local fan, fbn = cas.n(fa), cas.n(fb)
      -- (1) inverse function: region between the curve and the axis of rotation
      local inv
      if not g and fan and fbn and abs(fan - fbn) > 1e-12 then
         local sols = cas.solve(ovar .. '=' .. f, var)
         local mid = (fan + fbn) / 2
         for _, sx in ipairs(sols or {}) do
            local v = cas.n(cas.with(sx, { { ovar, cas.num(mid) } }))
            if v and v >= min(an, bn) - 1e-9 and v <= max(an, bn) + 1e-9 then
               inv = sx
               break
            end
         end
      end
      if inv then
         local lo, hi = fa, fb
         if fan > fbn then lo, hi = fb, fa end
         R:step(vname .. ' = ' .. M(inv) .. ',  ' .. M(lo) .. ' ' .. U.LEQ .. ' ' .. oname .. ' ' .. U.LEQ .. ' ' .. M(hi))
         local V, Vd = integrate(PI .. '*(' .. inv .. ')^2', ovar, lo, hi, R)
         R:step('Region between the curve and the ' .. axis .. '-axis: V = ' .. M(PI .. '*integral(' .. vname .. '^2,' .. oname .. ',' .. lo .. ',' .. hi .. ')')
                .. ' = ' .. M(Vd) .. ' ' .. EQ(V))
         result('volume about ' .. axis .. '-axis', 'vol', V)
      end
      -- (2) shells: region between the curve(s) and the other axis
      local h = g and ('abs((' .. f .. ')-(' .. g .. '))') or ('abs(' .. f .. ')')
      local sg = sign_on(F, an, bn)
      if not g and sg ~= 0 then h = sg < 0 and (U.NEG .. '(' .. f .. ')') or ('(' .. f .. ')') end
      local rsg = sign_on(function(t) return t end, an, bn)
      local r = rsg == 0 and ('abs(' .. var .. ')') or (rsg < 0 and (U.NEG .. var) or var)
      local Vs, Vsd = integrate('2*' .. PI .. '*' .. r .. '*' .. h, var, a, b, R)
      R:step('Region between the curve and the ' .. (axis == 'x' and 'y' or 'x') .. '-axis (shells): V = '
             .. M(Vsd) .. ' ' .. EQ(Vs))
      result('volume (shells) about ' .. axis .. '-axis', 'vol_shell', Vs)
   end

   -- Arc length
   R:section('Arc length')
   local integrand = U.ROOT .. '(1+(' .. d .. ')^2)'
   local L, Ld = integrate(integrand, var, a, b, R)
   R:step('L = ' .. M('integral(' .. U.ROOT .. '(1+(' .. dname .. ')^2),' .. vname .. ',' .. a .. ',' .. b .. ')')
          .. ' = ' .. M(Ld) .. ' ' .. EQ(L))
   result('arc length', 'len', L)

   -- Surface area
   R:section('Surface area')
   local radius, rf
   if same_axis then
      radius, rf = f, F
   else
      radius, rf = var, function(t) return t end
   end
   local sg = sign_on(rf, an, bn)
   local rad = sg == 0 and ('abs(' .. radius .. ')') or (sg < 0 and (U.NEG .. '(' .. radius .. ')') or ('(' .. radius .. ')'))
   local SA, SAd = integrate('2*' .. PI .. '*' .. rad .. '*' .. integrand, var, a, b, R)
   local rname = same_axis and other or vname
   R:step('S = ' .. M('2*' .. PI .. '*integral(' .. rname .. '*' .. U.ROOT .. '(1+(' .. dname .. ')^2),' .. vname .. ',' .. a .. ',' .. b .. ')')
          .. ' = ' .. M(SAd) .. ' ' .. EQ(SA))
   result('surface area about ' .. axis .. '-axis', 'sa', SA)

   -- Graph
   local w = bn - an
   if kind == 'y' then
      spec.xmin, spec.xmax = an - 0.25 * w, bn + 0.25 * w
      if spec.xmin > 0 and spec.xmin < w then spec.xmin = -0.1 * w end
      table.insert(spec.curves, { fn = F })
      if G then table.insert(spec.curves, { fn = G }) end
      table.insert(spec.shade, { kind = 'x', top = F, bottom = G, a = an, b = bn })
      table.insert(spec.vlines, { x = an })
      table.insert(spec.vlines, { x = bn })
   else
      spec.ymin, spec.ymax = an - 0.25 * w, bn + 0.25 * w
      if spec.ymin > 0 and spec.ymin < w then spec.ymin = -0.1 * w end
      local xl, xh = 0, 0
      for i = 0, 100 do
         local v = F(an + w * i / 100)
         if v then xl, xh = min(xl, v), max(xh, v) end
         local v2 = G and G(an + w * i / 100)
         if v2 then xl, xh = min(xl, v2), max(xh, v2) end
      end
      local pad = max(0.5, (xh - xl) * 0.25)
      spec.xmin, spec.xmax = xl - pad, xh + pad
      table.insert(spec.curves, { kind = 'x', fn = F, ymin = spec.ymin, ymax = spec.ymax })
      if G then table.insert(spec.curves, { kind = 'x', fn = G, ymin = spec.ymin, ymax = spec.ymax }) end
      table.insert(spec.shade, { kind = 'y', right = F, left = G, a = an, b = bn })
      table.insert(spec.hlines, { y = an })
      table.insert(spec.hlines, { y = bn })
   end
   R.graph = spec
end

-- Inputs ---------------------------------------------------------------------------

local MAP = U.locals_map()
local AXES = { q9x = true, q9y = true, q9t = true }

local function read(text)
   return text and cas.input(text, MAP, false, true)
end

-- A limit typed as 'y=1' or 'x=0': the letter says which variable it is in
local function split_limit(text)
   local v, rest = (text or ''):match('^%s*([xyXY])%s*=%s*(.-)%s*$')
   if v then return rest, v:lower() end
   return text
end

-- kind, f, g, a, b (CAS text) and the variable of the limits ('x' or 'y')
local function inputs(I)
   local kind = I.type or 'y'
   local at, av = split_limit(I.a)
   local bt, bv = split_limit(I.b)
   local lim = kind == 'y' and (av or bv or I.lim) or nil
   return kind, read(I.f), read(I.g), read(at), read(bt), lim == 'y' and 'y' or 'x'
end

-- Letters other than x, y, t: constants such as a or k, sorted
local function constants_of(list)
   local set, out = {}, {}
   for _, e in ipairs(list) do
      for _, u in ipairs(U.unknowns(e or '0')) do
         if not AXES[u] and not set[u] then
            set[u] = true
            table.insert(out, u)
         end
      end
   end
   table.sort(out)
   return out
end

has_constants = function(I)
   local ok, n = pcall(function()
      local _, f, g, a, b = inputs(I)
      return #constants_of({ f or '0', g or '0', a or '0', b or '0' })
   end)
   return ok and n > 0
end

local function names_of(consts)
   local t = {}
   for _, c in ipairs(consts) do table.insert(t, cas.display_name(c)) end
   return table.concat(t, ', ')
end

-- Limits in y for y = f(x) -----------------------------------------------------------

-- x = g(y) from y = f(x): the branch that is real at ytest, x >= 0 if possible
local function inverse(f, ytest)
   local sols = cas.solve('q9y=' .. f, 'q9x')
   local best, best_score
   for _, sx in ipairs(sols or {}) do
      if not cas.uses(sx, { 'q9x' }) then
         local v = cas.n(cas.with(sx, { { 'q9y', ytest } }))
         local score = v and (v >= -1e-12 and 2 or 1) or 0
         if score > 0 and (not best or score > best_score) then best, best_score = sx, score end
      end
   end
   return best
end

-- When x cannot be written in terms of y: substitute y = f(x), dy = f'(x) dx
-- (region between the curve and the y-axis from y = a to y = b)
local function by_substitution(R, f, a, b, axis)
   local an, bn = cas.n(a), cas.n(b)
   if not (an and bn) or bn <= an then
      R:note('The lower limit must be less than the upper limit', 'error')
      return
   end
   local function x_at(y)
      local sols = cas.solve(f .. '=' .. U.par(y), 'q9x')
      local list = U.expand_solutions(sols, nil, nil, 10)
      local neg
      for _, sx in ipairs(list) do
         local v = cas.n(sx)
         if v and v >= -1e-12 then return sx end
         neg = sx
      end
      return neg
   end
   local x1, x2 = x_at(a), x_at(b)
   if not (x1 and x2) then
      R:note('Could not find x where y = ' .. U.txt(x1 and b or a), 'error')
      return
   end
   local d = U.simp('derivative(' .. f .. ',q9x)')
   R:step('y = ' .. M(f) .. ',  dy = ' .. M(d) .. ' dx')
   R:step('y = ' .. M(a) .. ' ' .. U.IMPL .. ' x = ' .. M(x1) .. ',  y = ' .. M(b) .. ' ' .. U.IMPL .. ' x = ' .. M(x2))
   local function absval(v)
      local n = v and cas.n(v)
      return (n and n < 0) and U.simp(U.NEG .. U.par(v)) or v
   end
   R:section('Area')
   local A, Ad = integrate('q9x*(' .. d .. ')', 'q9x', x1, x2, R)
   R:step('A = ' .. M('integral(x,y,' .. a .. ',' .. b .. ')') .. ' = ' .. M(Ad) .. ' ' .. EQ(absval(A)))
   if A then R:result('area', absval(A), { key = 'area' }) end
   R:section('Volume')
   if axis == 'y' then
      local V, Vd = integrate(PI .. '*q9x^2*(' .. d .. ')', 'q9x', x1, x2, R)
      R:step('V = ' .. M(PI .. '*integral(x^2,y,' .. a .. ',' .. b .. ')') .. ' = ' .. M(Vd) .. ' ' .. EQ(absval(V)))
      if V then R:result('volume about y-axis', absval(V), { key = 'vol' }) end
   else
      local V, Vd = integrate('2*' .. PI .. '*(' .. f .. ')*q9x*(' .. d .. ')', 'q9x', x1, x2, R)
      R:step('Shells: V = ' .. M('2*' .. PI .. '*integral(y*x,y,' .. a .. ',' .. b .. ')') .. ' = ' .. M(Vd) .. ' '
             .. EQ(absval(V)))
      if V then R:result('volume (shells) about x-axis', absval(V), { key = 'vol_shell' }) end
   end
   -- graph: the curve, the lines y = a and y = b, the region left of the curve
   local F = numeric.compile_or_cas(f, { 'q9x' })
   local x1n, x2n = cas.n(x1), cas.n(x2)
   local lo, hi = min(0, x1n, x2n), max(0, x1n, x2n)
   local w = max(hi - lo, 1)
   local function right(y)
      return numeric.bisect(function(x) local v = F(x) return v and (v - y) end, min(x1n, x2n), max(x1n, x2n))
   end
   R.graph = {
      xmin = lo - 0.25 * w, xmax = hi + 0.25 * w, ymin = an - 0.25 * (bn - an), ymax = bn + 0.25 * (bn - an),
      curves = { { fn = F } }, shade = { { kind = 'y', right = right, a = an, b = bn } },
      hlines = { { y = an }, { y = bn } }, vlines = {}, axis = axis,
   }
end

-- Letters (constants) ---------------------------------------------------------------

-- Area and volume with constants in the curve or the limits (assumed > 0).
-- quiet: working only. Returns { area = ..., vol = ... | vol_shell = ... }
local function symbolic(R, kind, f, g, a, b, axis, consts, quiet)
   local var = VARS[kind]
   local cons = {}
   for _, c in ipairs(consts) do table.insert(cons, c .. '>0') end
   local assume = table.concat(cons, ' and ')
   local done = {}
   local function integ(e)
      local disp = 'integral(' .. e .. ',' .. var .. ',' .. a .. ',' .. b .. ')'
      local res = cas.eval(disp .. '|' .. assume)
      if res and not res:find('integral(', 1, true) then
         done[res] = true
         return res, disp
      end
      return disp, disp -- left as an integral
   end
   local out = {}
   local function put(key, label, value, how, raw)
      out[key] = value
      -- show '= value' only when the CAS could integrate
      R:step(done[raw] and (how .. ' ' .. U.eq(value)) or how)
      if not quiet then R:result(label, value, { key = key }) end
   end
   R:step('Constants: ' .. names_of(consts) .. ' > 0')
   if kind == 'param' then
      local dx = U.simp('derivative(' .. f .. ',' .. var .. ')')
      local dy = U.simp('derivative(' .. g .. ',' .. var .. ')')
      local A, Ad = integ('(' .. g .. ')*(' .. dx .. ')')
      put('area', 'area', A, 'A = ' .. M(Ad), A)
      local ve = axis == 'x' and ('(' .. g .. ')^2*(' .. dx .. ')') or ('(' .. f .. ')^2*(' .. dy .. ')')
      local V, Vd = integ(ve)
      put('vol', 'volume about ' .. axis .. '-axis', U.simp(PI .. '*' .. U.par(V)), 'V = ' .. M(PI .. '*' .. Vd), V)
      return out
   end
   local diff = g and ('(' .. f .. ')-(' .. g .. ')') or f
   local A, Ad = integ(diff)
   put('area', 'area', A, 'A = ' .. M(Ad), A)
   local same_axis = (kind == 'y' and axis == 'x') or (kind == 'x' and axis == 'y')
   if same_axis then
      local ve = g and ('(' .. f .. ')^2-(' .. g .. ')^2') or ('(' .. f .. ')^2')
      local V, Vd = integ(ve)
      put('vol', 'volume about ' .. axis .. '-axis', U.simp(PI .. '*' .. U.par(V)), 'V = ' .. M(PI .. '*' .. Vd), V)
   else
      local V, Vd = integ(var .. '*(' .. diff .. ')')
      put('vol_shell', 'volume (shells) about ' .. axis .. '-axis', U.simp('2*' .. PI .. '*' .. U.par(V)),
          'Shells: V = ' .. M('2*' .. PI .. '*' .. Vd), V)
   end
   return out
end

-- 'V=16pi', 'A=4' (a value to find the constant from) or 'a=2' (the constant)
local function parse_given(text, consts)
   local lhs, rhs = (text or ''):match('^%s*(%a+)%s*=%s*(.-)%s*$')
   if not lhs or rhs == '' then return nil end
   local val = U.simp(read(rhs))
   for _, c in ipairs(consts) do
      if cas.display_name(c) == lhs then return { const = c, val = val } end
   end
   local l = lhs:lower()
   if l == 'v' or l:find('^vol') then return { key = 'vol', name = 'V', val = val } end
   if l == 'a' or l == 'area' then return { key = 'area', name = 'A', val = val } end
end

function S.solve(I, R)
   local kind = I.type or 'y'
   if not I.f or (kind == 'param' and not I.g) or not I.a or not I.b then
      R:note(kind == 'param' and 'Enter x(t), y(t) and the t interval' or 'Enter the curve and the interval')
      return
   end
   local _, f, g, a, b, lim = inputs(I)
   local var = VARS[kind]
   for _, e in ipairs({ f, g or '0' }) do
      for _, u in ipairs(U.unknowns(e)) do
         if AXES[u] and u ~= var then
            R:note('Write the curve in terms of ' .. NAMES[kind] .. ' only', 'error')
            return
         end
      end
   end
   f, a, b = U.simp(f), U.simp(a), U.simp(b)
   g = g and U.simp(g) or nil
   local axis = I.axis or 'x'
   local consts = constants_of({ f or '0', g or '0', a or '0', b or '0' })

   -- limits given as y values for y = f(x): use x = g(y)
   if kind == 'y' and lim == 'y' then
      local an, bn = cas.n(a), cas.n(b)
      local yt = (an and bn) and cas.num((an + bn) / 2) or '1'
      local fi = inverse(f, yt)
      local gi = g and inverse(g, yt)
      if fi and (not g or gi) then
         R:step('Limits are y values: write x in terms of y:  x = ' .. M(fi) .. (gi and (',  x = ' .. M(gi)) or ''))
         kind, f, g = 'x', fi, gi
      elseif not g and #consts == 0 then
         R:step('Limits are y values')
         return by_substitution(R, f, a, b, axis)
      else
         R:note('Could not write x in terms of y: choose the curve type x = g(y)', 'error')
         return
      end
   end

   if #consts == 0 then
      return solve_numeric(R, kind, f, g, a, b, axis)
   end

   -- constants: answers in terms of them, or find one from a given value
   local names = names_of(consts)
   local given = I.known and parse_given(I.known, consts)
   if I.known and not given then
      R:note('Given: use V=16pi, A=4 or ' .. cas.display_name(consts[1]) .. '=2', 'error')
   end
   if not given then
      R:section('In terms of ' .. names)
      symbolic(R, kind, f, g, a, b, axis, consts)
      R:note('Answers in terms of ' .. names .. ' (assumed > 0). Type a value such as V=16pi in "given" to find '
             .. cas.display_name(consts[1]))
      return
   end
   local c, val
   if given.const then
      c, val = given.const, given.val
   else
      if #consts > 1 then
         R:note('Only one letter can be found from one given value', 'error')
         return
      end
      c = consts[1]
      R:section('Find ' .. cas.display_name(c))
      local ex = symbolic(R, kind, f, g, a, b, axis, consts, true)
      local e = ex[given.key] or (given.key == 'vol' and ex.vol_shell)
      local sols = e and cas.solve(U.par(e) .. '=' .. U.par(given.val), c, c .. '>0')
      local list = U.expand_solutions(sols, 0, nil, 4)
      val = list[1]
      if not val then
         R:note('Could not find ' .. cas.display_name(c) .. ' from the given value', 'error')
         return
      end
      R:step(given.name .. ' = ' .. M(given.val) .. ' ' .. U.IMPL .. ' ' .. M(c .. '=' .. val)
             .. (#list > 1 and ' (first positive solution)' or ''))
   end
   R:result(cas.display_name(c), val, { key = 'param_' .. cas.display_name(c) })
   local sub = { [c] = '(' .. val .. ')' }
   local function put(e) return e and U.simp(cas.rename(e, sub, true)) end
   f, g, a, b = put(f), put(g), put(a), put(b)
   if #constants_of({ f or '0', g or '0', a or '0', b or '0' }) > 0 then
      R:note('Answers in terms of ' .. names_of(constants_of({ f or '0', g or '0', a or '0', b or '0' })) .. ' (assumed > 0). Type a value such as V=16pi in "given" to find '
             .. cas.display_name(constants_of({ f or '0', g or '0', a or '0', b or '0' })[1]))
      return symbolic(R, kind, f, g, a, b, axis, constants_of({ f or '0', g or '0', a or '0', b or '0' }))
   end
   R:section('With ' .. cas.display_name(c) .. ' = ' .. U.txt(val))
   return solve_numeric(R, kind, f, g, a, b, axis)
end

return S
