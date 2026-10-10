-- Transformations of graphs: y = f(x) -> y = A f(n(x + b)) + c
--   * image typed with f, e.g. 2f(3x-6)+4: read A, n, b, c
--   * image typed as a rule, e.g. 3(x-1)^2+2 with f(x) = x^2: find A, n, b, c
-- Gives the transformations in order (dilations, reflections, translations),
-- the mapping (x, y) -> (x/n - b, Ay + c), its inverse and the image of a point.
local cas = require 'apps.vce.cas'
local U = require 'apps.vce.solvers.util'
local numeric = require 'apps.vce.numeric'
local expr = require 'expressiontree'

local M = U.M
local MAP = U.locals_map()
local X, Y, UU = 'q9x', 'q9y', 'q8u'
local abs, max, min, floor = math.abs, math.max, math.min, math.floor
local PI = '\207\128'

local S = {
   id = 'transform',
   title = 'Transformations of graphs',
   short = 'Transformations',
   group = 'Functions',
   course = 'MM',
   desc = 'y=f(x) to y=Af(n(x+b))+c: order, mapping (x,y) to (..), or find it from two rules',
   fields = {
      { id = 'f', label = 'f(x) =', hint = 'x^2   sin(x)   e^x   sqrt(x)', implicit = true },
      { id = 'g', label = 'image y =', hint = '2f(3x-6)+4   or   3(x-1)^2+2' },
      { id = 'pt', label = 'point', hint = '(1,1) on y=f(x): find its image' },
   },
   example = { f = 'x^2', g = '-2f(3x-6)+4', pt = '(1,1)' },
}

local function strip_lhs(text)
   text = U.trim(text or '')
   local body = text:match('^%a%s*%(%s*%a%s*%)%s*=(.*)$') or text:match('^[yY]%s*=(.*)$')
   return U.trim(body or text)
end

local function at(e, var, v)
   return '(' .. cas.rename(e, { [var] = '(' .. v .. ')' }, true) .. ')'
end

-- Exact-looking text for a number found numerically (integers, p/q, kπ/q)
local function nice(x)
   if not x then return nil end
   for q = 1, 12 do
      local p = x * q
      if abs(p - floor(p + 0.5)) < 1e-7 * max(1, abs(p)) then
         p = floor(p + 0.5)
         local s = q == 1 and tostring(p) or (tostring(p) .. '/' .. q)
         return (s:gsub('^%-', U.NEG))
      end
   end
   for q = 1, 12 do
      local p = x * q / math.pi
      if abs(p - floor(p + 0.5)) < 1e-7 * max(1, abs(p)) then
         p = floor(p + 0.5)
         if p ~= 0 then
            local s = (p == 1 and '' or (p == -1 and '-' or (tostring(p) .. '*'))) .. PI .. (q == 1 and '' or ('/' .. q))
            return (s:gsub('^%-', U.NEG))
         end
      end
   end
end

-- Sample points where both functions are defined
local SAMPLE = { -3.7, -2.9, -2.2, -1.6, -1.1, -0.7, -0.35, 0.15, 0.45, 0.85, 1.3, 1.75, 2.35, 2.9, 3.6, 4.3 }

-- Least squares fit of g(x) = A*h(x) + c on the sample; returns A, c or nil
local function fit(G, H)
   local px, py = {}, {}
   for _, x in ipairs(SAMPLE) do
      local gy, hy = G(x), H(x)
      if gy and hy and abs(gy) < 1e8 and abs(hy) < 1e8 then
         table.insert(px, hy)
         table.insert(py, gy)
      end
   end
   local n = #px
   if n < 4 then return nil end
   local sx, sy, sxx, sxy = 0, 0, 0, 0
   for i = 1, n do
      sx, sy = sx + px[i], sy + py[i]
      sxx, sxy = sxx + px[i] * px[i], sxy + px[i] * py[i]
   end
   local d = n * sxx - sx * sx
   if abs(d) < 1e-9 * max(1, n * sxx) then return nil end
   local A = (n * sxy - sx * sy) / d
   local c = (sy - A * sx) / n
   if abs(A) < 1e-9 then return nil end
   local scale = 1
   for i = 1, n do scale = max(scale, abs(py[i])) end
   for i = 1, n do
      if abs(A * px[i] + c - py[i]) > 1e-6 * scale then return nil end
   end
   return A, c
end

