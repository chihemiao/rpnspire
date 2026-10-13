-- Normal distribution: probabilities, inverse normal, find μ or σ
local cas = require 'apps.vce.cas'
local ev = require 'apps.vce.event'
local U = require 'apps.vce.solvers.util'

local M, D = U.M, U.D
local mu_s, sigma_s = U.mu, U.sigma

local S = {
   id = 'normal',
   title = 'Normal distribution',
   short = 'Normal',
   group = 'Probability',
   desc = 'P(a<X<b), inverse normal, find ' .. mu_s .. ' or ' .. sigma_s,
   fields = {
      { id = 'mu', label = mu_s, hint = 'mean' },
      { id = 'sd', label = sigma_s, hint = 'standard deviation' },
      { id = 'var', label = sigma_s .. U.SQ, hint = 'variance (instead of ' .. sigma_s .. ')' },
      { id = 'event', label = 'Event', hint = '45<X<55   X>k   X>60|X>50' },
      { id = 'p', label = 'Pr', hint = 'probability of event (to find k, ' .. mu_s .. ', ' .. sigma_s .. ')' },
      { id = 'q', label = 'P(X<x)=', hint = 'area, e.g. 0.99 -> x' },
   },
   example = { mu = '50', sd = '4', event = '45<X<55' },
}

local function ncdf(lo, hi, mu, sd)
   return string.format('normCdf(%s,%s,%s,%s)', lo or U.NEGINF, hi or U.INF, mu, sd)
end

-- Text for an event with given bounds
local function ptext(rv, lo, hi)
   if lo and not hi then
      return 'P(' .. rv .. ' > ' .. M(lo) .. ')'
   end
   local s = 'P('
   if lo then s = s .. M(lo) .. ' < ' end
   s = s .. rv
   if hi then s = s .. ' < ' .. M(hi) end
   return s .. ')'
end

local function dist_text(rv, mu, sd, var)
   local v = var and var.val or (U.par(sd.val) .. '^2')
   return rv .. ' ~ ' .. M('N(' .. mu.val .. ',' .. v .. ')')
end

