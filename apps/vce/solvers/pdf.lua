-- Continuous random variable with a (piecewise) probability density function
local cas = require 'apps.vce.cas'
local ev = require 'apps.vce.event'
local U = require 'apps.vce.solvers.util'

local M = U.M
local X = 'q9x'

local S = {
   id = 'pdf',
   title = 'Probability density function',
   short = 'PDF',
   group = 'Probability',
   desc = 'f(x): find k, E(X), Var(X), median, mode, P(a<X<b), x for area',
   fields = {
      { id = 'f1', label = 'f(x)', hint = '3/8*x^2   k*x*(2-x)' },
      { id = 'a1', label = 'from x=', hint = 'lower end of domain' },
      { id = 'b1', label = 'to x=', hint = 'upper end (inf allowed)' },
      { id = 'f2', label = 'f(x) #2', hint = 'optional 2nd piece', show = function(I) return I.f1 ~= nil end },
      { id = 'a2', label = 'from x=', hint = '', show = function(I) return I.f2 ~= nil end },
      { id = 'b2', label = 'to x=', hint = '', show = function(I) return I.f2 ~= nil end },
      { id = 'f3', label = 'f(x) #3', hint = 'optional 3rd piece', show = function(I) return I.f2 ~= nil end },
      { id = 'a3', label = 'from x=', hint = '', show = function(I) return I.f3 ~= nil end },
      { id = 'b3', label = 'to x=', hint = '', show = function(I) return I.f3 ~= nil end },
      { id = 'mean', label = 'E(X)=', hint = 'if given (2nd unknown)' },
      { id = 'event', label = 'Event', hint = 'X<1   0.5<X<1.5   X>k' },
      { id = 'pr', label = 'Pr', hint = 'probability of event (to find k)' },
      { id = 'q', label = 'P(X<x)=', hint = 'area, e.g. 0.99 -> x' },
   },
   example = { f1 = '3/8*x^2', a1 = '0', b1 = '2', event = 'X<1' },
}

local function integral(f, a, b)
   return string.format('integral(%s,%s,%s,%s)', f, X, a, b)
end

local function cond_text(p)
   local s = ''
   if p.an ~= -math.huge then s = p.a .. U.LEQ end
   s = s .. X
   if p.bn ~= math.huge then s = s .. U.LEQ .. p.b end
   return s
end

-- Pretty definition of f as a piecewise function (display only)
local function definition(pieces)
   local args = {}
   for _, p in ipairs(pieces) do
      table.insert(args, p.f)
      table.insert(args, cond_text(p))
   end
   table.insert(args, '0')
   return 'piecewise(' .. table.concat(args, ',') .. ')'
end