-- Subexpressions of the rule that are linear in x (candidate inner parts)
local function linear_parts(src)
   local tree = expr.from_string(src)
   local seen, out = {}, {}
   local function walk(node)
      local ok, s = pcall(U.tree_infix, node)
      if ok and s and not seen[s] and cas.uses(s, { X }) then
         seen[s] = true
         local f = numeric.compile(s, { X })
         if f then
            local a, b, c = f(0.37), f(1.21), f(2.05)
            if a and b and c and abs((c - b) - (b - a)) < 1e-9 * max(1, abs(a), abs(b), abs(c))
               and abs(b - a) > 1e-12 then
               table.insert(out, s)
            end
         end
      end
      for _, ch in ipairs(node.children or {}) do walk(ch) end
   end
   pcall(walk, tree)
   table.sort(out, function(p, q) return #p > #q end)
   return out
end

-- Numeric search for g(x) = A f(n x + m) + c when no inner part is visible
local NS = { 1, -1, 2, -2, 0.5, -0.5, 3, -3, 1 / 3, -1 / 3, 4, -4, 0.25, -0.25 }
local function search(G, Fn)
   local ms = {}
   for i = -120, 120 do table.insert(ms, i / 12) end
   for k = -12, 12 do if k % 2 ~= 0 then table.insert(ms, k * math.pi / 6) end end
   for _, n in ipairs(NS) do
      for _, m in ipairs(ms) do
         if fit(G, function(x) return Fn(n * x + m) end) then return n, m end
      end
   end
end

-- Text for 'x + b' style pieces
local function plus(a, b)
   local bn = cas.n(b)
   if bn == 0 then return a end
   if bn and bn < 0 then return a .. '-' .. U.par(U.simp(U.NEG .. U.par(b))) end
   return a .. '+' .. U.par(b)
end

local function times(k, e)
   local kn = cas.n(k)
   if kn == 1 then return e end
   if kn == -1 then return U.NEG .. e end
   return U.par(k) .. '*' .. e
end

function S.solve(I, R)
   if not I.g then
      R:note('Type the image, e.g. 2f(3x-6)+4, or f(x) and the new rule')
      return
   end
   local fsrc = I.f and cas.input(strip_lhs(I.f), MAP, false, true)
   local graw = strip_lhs(I.g)
   local A, n, m, c, gsrc

   -- Image written with f( ... ) ------------------------------------------------------
   local name = U.trim(I.f or ''):match('^(%a)%s*%(%s*%a%s*%)%s*=') or 'f'
   local i0 = graw:find(name .. '%s*%(')
   if i0 and not graw:sub(i0 - 1, i0 - 1):match('[%a_]') then
      local open = graw:find('%(', i0)
      local depth, close = 0, nil
      for j = open, #graw do
         local ch = graw:sub(j, j)
         if ch == '(' then depth = depth + 1 elseif ch == ')' then
            depth = depth - 1
            if depth == 0 then close = j break end
         end
      end
      if not close then error({ desc = 'Missing ) in the image' }) end
      local inner = cas.input(graw:sub(open + 1, close - 1), MAP, false, true)
      local outer = cas.input(graw:sub(1, i0 - 1) .. '(' .. UU .. ')' .. graw:sub(close + 1), MAP, false, true)
      if not inner then error({ desc = 'Missing value in f( )' }) end
      if cas.uses(outer, { X }) then
         R:note('The image must be A*f(...)+c: x may only appear inside f( )', 'error')
         return
      end
      c = U.simp(at(outer, UU, '0'))
      A = U.simp(at(outer, UU, '1') .. '-' .. U.par(c))
      m = U.simp(at(inner, X, '0'))
      n = U.simp(at(inner, X, '1') .. '-' .. U.par(m))
      local An, cn, nn, mn = cas.n(A), cas.n(c), cas.n(n), cas.n(m)
      local o2, i2 = cas.n(at(outer, UU, '2.5')), cas.n(at(inner, X, '2.5'))
      if not (An and cn and o2 and abs(o2 - (2.5 * An + cn)) < 1e-9 * max(1, abs(o2))) then
         R:note('The image must be A*f(...)+c with numbers A and c', 'error')
         return
      end
      if not (nn and mn and i2 and abs(i2 - (2.5 * nn + mn)) < 1e-9 * max(1, abs(i2))) then
         R:note('Inside f( ) must be linear, like 3x-6 or 3(x-2)', 'error')
         return
      end
      if fsrc then gsrc = U.simp(times(A, U.par(at(fsrc, X, plus(times(n, X), m)))) .. '+' .. U.par(c)) end
      R:step('Image ' .. M('y=' .. times(A, 'f(' .. plus(times(n, X), m) .. ')') .. '+' .. U.par(c)))
   else
      -- Image given as a rule: match it with f -----------------------------------------
      if not fsrc then
         R:note('Type f(x) too, or write the image with f, e.g. 2f(3x-6)+4')
         return
      end
      gsrc = cas.input(graw, MAP, false, true)
      local G = numeric.compile(gsrc, { X }) or numeric.compile_or_cas(gsrc, { X })
      local Fn = numeric.compile(fsrc, { X }) or numeric.compile_or_cas(fsrc, { X })
      local found
      for _, L in ipairs(linear_parts(gsrc)) do
         local Lf = numeric.compile(L, { X })
         if fit(G, function(x) local u = Lf(x) return u and Fn(u) end) then
            m = U.simp(at(L, X, '0'))
            n = U.simp(at(L, X, '1') .. '-' .. U.par(m))
            found = L
            break
         end
      end
      if not found then
         local nn, mm = search(G, Fn)
         if nn then
            n, m = nice(nn), nice(mm)
            found = plus(times(n, X), m)
         end
      end
      if not found then
         R:note('Could not write the image as A*f(n(x+b))+c', 'error')
         return
      end
      -- exact A and c from two points where f has simple values
      local nn, mn = cas.n(n), cas.n(m)
      local us = {}
      for _, u in ipairs({ '0', '1', '2', '1/2', U.NEG .. '1', PI .. '/2', '3', '4' }) do
         local un = cas.n(u)
         local fu = un and Fn(un)
         local xu = un and (un - mn) / nn
         if fu and xu and G(xu) then
            local dup = false
            for _, o in ipairs(us) do if abs(o.f - fu) < 1e-9 then dup = true end end
            if not dup then table.insert(us, { u = u, f = fu }) end
         end
         if #us == 2 then break end
      end
      if #us < 2 then
         R:note('Could not write the image as A*f(n(x+b))+c', 'error')
         return
      end
      local function xof(u) return '(' .. U.par(u) .. '-' .. U.par(m) .. ')/' .. U.par(n) end
      local g1, g2 = at(gsrc, X, xof(us[1].u)), at(gsrc, X, xof(us[2].u))
      local f1, f2 = at(fsrc, X, us[1].u), at(fsrc, X, us[2].u)
      A = U.simp('(' .. g1 .. '-' .. g2 .. ')/(' .. f1 .. '-' .. f2 .. ')')
      c = U.simp(g1 .. '-' .. U.par(A) .. '*' .. f1)
      R:step('Write ' .. M('y=' .. gsrc) .. ' in the form ' .. M('y=A*f(n*(x+b))+c') .. ' with ' .. M('f(x)=' .. fsrc))
      R:step('Inside: ' .. M(plus(times(n, X), m)) .. ',  outside: ' .. M('A=' .. A) .. ', ' .. M('c=' .. c))
   end

   local b = U.simp(U.par(m) .. '/' .. U.par(n))
   local An, nn, bn, cn = cas.n(A), cas.n(n), cas.n(b), cas.n(c)
   if not (An and nn and bn and cn) or An == 0 or nn == 0 then
      R:note('A, n, b and c must be numbers (A, n not zero)', 'error')
      return
   end
   if cas.n(m) ~= 0 and nn ~= 1 then
      R:step(M('f(' .. plus(times(n, X), m) .. ')') .. ' = ' .. M('f(' .. times(n, U.par(plus(X, b))) .. ')'))
   end
   R:step(M('y=A*f(n*(x+b))+c') .. ' with ' .. M('A=' .. A) .. ', ' .. M('n=' .. n) .. ', ' .. M('b=' .. b) .. ', ' .. M('c=' .. c))
   R:result('A', A, { key = 'A' })
   R:result('n', n, { key = 'n' })
   R:result('b', b, { key = 'b' })
   R:result('c', c, { key = 'c' })

   -- Transformations in order ------------------------------------------------------------
   R:section('Transformations (in order)')
   local list = {}
   local absA = U.simp('abs(' .. A .. ')')
   local inv_n = U.simp('1/abs(' .. n .. ')')
   if abs(abs(An) - 1) > 1e-12 then
      table.insert(list, 'Dilation by a factor of ' .. U.txt(absA) .. ' from the x-axis')
   end
   if abs(abs(nn) - 1) > 1e-12 then
      table.insert(list, 'Dilation by a factor of ' .. U.txt(inv_n) .. ' from the y-axis')
   end
   if An < 0 then table.insert(list, 'Reflection in the x-axis') end
   if nn < 0 then table.insert(list, 'Reflection in the y-axis') end
   if bn ~= 0 then
      local sh = U.simp('abs(' .. b .. ')')
      table.insert(list, 'Translation of ' .. U.txt(sh) .. ' unit' .. (abs(bn) == 1 and '' or 's')
                   .. ' in the ' .. (bn < 0 and 'positive' or 'negative') .. ' direction of the x-axis')
   end
   if cn ~= 0 then
      local sh = U.simp('abs(' .. c .. ')')
      table.insert(list, 'Translation of ' .. U.txt(sh) .. ' unit' .. (abs(cn) == 1 and '' or 's')
                   .. ' in the ' .. (cn > 0 and 'positive' or 'negative') .. ' direction of the y-axis')
   end
   if #list == 0 then table.insert(list, 'No change (the image is y = f(x))') end
   for k, t in ipairs(list) do
      R:step(t)
      R:result(k .. '.', t, { key = 'step' .. k, text = true })
   end
   R:step('Order: dilations and reflections first, then translations')

   -- Mapping --------------------------------------------------------------------------------
   R:section('Mapping')
   local mx = U.simp(X .. '/' .. U.par(n) .. '-' .. U.par(b))
   local my = U.simp(U.par(A) .. '*' .. Y .. '+' .. U.par(c))
   R:step('x\' = ' .. M('x/n-b') .. ' = ' .. M(mx) .. ',   y\' = ' .. M('A*y+c') .. ' = ' .. M(my))
   R:result('(x, y) ' .. '\226\134\146', 'pt(' .. mx .. ',' .. my .. ')', { key = 'map' })
   local ix = U.simp(U.par(n) .. '*(' .. X .. '+' .. U.par(b) .. ')')
   local iy = U.simp('(' .. Y .. '-' .. U.par(c) .. ')/' .. U.par(A))
   R:step('Inverse (image back to y = f(x)): x = ' .. M(ix) .. ',  y = ' .. M(iy))
   R:result('inverse (x, y) ' .. '\226\134\146', 'pt(' .. ix .. ',' .. iy .. ')', { key = 'inv' })

   local spec = { curves = {}, points = {} }
   local P, Q
   if I.pt then
      local inner = U.trim(I.pt):match('^pt%s*(%b())$') or U.trim(I.pt):match('^(%b())$') or ('(' .. I.pt .. ')')
      local parts = cas.split_top(inner:sub(2, -2), ',')
      if #parts ~= 2 then
         R:note('Write the point as (1,1)', 'error')
      else
         local px = U.simp(cas.input(parts[1], MAP, false, true))
         local py = U.simp(cas.input(parts[2], MAP, false, true))
         local qx = U.simp(at(mx, X, px))
         local qy = U.simp(at(my, Y, py))
         R:step(M('pt(' .. px .. ',' .. py .. ')') .. ' ' .. '\226\134\146' .. ' '
                .. M('pt(' .. px .. '/' .. U.par(n) .. '-' .. U.par(b) .. ',' .. U.par(A) .. '*' .. U.par(py) .. '+' .. U.par(c) .. ')')
                .. ' = ' .. M('pt(' .. qx .. ',' .. qy .. ')'))
         R:pair('image of (' .. U.txt(px) .. ', ' .. U.txt(py) .. ')', qx, qy, { key = 'image' })
         P, Q = { cas.n(px), cas.n(py) }, { cas.n(qx), cas.n(qy) }
      end
   end

   -- Rule of the image and graph ---------------------------------------------------------------
   if gsrc then
      R:result('image y', gsrc, { key = 'g' })
   end
   local Fn = fsrc and (numeric.compile(fsrc, { X }) or numeric.compile_or_cas(fsrc, { X }))
   local Gn = gsrc and (numeric.compile(gsrc, { X }) or numeric.compile_or_cas(gsrc, { X }))
   if Fn and Gn then
      spec.curves = { { fn = Fn }, { fn = Gn } }
      if P and P[1] and P[2] and Q[1] and Q[2] then
         table.insert(spec.points, { x = P[1], y = P[2], kind = 'point', label = 'P' })
         table.insert(spec.points, { x = Q[1], y = Q[2], kind = 'max', label = "P'" })
      end
      -- window: a window for y = f(x) and its image under the mapping
      local plot = require 'ui.plot'
      local base = { xmin = -4, xmax = 4, curves = { { fn = Fn } } }
      plot.auto_range(base)
      local x1, x2 = -4 / nn - bn, 4 / nn - bn
      local y1, y2 = An * base.ymin + cn, An * base.ymax + cn
      spec.xmin, spec.xmax = min(-4, x1, x2), max(4, x1, x2)
      spec.ymin, spec.ymax = min(base.ymin, y1, y2), max(base.ymax, y1, y2)
      for _, q in ipairs(spec.points) do
         spec.xmin, spec.xmax = min(spec.xmin, q.x - 1), max(spec.xmax, q.x + 1)
         spec.ymin, spec.ymax = min(spec.ymin, q.y - 1), max(spec.ymax, q.y + 1)
      end
      R.graph = spec
   end
end

return S