function S.solve(I, R)
   local mu = U.read(I.mu)
   local sd = U.read(I.sd)
   local var = U.read(I.var)

   if var and not sd then
      local root = U.ROOT .. '(' .. var.val .. ')'
      local s = U.simp(root)
      sd = { src = s, val = s, num = cas.n(s) }
      R:result(sigma_s, s, { key = 'sd' })
      R:step(sigma_s .. ' = ' .. M(root) .. ' ' .. U.eq(s))
   elseif sd and not var then
      R:result(sigma_s .. U.SQ, U.simp(U.par(sd.val) .. '^2'), { key = 'var' })
   end

   local event = I.event and U.trim(I.event) ~= '' and I.event or nil
   local pin = I.p and ev.parse_prob(I.p)

   if not mu and not sd and event then
      mu = { val = '0', num = 0 }
      sd = { val = '1', num = 1 }
      R:note('No ' .. mu_s .. ', ' .. sigma_s .. ': using Z ~ N(0, 1)')
   end

   -- area to the left -> x value
   if I.q then
      if mu and sd then
         local q = U.read(I.q)
         local expr = string.format('invNorm(%s,%s,%s)', q.val, mu.val, sd.val)
         local xv = U.simp(expr)
         R:section('Area ' .. U.IMPL .. ' x')
         R:step('P(X < x) = ' .. M(q.val) .. ' ' .. U.IMPL .. ' x = ' .. M(expr) .. ' ' .. U.eq(xv))
         R:result('x: P(X<x)=' .. U.txt(q.val), xv, { key = 'q' })
      else
         R:note('Area ' .. U.IMPL .. ' x needs ' .. mu_s .. ' and ' .. sigma_s, 'warn')
      end
      if not event then return end
   end

   if not event then
      if mu and sd then
         R:step(dist_text('X', mu, sd, var))
         R:result('E(X)', mu.val, { key = 'mean' })
         R:note('Enter an event, e.g. X<55 or 45<X<55')
      else
         R:note('Enter ' .. mu_s .. ', ' .. sigma_s .. ' and an event')
      end
      return
   end

   local e, err = ev.parse(event)
   if not e then
      R:note(err, 'error')
      return
   end
   local rv = e.rv:upper()

   local lo, hi = U.bound(e.lo), U.bound(e.hi)
   if e.eq or e.ne then
      if mu and sd then
         R:step(dist_text(rv, mu, sd, var))
      end
      local v = e.eq and '0' or '1'
      R:step('X is continuous ' .. U.IMPL .. ' ' .. ev.describe(e, rv) .. ' = ' .. v)
      R:result(ev.describe(e, rv), v, { key = 'p' })
      return
   end

   local unknown = {}
   for _, b in ipairs({ lo or '', hi or '' }) do
      for _, u in ipairs(U.unknowns(b)) do unknown[u] = true end
   end
   local unk = next(unknown)

   -- Case: unknown bound -------------------------------------------------
   if unk then
      if not (mu and sd) then
         R:note('Need ' .. mu_s .. ' and ' .. sigma_s .. ' to find ' .. cas.display_name(unk), 'error')
         return
      end
      if not pin then
         R:note('Enter the probability Pr to find ' .. cas.display_name(unk), 'error')
         return
      end
      local p = U.read(pin.value)
      local name = cas.display_name(unk)
      R:step(dist_text(rv, mu, sd, var))
      R:step(ptext(rv, lo, hi) .. ' = ' .. M(p.val))
      local k
      local lo_has = lo and cas.uses(lo, { unk })
      local hi_has = hi and cas.uses(hi, { unk })
      if hi_has and not lo then
         k = string.format('invNorm(%s,%s,%s)', p.val, mu.val, sd.val)
      elseif lo_has and not hi then
         local pc = U.simp('1-' .. U.par(p.val))
         R:step(U.IMPL .. ' ' .. ptext(rv, nil, lo) .. ' = ' .. M('1-' .. U.par(p.val)) .. ' = ' .. M(pc))
         k = string.format('invNorm(%s,%s,%s)', pc, mu.val, sd.val)
      elseif hi_has and not lo_has then
         local below = ncdf(nil, lo, mu.val, sd.val)
         R:step(U.IMPL .. ' ' .. ptext(rv, nil, hi) .. ' = ' .. M(p.val .. '+' .. below))
         k = string.format('invNorm(%s+%s,%s,%s)', U.par(p.val), below, mu.val, sd.val)
      elseif lo_has and not hi_has then
         local below = ncdf(nil, hi, mu.val, sd.val)
         R:step(U.IMPL .. ' ' .. ptext(rv, nil, lo) .. ' = ' .. M(below .. '-' .. U.par(p.val)))
         k = string.format('invNorm(%s-%s,%s,%s)', below, U.par(p.val), mu.val, sd.val)
      end

      local kval
      if k then
         -- isolate the unknown: bound(k_sym) = invNorm(...)
         local bound = hi_has and hi or lo
         local inv = U.simp(k)
         if bound == unk then
            kval = inv
            R:step(name .. ' = ' .. M(k) .. ' ' .. U.eq(inv))
         else
            local sols = cas.solve(bound .. '=' .. inv, unk)
            kval = sols and sols[1]
            R:step(M(bound) .. ' = ' .. M(k) .. ' ' .. U.eq(inv))
            if kval then R:step(name .. ' ' .. U.eq(kval)) end
         end
      else
         -- unknown in both bounds: symmetric interval about the mean?
         local sum = cas.n('(' .. lo .. ')+(' .. hi .. ')')
         local width = sd.num and 10 * sd.num or 1000
         local eq = ncdf(lo, hi, mu.val, sd.val) .. '=' .. p.val
         if sum and mu.num and math.abs(sum - 2 * mu.num) < 1e-9 then
            R:step(U.IMPL .. ' ' .. ptext(rv, nil, hi) .. ' = ' .. M('(1+' .. U.par(p.val) .. ')/2'))
            local hv = U.simp(string.format('invNorm((1+%s)/2,%s,%s)', U.par(p.val), mu.val, sd.val))
            R:step(M(hi) .. ' = ' .. M(string.format('invNorm((1+%s)/2,%s,%s)', U.par(p.val), mu.val, sd.val))
                   .. ' ' .. U.eq(hv))
            local sols = cas.solve(hi .. '=' .. hv, unk)
            kval = sols and sols[1]
         else
            kval = cas.nsolve(eq, unk, 0, width)
            if not kval then kval = cas.nsolve(eq, unk) end
            R:step('Solve ' .. M(eq) .. ' for ' .. name)
         end
         if kval then R:step(name .. ' ' .. U.eq(kval)) end
      end

      if kval then
         R:result(name, kval, { key = 'k' })
         local assign = { { unk, kval } }
         if lo and lo ~= unk then R:result('lower', U.simp(cas.with(lo, assign)), { key = 'lo' }) end
         if hi and hi ~= unk then R:result('upper', U.simp(cas.with(hi, assign)), { key = 'hi' }) end
      else
         R:note('Could not solve for ' .. name, 'error')
      end
      return
   end

   -- Case: unknown μ or σ -----------------------------------------------
   if not (mu and sd) then
      if not mu and not sd then
         R:note('Two unknowns: use "Normal: find ' .. mu_s .. ' & ' .. sigma_s .. '"', 'error')
         return
      end
      if not pin then
         R:note('Enter Pr (probability of the event)', 'error')
         return
      end
      if e.given then
         R:note('Conditional events need ' .. mu_s .. ' and ' .. sigma_s, 'error')
         return
      end
      local p = U.read(pin.value)
      R:step(ptext(rv, lo, hi) .. ' = ' .. M(p.val))

      -- z value and the bound it applies to
      local z, b
      if hi and not lo then
         z, b = string.format('invNorm(%s)', p.val), hi
      elseif lo and not hi then
         local pc = U.simp('1-' .. U.par(p.val))
         R:step(U.IMPL .. ' ' .. ptext(rv, nil, lo) .. ' = ' .. M('1-' .. U.par(p.val)) .. ' = ' .. M(pc))
         z, b = string.format('invNorm(%s)', pc), lo
      elseif mu and cas.n(lo .. '+' .. hi) and math.abs(cas.n(lo .. '+' .. hi) - 2 * mu.num) < 1e-9 then
         local pc = U.simp('(1+' .. U.par(p.val) .. ')/2')
         R:step('Interval is symmetric about ' .. mu_s .. ' ' .. U.IMPL .. ' '
                .. ptext(rv, nil, hi) .. ' = ' .. M('(1+' .. U.par(p.val) .. ')/2') .. ' = ' .. M(pc))
         z, b = string.format('invNorm(%s)', pc), hi
      end

      if not mu then
         if not z then
            local eq = ncdf(lo, hi, 'q9m', sd.val) .. '=' .. p.val
            local m = cas.nsolve(eq, 'q9m')
            if m then
               R:step('Solve ' .. M(eq) .. ' for ' .. mu_s)
               R:result(mu_s, m, { key = 'mu' })
               R:step(mu_s .. ' ' .. U.eq(m))
            else
               R:note('Could not solve for ' .. mu_s, 'error')
            end
            return
         end
         local zv = U.simp(z)
         R:step(U.IMPL .. ' ' .. M('(' .. b .. '-' .. mu_s .. ')/' .. U.par(sd.val)) .. ' = ' .. M(z) .. ' ' .. U.eq(zv))
         local m = U.simp(string.format('%s-%s*%s', U.par(b), U.par(sd.val), z))
         R:step(mu_s .. ' = ' .. M(string.format('%s-%s*%s', U.par(b), U.par(sd.val), z)) .. ' ' .. U.eq(m))
         R:result(mu_s, m, { key = 'mu' })
      else
         if not z then
            local eq = ncdf(lo, hi, mu.val, 'q9s') .. '=' .. p.val
            local s = cas.nsolve(eq, 'q9s', 1e-6, 1e6)
            if s then
               R:step('Solve ' .. M(eq) .. ' for ' .. sigma_s .. ' > 0')
               R:result(sigma_s, s, { key = 'sd' })
               R:step(sigma_s .. ' ' .. U.eq(s))
            else
               R:note('Could not solve for ' .. sigma_s, 'error')
            end
            return
         end
         local zv = U.simp(z)
         R:step(U.IMPL .. ' ' .. M('(' .. b .. '-' .. U.par(mu.val) .. ')/' .. sigma_s) .. ' = ' .. M(z) .. ' ' .. U.eq(zv))
         local sexpr = string.format('(%s-%s)/%s', U.par(b), U.par(mu.val), z)
         local s = U.simp(sexpr)
         R:step(sigma_s .. ' = ' .. M(sexpr) .. ' ' .. U.eq(s))
         local sn = cas.n(s)
         if sn and sn <= 0 then
            R:note(sigma_s .. ' must be positive: check the event and Pr', 'error')
         end
         R:result(sigma_s, s, { key = 'sd' })
         R:result(sigma_s .. U.SQ, U.simp(U.par(s) .. '^2'), { key = 'var' })
      end
      return
   end

   -- Case: forward probability -----------------------------------------
   R:step(dist_text(rv, mu, sd, var))
   local function z_of(b)
      local zb = U.simp('(' .. b .. '-' .. U.par(mu.val) .. ')/' .. U.par(sd.val))
      return zb
   end

   local function prob_line(l, h, label)
      local expr = ncdf(l, h, mu.val, sd.val)
      local val = U.simp(expr)
      R:step((label or ptext(rv, l, h)) .. ' = ' .. M(expr) .. ' ' .. U.eq(val))
      return val, expr
   end

   if e.given then
      local num = function(s) return cas.n(U.bound(s)) end
      local a = { ev.interval(e, num) }
      local b = { ev.interval(e.given, num) }
      local i = ev.intersect(a, b)
      local glo, ghi = U.bound(e.given.lo), U.bound(e.given.hi)
      local inter_empty = i[1] >= i[3]
      local ilo = i[1] ~= -math.huge and cas.num(i[1]) or nil
      local ihi = i[3] ~= math.huge and cas.num(i[3]) or nil
      R:step(ev.describe(e, rv) .. ' = ' .. ptext(rv, ilo, ihi) .. ' / ' .. ptext(rv, glo, ghi))
      local pb = prob_line(glo, ghi)
      local pab = '0'
      if not inter_empty then
         pab = prob_line(ilo, ihi)
      end
      local res = U.simp(U.par(pab) .. '/' .. U.par(pb))
      R:step(ev.describe(e, rv) .. ' = ' .. D(cas.n(pab) or 0) .. ' / ' .. D(cas.n(pb) or 1) .. ' ' .. U.eq(res))
      R:result(ev.describe(e, rv), res, { key = 'p' })
      return
   end

   -- standardised form
   local zt = {}
   if lo then table.insert(zt, M(z_of(lo)) .. ' < ') end
   table.insert(zt, 'Z')
   if hi then table.insert(zt, ' < ' .. M(z_of(hi))) end
   local val = prob_line(lo, hi)
   R:step('= P(' .. table.concat(zt) .. '),  Z ~ N(0, 1)')
   R:result(ev.describe(e, rv), val, { key = 'p' })
end

return S