function S.solve(I, R)
   local map = U.locals_map()
   local pieces = {}
   for i = 1, 3 do
      local f = I['f' .. i]
      if f then
         local p = { f = cas.input(f, map), a = cas.input(I['a' .. i] or '', map), b = cas.input(I['b' .. i] or '', map) }
         if not p.a or not p.b then
            R:note('Enter the domain of piece ' .. i, 'error')
            return
         end
         p.a, p.b = U.simp(p.a), U.simp(p.b)
         p.an, p.bn = cas.n(p.a), cas.n(p.b)
         if not p.an or not p.bn then
            R:note('Domain ends must be numbers', 'error')
            return
         end
         table.insert(pieces, p)
      end
   end
   if #pieces == 0 then
      R:note('Enter f(x) and its domain')
      return
   end
   table.sort(pieces, function(a, b) return a.an < b.an end)

   -- Unknown constants ------------------------------------------------------
   local unknown, seen = {}, {}
   for _, p in ipairs(pieces) do
      for _, u in ipairs(U.unknowns(p.f)) do
         if u ~= X and not seen[u] then
            seen[u] = true
            table.insert(unknown, u)
         end
      end
   end

   local function area_expr(ps)
      local parts = {}
      for _, p in ipairs(ps) do table.insert(parts, integral(p.f, p.a, p.b)) end
      return table.concat(parts, '+')
   end

   R.display = 'f(' .. X .. ')=' .. definition(pieces)

   if #unknown > 0 then
      local total = area_expr(pieces)
      local tsimp = U.simp(total)
      R:step('Total area = 1: ' .. M(total .. '=1'))
      if tsimp ~= total then
         R:step(U.IMPL .. ' ' .. M(tsimp .. '=1'))
      end
      local assign
      if #unknown == 1 then
         local u = unknown[1]
         local sols = cas.solve(tsimp .. '=1', u)
         if not sols or #sols == 0 then
            local v = cas.nsolve(tsimp .. '=1', u)
            sols = v and { v } or {}
         end
         -- keep solutions with f(x) >= 0 on the domain
         local valid = {}
         for _, s in ipairs(sols) do
            local ok = true
            for _, p in ipairs(pieces) do
               local probe = {}
               local lo = p.an == -math.huge and p.bn - 10 or p.an
               local hi = p.bn == math.huge and p.an + 10 or p.bn
               for k = 0, 4 do table.insert(probe, lo + (hi - lo) * k / 4) end
               for _, xv in ipairs(probe) do
                  local v = cas.n(cas.with(p.f, { { u, s }, { X, cas.num(xv) } }))
                  if v and v < -1e-9 then ok = false end
               end
            end
            if ok then table.insert(valid, s) end
         end
         if #valid == 0 then
            R:note('No value of ' .. cas.display_name(u) .. ' makes f a valid pdf', 'error')
            return
         end
         if #valid < #sols then
            R:step('Reject values giving f(x) < 0')
         end
         assign = { { u, valid[1] } }
         R:step(U.IMPL .. ' ' .. cas.display_name(u) .. ' ' .. U.eq(valid[1]))
         R:result(cas.display_name(u), valid[1], { key = 'k' })
      elseif #unknown == 2 and I.mean then
         local mean = U.read(I.mean)
         local mparts = {}
         for _, p in ipairs(pieces) do
            table.insert(mparts, integral(X .. '*' .. U.par(p.f), p.a, p.b))
         end
         local meq = U.simp(table.concat(mparts, '+')) .. '=' .. mean.val
         R:step('E(X) = ' .. M(table.concat(mparts, '+') .. '=' .. mean.val))
         local u1, u2 = unknown[1], unknown[2]
         local res = cas.eval('solve(' .. tsimp .. '=1 and ' .. meq .. ',{' .. u1 .. ',' .. u2 .. '})')
         local s1 = res and cas.solutions(res, u1)
         local s2 = res and cas.solutions(res, u2)
         if not (s1 and s2 and s1[1] and s2[1]) then
            R:note('Could not solve for the two unknowns', 'error')
            return
         end
         assign = { { u1, s1[1] }, { u2, s2[1] } }
         R:step(U.IMPL .. ' ' .. cas.display_name(u1) .. ' ' .. U.eq(s1[1]) .. ',  ' .. cas.display_name(u2) .. ' ' .. U.eq(s2[1]))
         R:result(cas.display_name(u1), s1[1], { key = 'k' })
         R:result(cas.display_name(u2), s2[1], { key = 'k2' })
      else
         R:note('Too many unknowns (give E(X) for a second one)', 'error')
         return
      end
      for _, p in ipairs(pieces) do
         p.f = U.simp(cas.with(p.f, assign))
      end
      R.display = 'f(' .. X .. ')=' .. definition(pieces)
      R:step('f(x) = ' .. M(definition(pieces)))
   else
      local total = U.simp(area_expr(pieces))
      local tn = cas.n(total)
      if tn and math.abs(tn - 1) > 1e-6 then
         R:note('Total area = ' .. U.txt(total) .. ' (not 1): not a pdf', 'warn')
      end
   end

   for _, p in ipairs(pieces) do
      p.area = U.simp(integral(p.f, p.a, p.b))
      p.arean = cas.n(p.area) or 0
   end

   -- Mean, variance -----------------------------------------------------------
   local mparts, m2parts = {}, {}
   for _, p in ipairs(pieces) do
      table.insert(mparts, integral(X .. '*' .. U.par(p.f), p.a, p.b))
      table.insert(m2parts, integral(X .. '^2*' .. U.par(p.f), p.a, p.b))
   end
   local ok, err = pcall(function()
      local ex = U.simp(table.concat(mparts, '+'))
      local ex2 = U.simp(table.concat(m2parts, '+'))
      local var = U.simp(U.par(ex2) .. '-' .. U.par(ex) .. '^2')
      local sd = U.simp(U.ROOT .. '(' .. var .. ')')
      R:step('E(X) = ' .. M(table.concat(mparts, '+')) .. ' ' .. U.eq(ex))
      R:step('E(X' .. U.SQ .. ') = ' .. M(table.concat(m2parts, '+')) .. ' ' .. U.eq(ex2))
      R:step('Var(X) = E(X' .. U.SQ .. ') - [E(X)]' .. U.SQ .. ' = ' .. M(U.par(ex2) .. '-' .. U.par(ex) .. '^2') .. ' ' .. U.eq(var))
      R:step('SD(X) = ' .. M(U.ROOT .. '(' .. var .. ')') .. ' ' .. U.eq(sd))
      R:result('E(X)', ex, { key = 'mean' })
      R:result('Var(X)', var, { key = 'var' })
      R:result('SD(X)', sd, { key = 'sd' })
   end)
   if not ok then
      R:note('Mean/variance: ' .. tostring(type(err) == 'table' and err.desc or err), 'warn')
   end

   -- Quantile: value q with P(X < q) = p (p numeric) -----------------------------
   local function quantile(pexpr, name)
      local pn = cas.n(pexpr)
      if not pn or pn < 0 or pn > 1 then
         R:note('Probability must be between 0 and 1', 'error')
         return nil
      end
      local cum, cum_exact = 0, nil
      for idx, p in ipairs(pieces) do
         if cum + p.arean >= pn - 1e-12 or idx == #pieces then
            local lhs = integral(p.f, p.a, 'q9m')
            if cum_exact then lhs = U.par(cum_exact) .. '+' .. lhs end
            local eq = lhs .. '=' .. pexpr
            local cons = (p.an ~= -math.huge and (p.a .. U.LEQ .. 'q9m') or '')
            if p.bn ~= math.huge then
               cons = cons .. (cons ~= '' and ' and ' or '') .. 'q9m' .. U.LEQ .. p.b
            end
            local sols = cas.solve(eq, 'q9m', cons)
            local val
            for _, s in ipairs(sols or {}) do
               local v = cas.n(s)
               if v and v >= p.an - 1e-9 and v <= p.bn + 1e-9 then
                  val = s
                  break
               end
            end
            if not val then
               val = cas.nsolve(eq, 'q9m', p.an ~= -math.huge and p.a or nil, p.bn ~= math.huge and p.b or nil)
            end
            if #pieces > 1 and idx > 1 then
               R:step('P(X < ' .. M(p.a) .. ') = ' .. M(cum_exact) .. ' < ' .. M(pexpr) .. ', so ' .. name .. ' is in [' .. M(p.a) .. ', ' .. M(p.b) .. ']')
            end
            R:step(M(eq:gsub('q9m', 'q9' .. name)) .. (val and (' ' .. U.IMPL .. ' ' .. name .. ' ' .. U.eq(val)) or ''))
            return val
         end
         cum = cum + p.arean
         cum_exact = cum_exact and U.simp(U.par(cum_exact) .. '+' .. U.par(p.area)) or p.area
      end
   end

   -- Median
   local okm, med = pcall(quantile, '1/2', 'm')
   if okm and med then
      R:result('median', med, { key = 'median' })
   end

   -- Mode (maximum of f)
   pcall(function()
      local best, bestx
      local any_var = false
      for _, p in ipairs(pieces) do
         if cas.uses(p.f, { X }) then any_var = true end
      end
      if not any_var then return end
      for _, p in ipairs(pieces) do
         local cons = {}
         if p.an ~= -math.huge then table.insert(cons, p.a .. U.LEQ .. X) end
         if p.bn ~= math.huge then table.insert(cons, X .. U.LEQ .. p.b) end
         local res = cas.eval('fMax(' .. p.f .. ',' .. X .. ')|' .. table.concat(cons, ' and '))
         local sols = cas.solutions(res, X)
         if sols and sols[1] and cas.n(sols[1]) then
            local fx = cas.n(cas.with(p.f, { { X, sols[1] } }))
            if fx and (not best or fx > best + 1e-12) then
               best, bestx = fx, sols[1]
            end
         end
      end
      if bestx then
         R:step('Mode: f(x) is greatest at x ' .. U.eq(bestx))
         R:result('mode', bestx, { key = 'mode' })
      end
   end)

   -- P(X < x) = q -----------------------------------------------------------------
   if I.q then
      local q = U.read(I.q)
      R:section('Percentile')
      local v = quantile(q.val, 'a')
      if v then R:result('x: P(X<x)=' .. U.txt(q.val), v, { key = 'q' }) end
   end

   -- Event ------------------------------------------------------------------------
   if not I.event or U.trim(I.event) == '' then return end
   local e, eerr = ev.parse(I.event)
   if not e then
      R:note(eerr, 'error')
      return
   end
   R:section('Probability')
   local rv = e.rv:upper()
   local lo, hi = U.bound(e.lo), U.bound(e.hi)
   if e.eq or e.ne then
      local v = e.eq and '0' or '1'
      R:step('X is continuous ' .. U.IMPL .. ' ' .. ev.describe(e, rv) .. ' = ' .. v)
      R:result(ev.describe(e, rv), v, { key = 'prob' })
      return
   end

   local function cdf_at(t)
      -- exact P(X < t) for numeric t
      local tn = cas.n(t)
      local parts = {}
      for _, p in ipairs(pieces) do
         if tn > p.an then
            local up = tn >= p.bn and p.b or t
            table.insert(parts, integral(p.f, p.a, up))
         end
      end
      if #parts == 0 then return '0' end
      return U.simp(table.concat(parts, '+'))
   end

   local unk = {}
   for _, b in ipairs({ lo or '', hi or '' }) do
      for _, u in ipairs(U.unknowns(b)) do table.insert(unk, u) end
   end
   if #unk > 0 then
      if not I.pr then
         R:note('Enter Pr to find ' .. cas.display_name(unk[1]), 'error')
         return
      end
      local pr = U.read(ev.parse_prob(I.pr).value)
      local target
      local name = cas.display_name(unk[1])
      R:step(ev.describe(e, rv) .. ' = ' .. M(pr.val))
      if hi and not lo then
         target = pr.val
      elseif lo and not hi then
         target = U.simp('1-' .. U.par(pr.val))
         R:step(U.IMPL .. ' P(X < ' .. name .. ') = ' .. M(target))
      elseif lo and cas.uses(hi, unk) then
         target = U.simp(U.par(cdf_at(lo)) .. '+' .. U.par(pr.val))
         R:step(U.IMPL .. ' P(X < ' .. name .. ') = ' .. M(target))
      else
         target = U.simp(U.par(cdf_at(hi)) .. '-' .. U.par(pr.val))
         R:step(U.IMPL .. ' P(X < ' .. name .. ') = ' .. M(target))
      end
      local v = quantile(target, name)
      if v then R:result(name, v, { key = 'k' }) end
      return
   end

   local function prob(l, h)
      local ln = l and cas.n(l) or -math.huge
      local hn = h and cas.n(h) or math.huge
      local parts = {}
      for _, p in ipairs(pieces) do
         local a = math.max(ln, p.an)
         local b = math.min(hn, p.bn)
         if a < b then
            table.insert(parts, integral(p.f, a == ln and l or p.a, b == hn and h or p.b))
         end
      end
      if #parts == 0 then return '0', '0' end
      local expr = table.concat(parts, '+')
      return U.simp(expr), expr
   end

   if e.given then
      local num = function(s) return cas.n(U.bound(s)) end
      local A = { ev.interval(e, num) }
      local B = { ev.interval(e.given, num) }
      local AB = ev.intersect(A, B)
      local function nb(v, inf) return v ~= inf and cas.num(v) or nil end
      local pab, eab = '0', '0'
      if AB[1] < AB[3] then
         pab, eab = prob(nb(AB[1], -math.huge), nb(AB[3], math.huge))
      end
      local pb, eb = prob(U.bound(e.given.lo), U.bound(e.given.hi))
      R:step(ev.describe(e, rv) .. ' = ' .. M(U.par(eab) .. '/' .. U.par(eb)))
      local res = U.simp(U.par(pab) .. '/' .. U.par(pb))
      R:step('= ' .. M(U.par(pab) .. '/' .. U.par(pb)) .. ' ' .. U.eq(res))
      R:result(ev.describe(e, rv), res, { key = 'prob' })
      return
   end

   local res, expr = prob(lo, hi)
   R:step(ev.describe(e, rv) .. ' = ' .. M(expr) .. ' ' .. U.eq(res))
   R:result(ev.describe(e, rv), res, { key = 'prob' })
end

return S
