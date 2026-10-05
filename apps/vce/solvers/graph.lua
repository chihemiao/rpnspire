-- Function analysis and graph: asymptotes (vertical, horizontal, oblique,
-- curved), turning points, points of inflection, intercepts,
-- discontinuities and points where f is not differentiable.
local cas = require 'apps.vce.cas'
local numeric = require 'apps.vce.numeric'
local fmt = require 'apps.vce.fmt'
local U = require 'apps.vce.solvers.util'

local M = U.M
local X = 'q9x'
local abs, max, min, floor = math.abs, math.max, math.min, math.floor

local SHOW = { { 'show', 'show' }, { 'hide', 'hide' } }

local S = {
   id = 'graph',
   title = 'Function graph & features',
   short = 'Graph',
   group = 'Calculus',
   desc = 'Asymptotes, turning points, inflection, intercepts, discontinuities',
   fields = {
      { id = 'f', label = 'f(x) =', hint = '(x^2-1)/(x-2)   x*e^(-x)   f11(x)' },
      { id = 'xmin', label = 'x from', hint = '-10' },
      { id = 'xmax', label = 'x to', hint = '10' },
      { id = 'ymin', label = 'y from', hint = 'auto' },
      { id = 'ymax', label = 'y to', hint = 'auto' },
      { id = 'asym', label = 'Asymptotes', kind = 'choice', options = { { 'dashed', 'dashed lines' }, { 'hide', 'hide' } } },
      { id = 'turn', label = 'Turning pts', kind = 'choice', options = SHOW },
      { id = 'infl', label = 'Inflection', kind = 'choice', options = SHOW },
      { id = 'icpt', label = 'Intercepts', kind = 'choice', options = SHOW },
      { id = 'disc', label = 'Discontinuity', kind = 'choice', options = SHOW },
      { id = 'labels', label = 'Labels', kind = 'choice', options = SHOW },
   },
   example = { f = '(x^2-1)/(x-2)', xmin = '-6', xmax = '8' },
}

-- 2 d.p. text for graph labels
local function n2(v)
   local s = fmt.plain(fmt.round(v, 2))
   return s
end

local function pt_label(name, x, y)
   return name .. ' (' .. n2(x) .. ', ' .. n2(y) .. ')'
end

-- Exact candidates from the CAS: solutions of `expr = 0` in the window
local function snap_list(list, xmin, xmax)
   local out = {}
   for _, e in ipairs(list) do
      local v = cas.n(e)
      if v and fmt.has_decimal(e) then
         local r = floor(v + 0.5)
         if abs(v - r) < 1e-8 * max(1, xmax - xmin) then e = cas.num(r) end
      end
      table.insert(out, e)
   end
   return out
end

local function cas_zeros(expr, xmin, xmax, cons)
   if not expr then return {} end
   local sols = cas.solve(expr .. '=0', X, cons)
   return snap_list(U.expand_solutions(sols, xmin, xmax, 30), xmin, xmax)
end

-- Is a CAS result usable (evaluated, no leftover function calls)?
local function evaluated(res, ...)
   if not res then return false end
   for _, name in ipairs({ ... }) do
      if res:find(name .. '(', 1, true) then return false end
   end
   return true
end

