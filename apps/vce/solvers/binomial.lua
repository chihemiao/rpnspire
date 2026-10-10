-- Binomial distribution X ~ Bi(n, p)
local cas = require 'apps.vce.cas'
local ev = require 'apps.vce.event'
local U = require 'apps.vce.solvers.util'

local M, D = U.M, U.D

local S = {
   id = 'binomial',
   title = 'Binomial distribution',
   short = 'Binomial',
   group = 'Probability',
   desc = 'Bi(n,p): P(X=k), P(X' .. U.GEQ .. 'k), find n or p, mean/var',
   fields = {
      { id = 'n', label = 'n', hint = 'number of trials' },
      { id = 'p', label = 'p', hint = 'P(success)' },
      { id = 'mean', label = 'E(X)', hint = 'mean np' },
      { id = 'var', label = 'Var(X)', hint = 'variance np(1-p)' },
      { id = 'sd', label = 'SD(X)', hint = 'standard deviation' },
      { id = 'event', label = 'Event', hint = 'X=3  X' .. U.GEQ .. '2  2' .. U.LEQ .. 'X<5  X>2|X' .. U.GEQ .. '1' },
      { id = 'pr', label = 'Pr', hint = 'e.g. ' .. U.GEQ .. '0.95 to find n, or 0.1 to find p' },
   },
   example = { n = '10', p = '0.3', event = 'X>=3' },
}

-- Lua binomial cdf for searches
local function lnfact(k)
   local s = 0
   for i = 2, k do s = s + math.log(i) end
   return s
end

local function bpdf(n, p, k)
   if k < 0 or k > n then return 0 end
   if p == 0 then return k == 0 and 1 or 0 end
   if p == 1 then return k == n and 1 or 0 end
   return math.exp(lnfact(n) - lnfact(k) - lnfact(n - k) + k * math.log(p) + (n - k) * math.log(1 - p))
end

local function bcdf(n, p, a, b)
   a = math.max(0, a)
   b = math.min(n, b)
   local s = 0
   for k = a, b do s = s + bpdf(n, p, k) end
   return s
end

-- Exact probability expression for integer range [a, b] (CAS strings)
local function prob_expr(n, p, a, b)
   if a == b then
      return string.format('nCr(%s,%d)*%s^%d*(1-%s)^(%s-%d)', n, a, U.par(p), a, U.par(p), n, a)
   end
   return string.format('sum(seq(nCr(%s,q9i)*%s^q9i*(1-%s)^(%s-q9i),q9i,%d,%d))',
                        n, U.par(p), U.par(p), n, a, b)
end

local function cdf_text(n, p, a, b)
   if a == b then
      return string.format('binomPdf(%s,%s,%d)', n, p, a)
   end
   return string.format('binomCdf(%s,%s,%d,%d)', n, p, a, b)
end

local function range_text(rv, a, b, n)
   if a == b then return 'P(' .. rv .. ' = ' .. a .. ')' end
   if a <= 0 then return 'P(' .. rv .. ' ' .. U.LEQ .. ' ' .. b .. ')' end
   if b >= n then return 'P(' .. rv .. ' ' .. U.GEQ .. ' ' .. a .. ')' end
   return 'P(' .. a .. ' ' .. U.LEQ .. ' ' .. rv .. ' ' .. U.LEQ .. ' ' .. b .. ')'
end