function S.solve(I, R)
   if not I.f then
      R:note('Enter f(x) and a window')
      return
   end
   local map = U.locals_map()
   local raw = cas.input(I.f, map)
   local fx = U.simp(raw)
   for _, u in ipairs(U.unknowns(fx)) do
      if u ~= X then
         R:note('Only x may appear in f(x): give parameters a value', 'error')
         return
      end
   end

   local xmin = I.xmin and U.read(I.xmin).num or -10
   local xmax = I.xmax and U.read(I.xmax).num or 10
   if not (xmin and xmax) or xmax <= xmin then
      R:note('x from must be less than x to', 'error')
      return
   end
   local ymin = I.ymin and U.read(I.ymin).num or nil
   local ymax = I.ymax and U.read(I.ymax).num or nil
   local cons = X .. U.GEQ .. cas.num(xmin) .. ' and ' .. X .. U.LEQ .. cas.num(xmax)

   -- evaluate the expression as typed (keeps holes the CAS cancels)
   local F = numeric.compile(raw, { X }) or numeric.compile_or_cas(fx, { X })
   if raw ~= fx and numeric.compile(raw, { X }) then
      R:step('f(x) = ' .. M(raw) .. ' = ' .. M(fx))
   else
      R:step('f(x) = ' .. M(fx))
   end

   -- Derivatives -------------------------------------------------------------
   local d1 = U.simp('derivative(' .. fx .. ',' .. X .. ')')
   local d2 = U.simp('derivative(' .. d1 .. ',' .. X .. ')')
   -- unevaluated derivative() would nest finite differences (noisy): use our own
   local function exact_fn(e)
      return not e:find('derivative', 1, true) and numeric.compile(e, { X })
   end
   local D1 = exact_fn(d1) or function(x) return numeric.deriv(F, x) end
   local D2 = exact_fn(d2) or function(x)
      local h = 1e-3 * max(1, abs(x))
      local a, b, c = F(x - h), F(x), F(x + h)
      if not (a and b and c) then return nil end
      return (a - 2 * b + c) / (h * h)
   end
   R:step("f'(x) = " .. M(d1))
   R:step("f''(x) = " .. M(d2))
   R:result("f'(x)", d1, { key = 'd1' })
   R:result("f''(x)", d2, { key = 'd2' })

   -- Sample the window ----------------------------------------------------------
   local N = 600
   local dx = (xmax - xmin) / N
   local xs, ys = {}, {}
   local finite = {}
   for i = 0, N do
      local x = xmin + i * dx
      xs[i] = x
      ys[i] = F(x)
      if ys[i] then table.insert(finite, ys[i]) end
   end
   table.sort(finite)
   local yscale = 1
   if #finite > 0 then
      local lo = finite[max(1, floor(#finite * 0.1) + 1)]
      local hi = finite[min(#finite, floor(#finite * 0.9) + 1)]
      yscale = max(1, hi - lo, abs(hi), abs(lo))
   end

   -- Exact candidates for special x values
   local exact = {}
   local function add_exact(list)
      for _, e in ipairs(list) do table.insert(exact, { e = e, v = cas.n(e) }) end
   end
   local den = cas.eval('getDenom(' .. fx .. ')')
   if evaluated(den, 'getDenom') and cas.uses(den, { X }) then
      add_exact(cas_zeros(den, xmin, xmax, cons))
   end
   -- denominators, log/root arguments and tan poles of the typed expression
   for _, src in ipairs({ raw, fx }) do
      for _, sp in ipairs(U.special_subexprs(src)) do
         if cas.uses(sp.expr, { X }) then
            add_exact(cas_zeros(sp.expr, xmin, xmax, cons))
         end
      end
   end
   local den1 = cas.eval('getDenom(' .. d1 .. ')')
   local nd_candidates = {}
   if evaluated(den1, 'getDenom') and cas.uses(den1, { X }) then
      nd_candidates = cas_zeros(den1, xmin, xmax, cons)
      add_exact(nd_candidates)
   end
   local function exact_of(x)
      for _, c in ipairs(exact) do
         if c.v and abs(c.v - x) < 1e-6 * max(1, abs(x)) then return c.e end
      end
      -- snap to integers / simple decimals found numerically
      local r = floor(x + 0.5)
      if abs(x - r) < 1e-7 * max(1, xmax - xmin) then return cas.num(r) end
      return fmt.round(x, 6)
   end

   -- One-sided behaviour at x0: 'inf' (with sign), 'fin' (value) or nil
   local function side(x0, dir)
      local s = max(1, abs(x0))
      local v = {}
      for k, d in ipairs({ 1e-3, 1e-6, 1e-9, 1e-11 }) do v[k] = F(x0 + dir * d * s) end
      if not v[3] or not v[4] then return nil end
      local a = { abs(v[1] or v[2]), abs(v[2]), abs(v[3]), abs(v[4]) }
      -- unbounded: keeps growing (poles grow by factors, logs by steps)
      local growing = a[2] > a[1] and a[3] > a[2] and a[4] > a[3]
      local steady = (a[4] - a[3]) > 0.3 * (a[3] - a[2]) and (a[3] - a[2]) > 0.3 * (a[2] - a[1])
      if abs(v[4]) > 1e6 * yscale or (growing and steady and a[4] - a[1] > 0.5 * yscale) then
         return 'inf', v[4] > 0 and 1 or -1
      end
      return 'fin', v[4]
   end

   -- Locate discontinuities and domain boundaries ------------------------------
   local events = {}
   local function add_event(x)
      for _, e in ipairs(events) do
         if abs(e - x) < 1e-5 * max(1, xmax - xmin) then return end
      end
      table.insert(events, x)
   end
   for i = 0, N - 1 do
      local a, b = ys[i], ys[i + 1]
      if a and b then
         if abs(b - a) > 0.25 * yscale then
            -- shrink towards the largest jump; a continuous function's jump vanishes
            local l, r = xs[i], xs[i + 1]
            local fl, fr = a, b
            local ok = true
            for _ = 1, 50 do
               local m = (l + r) / 2
               local fm = F(m)
               if not fm then
                  r = m
                  fr = nil
                  break
               end
               if abs(fm - fl) > abs(fr - fm) then r, fr = m, fm else l, fl = m, fm end
            end
            if fr and abs(fr - fl) < 1e-3 * yscale then ok = false end
            if ok then add_event((l + r) / 2) end
         end
      elseif (a and not b) or (b and not a) then
         -- boundary between defined and undefined: bisect on definedness
         local l, r = xs[i], xs[i + 1]
         local left_defined = a ~= nil
         for _ = 1, 50 do
            local m = (l + r) / 2
            if (F(m) ~= nil) == left_defined then l = m else r = m end
         end
         add_event((l + r) / 2)
      end
   end
   -- exact denominator zeros always count
   for _, c in ipairs(exact) do
      if c.v and c.v > xmin and c.v < xmax then
         local is_nd = false
         for _, nd in ipairs(nd_candidates) do
            if cas.n(nd) == c.v then is_nd = true end
         end
         if not is_nd or F(c.v) == nil then add_event(c.v) end
      end
   end
   table.sort(events)

   local spec = {
      xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
      curves = { { fn = F } }, asymptotes = {}, points = {}, breaks = {},
   }
   local vas = {}

   local function numeric_roots(G)
      local out = {}
      local prev = G(xs[0])
      for i = 1, N do
         local v = G(xs[i])
         if v and prev and (v < 0) ~= (prev < 0) and abs(v - prev) < 10 * yscale then
            local root = numeric.bisect(G, xs[i - 1], xs[i])
            if root then table.insert(out, fmt.round(root, 8)) end
         elseif v == 0 then
            table.insert(out, fmt.round(xs[i], 8))
         end
         prev = v
      end
      return snap_list(out, xmin, xmax)
   end
   local function guarded(title, fn)
      local ok, err = pcall(fn)
      if not ok then
         R:note(title .. ': ' .. tostring(type(err) == 'table' and (err.desc or '?') or err), 'warn')
      end
   end
   local stationary = {}

   guarded('Vertical asymptotes', function()
   R:section('Asymptotes')
   for _, x0 in ipairs(events) do
      -- snap to an exact candidate
      local ex = exact_of(x0)
      local xv = cas.n(ex) or x0
      local lk, lv = side(xv, -1)
      local rk, rv = side(xv, 1)
      local fx0 = F(xv)
      if lk == 'inf' or rk == 'inf' then
         table.insert(vas, ex)
         table.insert(spec.asymptotes, { kind = 'v', x = xv })
         table.insert(spec.breaks, xv)
         local how = (lk == 'inf' and rk == 'inf') and 'both sides' or (lk == 'inf' and 'from the left' or 'from the right')
         R:step('As x ' .. '\226\134\146' .. ' ' .. M(ex) .. ' (' .. how .. '), |f(x)| ' .. '\226\134\146' .. ' ' .. U.INF
                .. ' ' .. U.IMPL .. ' vertical asymptote ' .. M('x=' .. ex))
         R:result('vertical asymptote', 'q9x=' .. ex, { key = 'va' })
      elseif lk == 'fin' and rk == 'fin' then
         if abs(lv - rv) < 1e-4 * (1 + abs(lv)) then
            if not fx0 or abs(fx0 - lv) > 1e-4 * (1 + abs(lv)) then
               local L = cas.eval('limit(' .. fx .. ',' .. X .. ',' .. ex .. ')')
               if not (L and cas.n(L)) then L = fmt.round(lv, 6) end
               table.insert(spec.points, { x = xv, y = lv, kind = 'hole', label = pt_label('hole', xv, lv) })
               table.insert(spec.breaks, xv)
               R:step('lim f(x) as x' .. '\226\134\146' .. M(ex) .. ' = ' .. M(L) .. ' but f(' .. M(ex) .. ') is undefined '
                      .. U.IMPL .. ' hole at ' .. M('pt(' .. ex .. ',' .. L .. ')'))
               R:pair('hole (removable)', ex, L, { key = 'hole' })
            end
         else
            table.insert(spec.points, { x = xv, y = fx0 or lv, y2 = fx0 and (abs(fx0 - lv) < 1e-9 and rv or lv) or rv,
                                        kind = 'jump', label = 'jump x=' .. n2(xv) })
            table.insert(spec.breaks, xv)
            R:step('Left and right limits at ' .. M('x=' .. ex) .. ' differ (' .. U.D(lv) .. ' and ' .. U.D(rv) .. ') '
                   .. U.IMPL .. ' jump discontinuity')
            R:pair('jump discontinuity', ex, fmt.round(fx0 or lv, 6), { key = 'jump' })
         end
      elseif (lk == 'fin') ~= (rk == 'fin') then
         -- end of the domain
         local v = lk == 'fin' and lv or rv
         local yv = fx0 or v
         local closed = fx0 ~= nil
         table.insert(spec.points, { x = xv, y = yv, kind = closed and 'end' or 'hole', label = pt_label('end', xv, yv) })
         local ye = closed and U.simp(cas.with(fx, { { X, ex } })) or fmt.round(v, 6)
         R:step('Domain ends at ' .. M('x=' .. ex) .. (closed and ' (included)' or ' (not included)') .. ': '
                .. M('pt(' .. ex .. ',' .. ye .. ')'))
         R:pair(closed and 'endpoint (closed)' or 'endpoint (open)', ex, ye, { key = 'endpoint' })
      end
   end

   end)

   -- Horizontal / oblique / curved asymptotes ---------------------------------
   guarded('Asymptotes', function()
   local function limit_at(e, where)
      local L = cas.eval('limit(' .. e .. ',' .. X .. ',' .. where .. ')')
      if not evaluated(L, 'limit') then return nil end
      return L, cas.n(L)
   end
   local done = {}
   local sides = { { U.INF, '+' .. U.INF, 1 }, { U.NEGINF, U.NEG .. U.INF, -1 } }
   local h_found = {}
   -- check a limit against the function far out (guards against slow growth)
   local function far_ok(val, dir, G)
      G = G or F
      local a, b = G(dir * 1e5), G(dir * 1e7)
      if not (a and b) then
         a, b = G(dir * 1e3), G(dir * 1e5)
      end
      return a and b and abs(a - val) < 1e-3 * (1 + abs(val)) and abs(b - val) < 1e-4 * (1 + abs(val))
   end
   -- approximate limits: snap to 0 / integers
   local function snap0(e, v)
      if v and fmt.has_decimal(e) then
         if abs(v) < 1e-9 then return '0', 0 end
         local r = floor(v + 0.5)
         if abs(v - r) < 1e-4 * (1 + abs(v)) then return cas.num(r), r end
      end
      return e, v
   end
   -- the function itself is (eventually) this line: not an asymptote
   local function coincides(G, dir)
      for _, x in ipairs({ dir * 3.1, dir * 5.7, dir * 11.3 }) do
         local a, b = F(x), G(x)
         if not (a and b) or abs(a - b) > 1e-12 * (1 + abs(b)) then return false end
      end
      return true
   end
   for _, sd in ipairs(sides) do
      local where = sd[1]
      local L, Ln = limit_at(fx, where)
      if L and Ln and abs(Ln) < 1e12 and far_ok(Ln, sd[3]) then
         L, Ln = snap0(L, Ln)
         local c = Ln
         if not coincides(function() return c end, sd[3]) then
            h_found[sd[3]] = { L, Ln }
         else
            done[sd[3]] = true
         end
      end
   end
   if h_found[1] and h_found[-1] and abs(h_found[1][2] - h_found[-1][2]) < 1e-9 then
      local L = h_found[1][1]
      R:step('As x ' .. '\226\134\146' .. ' ' .. U.PM .. U.INF .. ', f(x) ' .. '\226\134\146' .. ' ' .. M(L) .. ' '
             .. U.IMPL .. ' horizontal asymptote ' .. M('q9y=' .. L))
      R:result('horizontal asymptote', 'q9y=' .. L, { key = 'ha' })
      table.insert(spec.asymptotes, { kind = 'h', y = h_found[1][2] })
      done[1], done[-1] = true, true
   else
      for _, sd in ipairs(sides) do
         local hf = h_found[sd[3]]
         if hf then
            R:step('As x ' .. '\226\134\146' .. ' ' .. sd[2] .. ', f(x) ' .. '\226\134\146' .. ' ' .. M(hf[1]) .. ' '
                   .. U.IMPL .. ' horizontal asymptote ' .. M('q9y=' .. hf[1]))
            R:result('horizontal asymptote', 'q9y=' .. hf[1], { key = 'ha' })
            table.insert(spec.asymptotes, { kind = 'h', y = hf[2] })
            done[sd[3]] = true
         end
      end
   end

   if not (done[1] and done[-1]) then
      -- rational functions: polynomial part of the division
      local num = cas.eval('getNum(' .. fx .. ')')
      local q
      if evaluated(den, 'getDenom') and evaluated(num, 'getNum') and cas.uses(den, { X }) then
         q = cas.eval('polyQuotient(' .. num .. ',' .. den .. ',' .. X .. ')')
         if not evaluated(q, 'polyQuotient') or not cas.uses(q, { X }) then q = nil end
      end
      local Qf = q and numeric.compile(q, { X })
      if q and Qf and coincides(Qf, 1) then q = nil end
      if q then
         local rem = cas.eval('polyRemainder(' .. num .. ',' .. den .. ',' .. X .. ')')
         local deg = cas.eval('polyDegree(' .. q .. ',' .. X .. ')')
         local kind = (cas.n(deg or '') == 1) and 'oblique asymptote' or 'asymptotic curve'
         R:step('f(x) = ' .. M(q .. '+(' .. (rem or 'r(x)') .. ')/(' .. den .. ')') .. ' ' .. U.IMPL .. ' ' .. kind .. ' ' .. M('q9y=' .. q))
         R:result(kind, 'q9y=' .. q, { key = 'oa' })
         local Q = numeric.compile(q, { X })
         if Q then table.insert(spec.asymptotes, { kind = 'f', fn = Q }) end
      else
         local lines = {}
         for _, sd in ipairs(sides) do
            if not done[sd[3]] then
               local m, mn = limit_at(fx .. '/' .. X, sd[1])
               m, mn = snap0(m, mn)
               if m and mn and abs(mn) > 1e-9 and abs(mn) < 1e12
                  and far_ok(mn, sd[3], function(x) local v = F(x) return v and v / x end) then
                  local c, cn = limit_at(fx .. '-(' .. m .. ')*' .. X, sd[1])
                  if c and cn and abs(cn) < 1e12
                     and far_ok(cn, sd[3], function(x) local v = F(x) return v and v - mn * x end) then
                     c, cn = snap0(c, cn)
                     local mm, cc = mn, cn
                     local Gl = function(x) return mm * x + cc end
                     if not coincides(Gl, sd[3]) then
                        local line = U.simp('(' .. m .. ')*' .. X .. '+(' .. c .. ')')
                        local same = lines[1] and abs(lines[1][2] - mn) < 1e-4 * (1 + abs(mn))
                                     and abs(lines[1][3] - cn) < 1e-4 * (1 + abs(cn))
                        if not same then
                           R:step('As x ' .. '\226\134\146' .. ' ' .. sd[2] .. ': ' .. M('f(x)/x') .. ' ' .. '\226\134\146' .. ' ' .. M(m)
                                  .. ', ' .. M('f(x)-' .. U.par(m) .. '*x') .. ' ' .. '\226\134\146' .. ' ' .. M(c) .. ' '
                                  .. U.IMPL .. ' oblique asymptote ' .. M('q9y=' .. line))
                           R:result('oblique asymptote', 'q9y=' .. line, { key = 'oa' })
                           table.insert(spec.asymptotes, { kind = 'f', fn = Gl })
                           table.insert(lines, { line, mn, cn })
                        else
                           R:step('The same line is the asymptote as x ' .. '\226\134\146' .. ' ' .. sd[2])
                        end
                     end
                     done[sd[3]] = true
                  end
               end
            end
         end
      end
   end
   if #spec.asymptotes == 0 then
      R:step('No asymptotes found in this window')
   end

   end)

   -- Stationary points --------------------------------------------------------
   guarded('Turning points', function()
   R:section('Turning points')
   local stat = cas_zeros(d1, xmin, xmax, cons)
   if #stat == 0 and not evaluated(cas.eval('solve(' .. d1 .. '=0,' .. X .. ')'), 'solve') then
      stat = numeric_roots(D1)
   end
   R:step("f'(x) = 0 " .. U.IMPL .. ' ' .. (#stat > 0 and ('x = ' .. table.concat((function()
      local t = {}
      for _, s in ipairs(stat) do table.insert(t, M(s)) end
      return t
   end)(), ', ')) or 'no solutions in the window'))
   for _, xs0 in ipairs(stat) do
      local x0 = cas.n(xs0)
      local y0n = x0 and F(x0)
      if x0 and y0n then
         local y0 = U.simp(cas.with(fx, { { X, xs0 } }))
         local v2 = D2(x0)
         local kind, why
         if v2 and v2 < -1e-9 then
            kind, why = 'max', "f''(" .. U.txt(xs0) .. ') < 0'
         elseif v2 and v2 > 1e-9 then
            kind, why = 'min', "f''(" .. U.txt(xs0) .. ') > 0'
         else
            local h = 1e-4 * max(1, abs(x0))
            local l, r = D1(x0 - h), D1(x0 + h)
            if l and r and l > 0 and r < 0 then
               kind, why = 'max', "f' changes from + to -"
            elseif l and r and l < 0 and r > 0 then
               kind, why = 'min', "f' changes from - to +"
            else
               kind, why = 'inflect', "f' does not change sign"
            end
         end
         local name = kind == 'max' and 'local maximum' or (kind == 'min' and 'local minimum' or 'stationary point of inflection')
         R:step("f''(" .. M(xs0) .. ')' .. (v2 and (' ' .. U.APPROX .. ' ' .. U.D(v2)) or '') .. ': ' .. why .. ' '
                .. U.IMPL .. ' ' .. name .. ' ' .. M('pt(' .. xs0 .. ',' .. y0 .. ')'))
         R:pair(name, xs0, y0, { key = kind == 'inflect' and 'spi' or kind })
         table.insert(spec.points, { x = x0, y = y0n, kind = kind == 'inflect' and 'inflect' or kind,
                                     label = pt_label(kind == 'inflect' and 'stat. infl.' or kind, x0, y0n) })
         stationary[#stationary + 1] = x0
      end
   end

   end)

   -- Corners and cusps (found here, reported later) -----------------------------
   local corners = {}
   local ok_c, err_c = pcall(function()
   -- numeric search: jumps in f' (corners) or f' undefined where f is defined
   local known = {}
   for _, e in ipairs(events) do table.insert(known, e) end
   local function is_known(x)
      for _, k in ipairs(known) do
         if abs(k - x) < 1e-4 * max(1, xmax - xmin) then return true end
      end
      return false
   end
   local dvals = {}
   for i = 0, N do dvals[i] = ys[i] and D1(xs[i]) or nil end
   local dabs = {}
   for i = 0, N do if dvals[i] then table.insert(dabs, abs(dvals[i])) end end
   table.sort(dabs)
   local dscale = max(1, dabs[max(1, floor(#dabs * 0.5))] or 1)
   -- check with f only: at a corner the slope jump stays as the step shrinks
   -- (smooth but steep curves, e.g. near an asymptote, lose it); at a vertical
   -- tangent or cusp the one-sided slopes blow up
   local function slopes(x0, w)
      local a, b, c = F(x0 - w), F(x0), F(x0 + w)
      if not (a and b and c) then return nil end
      return (b - a) / w, (c - b) / w
   end
   local function is_corner(x0)
      local sc = max(1, abs(x0))
      local a, b, c = F(x0 - 1e-12 * sc), F(x0), F(x0 + 1e-12 * sc)
      if not (a and b and c) or abs(c - b) + abs(b - a) > 1e-3 * yscale then return false end
      local l1, r1 = slopes(x0, 1e-4 * sc)
      local l2, r2 = slopes(x0, 1e-6 * sc)
      if not (l1 and l2) then return false end
      local j1, j2 = abs(r1 - l1), abs(r2 - l2)
      if j2 > 0.1 * dscale and j2 > 0.3 * j1 then return 'corner' end
      local s1, s2 = min(abs(l1), abs(r1)), min(abs(l2), abs(r2))
      return s2 > 10 * dscale and s2 > 3 * s1 and 'vertical'
   end
   -- prefer exact candidates / integers close to a numeric corner
   local function verify(x)
      local tol = 1e-3 * max(1, xmax - xmin)
      for _, c in ipairs(exact) do
         local k = c.v and abs(c.v - x) < tol and is_corner(c.v)
         if k then return c.v, k end
      end
      local r = floor(x + 0.5)
      local k = abs(x - r) < tol and is_corner(r)
      if k then return r, k end
      k = is_corner(x)
      if k then return x, k end
      return nil
   end
   for _, nd in ipairs(nd_candidates) do
      local v = cas.n(nd)
      if v and is_corner(v) == 'corner' then table.insert(corners, v) end
   end
   for i = 0, N - 1 do
      local a, b = dvals[i], dvals[i + 1]
      local cand, ckind
      if a and b and abs(b - a) > 0.5 * dscale then
         -- narrow the bracket around the largest change of f'
         local l, r, fl, fr = xs[i], xs[i + 1], a, b
         while r - l > 1e-4 * max(1, abs(l)) do
            local m = (l + r) / 2
            local fm = D1(m)
            if not fm then break end
            if abs(fm - fl) > abs(fr - fm) then r, fr = m, fm else l, fl = m, fm end
         end
         -- one-sided slopes of f just outside the bracket
         local w = max(r - l, 1e-6 * max(1, abs(l)))
         local fL, fl0, fr0, fR = F(l - w), F(l), F(r), F(r + w)
         if fL and fl0 and fr0 and fR then
            local sl, sr = (fl0 - fL) / w, (fR - fr0) / w
            if abs(sr - sl) > 0.1 * dscale and abs(fr0 - fl0) < 1e-3 * yscale then
               -- corner where the left and right tangent lines meet
               local xi = (fr0 - fl0 + sl * l - sr * r) / (sl - sr)
               cand = (xi >= l - w and xi <= r + w) and xi or (l + r) / 2
            end
         end
         if cand then cand, ckind = verify(cand) end
      end
      if not cand and i > 0 and a and b and dvals[i - 1] and abs(a) > 5 * dscale
             and abs(a) >= abs(dvals[i - 1]) and abs(a) >= abs(b) then
         -- spike in |f'| (vertical tangent or cusp between samples)
         local l, r = xs[i - 1], xs[i + 1]
         for _ = 1, 60 do
            local m1, m2 = l + (r - l) / 3, r - (r - l) / 3
            local d1v, d2v = D1(m1), D1(m2)
            if not (d1v and d2v) then break end
            if abs(d1v) < abs(d2v) then l = m1 else r = m2 end
         end
         cand, ckind = verify((l + r) / 2)
      end
      if not cand and ys[i] and ys[i + 1] and ((a and not b) or (b and not a)) then
         local l, r = xs[i], xs[i + 1]
         local left = a ~= nil
         for _ = 1, 50 do
            local m = (l + r) / 2
            if (D1(m) ~= nil) == left then l = m else r = m end
         end
         cand, ckind = verify((l + r) / 2)
      end
      if cand and not is_known(cand) then
         local ex = exact_of(cand)
         local already = false
         for _, nd in ipairs(nd_candidates) do
            if abs((cas.n(nd) or 1e300) - (cas.n(ex) or cand)) < 1e-6 then already = true end
         end
         if not already then table.insert(nd_candidates, ex) end
         table.insert(known, cand)
         -- a vertical tangent can still be a point of inflection
         if ckind == 'corner' then table.insert(corners, cand) end
      end
   end
   end)
   if not ok_c then R:note('Differentiability: ' .. tostring(type(err_c) == 'table' and err_c.desc or err_c), 'warn') end
   local function near_corner(x)
      for _, c in ipairs(corners) do
         if abs(c - x) < 5e-3 * max(1, abs(x)) then return true end
      end
      for _, e in ipairs(events) do
         if abs(e - x) < 5e-3 * max(1, abs(x)) then return true end
      end
      return false
   end

   -- Points of inflection ------------------------------------------------------
   guarded('Points of inflection', function()
   R:section('Points of inflection')
   local infl = cas_zeros(d2, xmin, xmax, cons)
   if #infl == 0 and not evaluated(cas.eval('solve(' .. d2 .. '=0,' .. X .. ')'), 'solve') then
      infl = numeric_roots(D2)
   end
   local found_infl = false
   for _, xs0 in ipairs(infl) do
      local x0 = cas.n(xs0)
      local y0n = x0 and F(x0)
      if x0 and y0n then
         local h = 1e-3 * max(1, xmax - xmin)
         local l, r = D2(x0 - h), D2(x0 + h)
         local tol = 1e-6 * yscale
         if l and r and (l < 0) ~= (r < 0) and abs(l) > tol and abs(r) > tol and not near_corner(x0) then
            local is_stat = false
            for _, sx in ipairs(stationary) do
               if abs(sx - x0) < 1e-6 then is_stat = true end
            end
            if not is_stat then
               local y0 = U.simp(cas.with(fx, { { X, xs0 } }))
               R:step("f''(x) = 0 at " .. M('x=' .. xs0) .. " and f'' changes sign " .. U.IMPL .. ' point of inflection '
                      .. M('pt(' .. xs0 .. ',' .. y0 .. ')'))
               R:pair('point of inflection', xs0, y0, { key = 'poi' })
               table.insert(spec.points, { x = x0, y = y0n, kind = 'inflect', label = pt_label('infl.', x0, y0n) })
               found_infl = true
            end
         end
      end
   end
   if not found_infl then R:step('No (non-stationary) points of inflection in the window') end

   end)

   -- Intercepts ------------------------------------------------------------------
   guarded('Intercepts', function()
   R:section('Intercepts')
   local zs = cas_zeros(fx, xmin, xmax, cons)
   if #zs == 0 and not evaluated(cas.eval('solve(' .. fx .. '=0,' .. X .. ')'), 'solve') then
      zs = numeric_roots(F)
   end
   for _, z in ipairs(zs) do
      local zn = cas.n(z)
      if zn and F(zn) then
         R:step('f(x) = 0 ' .. U.IMPL .. ' x-intercept ' .. M('pt(' .. z .. ',0)'))
         R:pair('x-intercept', z, '0', { key = 'xint' })
         table.insert(spec.points, { x = zn, y = 0, kind = 'intercept', label = pt_label('', zn, 0):gsub('^ ', '') })
      end
   end
   if xmin <= 0 and xmax >= 0 then
      local y0n = F(0)
      if y0n then
         local y0 = U.simp(cas.with(fx, { { X, '0' } }))
         R:step('f(0) = ' .. M(y0) .. ' ' .. U.IMPL .. ' y-intercept ' .. M('pt(0,' .. y0 .. ')'))
         R:pair('y-intercept', '0', y0, { key = 'yint' })
         table.insert(spec.points, { x = 0, y = y0n, kind = 'intercept', label = pt_label('', 0, y0n):gsub('^ ', '') })
      end
   end

   end)

   -- Not differentiable (corners, cusps) ----------------------------------------
   guarded('Differentiability', function()
   for _, nd in ipairs(nd_candidates) do
      local x0 = cas.n(nd)
      local y0n = x0 and F(x0)
      if x0 and y0n then
         local h = 1e-12 * max(1, abs(x0))
         local fl, fr = F(x0 - h), F(x0 + h)
         if fl and fr and abs(fl - y0n) < 1e-3 * yscale and abs(fr - y0n) < 1e-3 * yscale then
            local y0 = U.simp(cas.with(fx, { { X, nd } }))
            R:step("f'(" .. M(nd) .. ') does not exist but f is continuous ' .. U.IMPL .. ' not differentiable at '
                   .. M('pt(' .. nd .. ',' .. y0 .. ')'))
            R:pair('not differentiable', nd, y0, { key = 'cusp' })
            table.insert(spec.points, { x = x0, y = y0n, kind = 'cusp', label = pt_label('cusp', x0, y0n) })
         end
      end
   end

   end)

   -- Graph options ----------------------------------------------------------------
   local hide = {}
   if I.asym == 'hide' then hide.asym = true end
   if I.turn == 'hide' then hide.max, hide.min = true, true end
   if I.infl == 'hide' then hide.inflect = true end
   if I.icpt == 'hide' then hide.intercept = true end
   if I.disc == 'hide' then hide.hole, hide.jump, hide['end'], hide.cusp = true, true, true, true end
   spec.hide = hide
   R.graph = spec
   R.graph_labels = I.labels ~= 'hide'
end

return S