function S.solve(I, R)
   local n = U.read(I.n)
   local p = U.read(I.p)
   local mean = U.read(I.mean)
   local var = U.read(I.var)
   local sd = U.read(I.sd)
   if sd and not var then
      var = U.read(U.par(sd.val) .. '^2')
   end

   -- Parameters ---------------------------------------------------------
   if not (n and p) then
      if mean and var and not n and not p then
         local pe = U.simp('1-' .. U.par(var.val) .. '/' .. U.par(mean.val))
         R:step('E(X) = np = ' .. M(mean.val) .. ',  Var(X) = np(1-p) = ' .. M(var.val))
         R:step(U.IMPL .. ' 1-p = ' .. M(var.val .. '/' .. U.par(mean.val)) .. ' ' .. U.IMPL .. ' p ' .. U.eq(pe))
         p = U.read(pe)
         local ne = U.simp(U.par(mean.val) .. '/' .. U.par(pe))
         R:step('n = ' .. M('E(X)/p') .. ' ' .. U.eq(ne))
         n = U.read(ne)
      elseif n and mean and not p then
         local pe = U.simp(U.par(mean.val) .. '/' .. U.par(n.val))
         R:step('np = ' .. M(mean.val) .. ' ' .. U.IMPL .. ' p = ' .. M(mean.val .. '/' .. U.par(n.val)) .. ' ' .. U.eq(pe))
         p = U.read(pe)
      elseif p and mean and not n then
         local ne = U.simp(U.par(mean.val) .. '/' .. U.par(p.val))
         R:step('np = ' .. M(mean.val) .. ' ' .. U.IMPL .. ' n = ' .. M(mean.val .. '/' .. U.par(p.val)) .. ' ' .. U.eq(ne))
         n = U.read(ne)
      elseif p and var and not n then
         local ne = U.simp(U.par(var.val) .. '/(' .. U.par(p.val) .. '*(1-' .. U.par(p.val) .. '))')
         R:step('np(1-p) = ' .. M(var.val) .. ' ' .. U.IMPL .. ' n ' .. U.eq(ne))
         n = U.read(ne)
      elseif n and var and not p then
         local sols = cas.solve(n.val .. '*q9p*(1-q9p)=' .. var.val, 'q9p', '0<q9p and q9p<1')
         if sols and #sols > 0 then
            R:step('np(1-p) = ' .. M(var.val) .. ' ' .. U.IMPL .. ' ' .. M(n.val .. '*p*(1-p)=' .. var.val))
            for _, s in ipairs(sols) do
               R:step('p ' .. U.eq(s))
            end
            p = U.read(sols[1])
            if #sols > 1 then
               R:note('Two values of p; using p = ' .. U.txt(sols[1]) .. ' (enter p to choose)', 'warn')
            end
         end
      end
   end

   local pr = I.pr and ev.parse_prob(I.pr)
   local event = I.event and U.trim(I.event) ~= '' and I.event or nil
   local e, eerr
   if event then
      e, eerr = ev.parse(event)
      if not e then
         R:note(eerr, 'error')
         return
      end
   end

   -- Find n: smallest n with P(event) rel pr --------------------------------
   if not n and p and e and pr then
      local pn = p.num
      local target = U.read(pr.value).num
      local rel = pr.rel == '=' and U.GEQ or pr.rel
      local num = function(s) return U.read(s).num end
      local found
      for trial = 1, 2000 do
         local lo, lo_inc, hi, hi_inc = ev.interval(e, num)
         local a, b = ev.int_range(lo, lo_inc, hi, hi_inc)
         local v = bcdf(trial, pn, math.max(a, 0), math.min(b, trial))
         local ok
         if rel == U.GEQ then ok = v >= target - 1e-12
         elseif rel == '>' then ok = v > target
         elseif rel == U.LEQ then ok = v <= target + 1e-12
         else ok = v < target end
         if ok then
            found = trial
            break
         end
      end
      local rv = e.rv:upper()
      R:step('X ~ Bi(n, ' .. M(p.val) .. ')')
      if not found then
         R:note('No n ' .. U.LEQ .. ' 2000 satisfies the condition', 'error')
         return
      end
      local desc = ev.describe(e, rv)
      local ea, eb = ev.int_range(ev.interval(e, num))
      if ea == 1 and eb == math.huge then
         R:step(desc .. ' = 1 - P(' .. rv .. ' = 0) = ' .. M('1-(1-' .. U.par(p.val) .. ')^n') .. ' ' .. rel .. ' ' .. M(pr.value))
         if rel == U.GEQ or rel == '>' then
            local bexpr = string.format('ln(1-%s)/ln(1-%s)', U.par(pr.value), U.par(p.val))
            R:step(U.IMPL .. ' n ' .. U.GEQ .. ' ' .. M(bexpr) .. ' ' .. U.eq(U.simp(bexpr)))
         end
      else
         R:step('Find the smallest n with ' .. desc .. ' ' .. rel .. ' ' .. M(pr.value))
      end
      local function pval(nn)
         local lo, lo_inc, hi, hi_inc = ev.interval(e, num)
         local a, b = ev.int_range(lo, lo_inc, hi, hi_inc)
         return bcdf(nn, pn, math.max(a, 0), math.min(b, nn))
      end
      if found > 1 then
         R:step('n = ' .. (found - 1) .. ': ' .. desc .. ' ' .. U.APPROX .. ' ' .. D(pval(found - 1)))
      end
      R:step('n = ' .. found .. ': ' .. desc .. ' ' .. U.APPROX .. ' ' .. D(pval(found)))
      R:step(U.IMPL .. ' n = ' .. found)
      R:result('n', tostring(found), { key = 'n' })
      return
   end

   -- Find p: P(event) = pr ------------------------------------------------
   if n and not p and e and pr and not e.given then
      local num = function(s) return U.read(s).num end
      local lo, lo_inc, hi, hi_inc = ev.interval(e, num)
      local a, b = ev.int_range(lo, lo_inc, hi, hi_inc)
      local nn = n.num
      a, b = math.max(a, 0), math.min(b, nn)
      local pe = prob_expr(n.val, 'q9p', a, b)
      local eq = pe .. '=' .. U.read(pr.value).val
      local sols = cas.solve(eq, 'q9p', '0<q9p and q9p<1')
      R:step('X ~ Bi(' .. M(n.val) .. ', p)')
      R:step(range_text(e.rv:upper(), a, b, nn) .. ' = ' .. M(pe) .. ' = ' .. M(pr.value))
      if not sols or #sols == 0 then
         local v = cas.nsolve(eq, 'q9p', 0, 1)
         sols = v and { v } or {}
      end
      if #sols == 0 then
         R:note('No solution for p in (0, 1)', 'error')
         return
      end
      for i, s in ipairs(sols) do
         R:step('p ' .. U.eq(s))
         R:result(#sols > 1 and ('p' .. i) or 'p', s, { key = i == 1 and 'p' or ('p' .. i) })
      end
      return
   end

   if not (n and p) then
      R:note('Enter two of n, p, E(X), Var(X)')
      return
   end

   local nn = n.num
   if not nn or nn ~= math.floor(nn) or nn < 0 then
      R:note('n must be a whole number', 'error')
   end

   R:step('X ~ Bi(' .. M(n.val) .. ', ' .. M(p.val) .. ')')
   local m = U.simp(U.par(n.val) .. '*' .. U.par(p.val))
   local v = U.simp(U.par(n.val) .. '*' .. U.par(p.val) .. '*(1-' .. U.par(p.val) .. ')')
   local s = U.simp(U.ROOT .. '(' .. v .. ')')
   if not (mean and var) then
      R:step('E(X) = np ' .. U.eq(m) .. ',  Var(X) = np(1-p) ' .. U.eq(v))
   end
   R:result('n', n.val, { key = 'n' })
   R:result('p', p.val, { key = 'p' })
   R:result('E(X)', m, { key = 'mean' })
   R:result('Var(X)', v, { key = 'var' })
   R:result('SD(X)', s, { key = 'sd' })

   if not e then return end
   local rv = e.rv:upper()
   if not nn then return end

   local num = function(x) return U.read(x).num end
   local function range_of(x)
      local lo, lo_inc, hi, hi_inc = ev.interval(x, num)
      return { lo, lo_inc, hi, hi_inc }
   end

   local function prob(rng, label)
      local a, b = ev.int_range(rng[1], rng[2], rng[3], rng[4])
      a, b = math.max(a, 0), math.min(b, nn)
      if a > b then
         R:step((label or 'P') .. ' = 0')
         return '0', a, b
      end
      local exact = U.simp(prob_expr(n.val, p.val, a, b))
      local txt = range_text(rv, a, b, nn)
      local line = txt .. ' = ' .. M(cdf_text(n.val, p.val, a, b))
      if a > 0 and b == nn and a ~= b then
         line = txt .. ' = 1 - P(' .. rv .. ' ' .. U.LEQ .. ' ' .. (a - 1) .. ') = ' .. M(cdf_text(n.val, p.val, a, b))
      end
      R:step(line .. ' ' .. U.eq(exact))
      return exact, a, b
   end

   if e.ne then
      local k = num(e.ne)
      local pk = U.simp(prob_expr(n.val, p.val, k, k))
      local res = U.simp('1-' .. U.par(pk))
      R:step(ev.describe(e, rv) .. ' = 1 - P(' .. rv .. ' = ' .. k .. ') ' .. U.eq(res))
      R:result(ev.describe(e, rv), res, { key = 'prob' })
      return
   end

   if e.given then
      local A, B = range_of(e), range_of(e.given)
      local AB = ev.intersect(A, B)
      local function rtext(rng)
         local a, b = ev.int_range(rng[1], rng[2], rng[3], rng[4])
         a, b = math.max(a, 0), math.min(b, nn)
         if a > b then return '0' end
         return range_text(rv, a, b, nn)
      end
      R:step(ev.describe(e, rv) .. ' = ' .. rtext(AB) .. ' / ' .. rtext(B))
      local pb = prob(B)
      local pab = prob(AB)
      local res = U.simp(U.par(pab) .. '/' .. U.par(pb))
      R:step(ev.describe(e, rv) .. ' = ' .. D(cas.n(pab) or 0) .. ' / ' .. D(cas.n(pb) or 1) .. ' ' .. U.eq(res))
      R:result(ev.describe(e, rv), res, { key = 'prob' })
      return
   end

   local res = prob(range_of(e))
   R:result(ev.describe(e, rv), res, { key = 'prob' })
end

return S
