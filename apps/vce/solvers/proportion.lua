-- Sample proportions (Maths Methods): distribution of P̂ = X/n,
-- P(P̂ ...) exactly (binomial) and by the normal approximation,
-- approximate confidence intervals for p, margin of error and sample size.
local cas = require 'apps.vce.cas'
local ev = require 'apps.vce.event'
local U = require 'apps.vce.solvers.util'

local M = U.M
local PH = 'hat(p)'
local PHR = 'hat(P)'

local S = {
   id = 'proportion',
   title = 'Sample proportion & confidence interval',
   short = 'Sample proportion',
   group = 'Probability',
   course = 'MM',
   desc = 'E(p̂), SD(p̂), P(p̂>a), approximate CI for p, margin of error, sample size',
   fields = {
      { id = 'p', label = 'p', hint = 'population proportion' },
      { id = 'n', label = 'n', hint = 'sample size' },
      { id = 'event', label = 'Event', hint = 'P>0.3   0.2<P<0.4   (P means p-hat)' },
      { id = 'x', label = 'x (count)', hint = 'successes in the sample, e.g. 18' },
      { id = 'phat', label = '`hat(p)`', hint = 'sample proportion (or the count above)' },
      { id = 'c', label = 'Level', hint = 'confidence level: 95 or 0.95' },
      { id = 'e', label = 'E (M)', hint = 'margin of error (finds n)' },
      { id = 'lo', label = 'CI lower', hint = 'given interval (a, b)' },
      { id = 'hi', label = 'CI upper', hint = '' },
   },
   example = { p = '0.3', n = '50', event = 'P>0.36' },
}

local function binom_text(n, p, a, b)
   return string.format('binomCdf(%s,%s,%d,%d)', n, p, a, b)
end

function S.solve(I, R)
   local p = U.read(I.p)
   local n = U.read(I.n)
   local x = U.read(I.x)
   local phat = U.read(I.phat)
   local c = U.read(I.c)
   local E = U.read(I.e)
   local lo, hi = U.read(I.lo), U.read(I.hi)
   if c and c.num and c.num > 1 then c = U.read(U.par(c.val) .. '/100') end

   -- Distribution of P̂ ------------------------------------------------------------------
   local sd
   if p and n then
      R:section('Distribution of ' .. M(PHR))
      R:step(M(PHR) .. ' = ' .. M('X/n') .. ' where ' .. M('X') .. ' ~ ' .. M('Bi(' .. n.val .. ',' .. p.val .. ')'))
      R:step('E(' .. M(PHR) .. ') = p = ' .. M(p.val))
      R:result('E(`' .. PHR .. '`)', p.val, { key = 'mean' })
      local v = U.simp(U.par(p.val) .. '*(1-' .. U.par(p.val) .. ')/' .. U.par(n.val))
      sd = U.simp(U.ROOT .. '(' .. v .. ')')
      R:step('SD(' .. M(PHR) .. ') = ' .. M(U.ROOT .. '(p*(1-p)/n)') .. ' = '
             .. M(U.ROOT .. '(' .. p.val .. '*(1-' .. p.val .. ')/' .. n.val .. ')') .. ' ' .. U.eq(sd))
      R:result('SD(`' .. PHR .. '`)', sd, { key = 'sd' })
      R:result('Var(`' .. PHR .. '`)', v, { key = 'var' })
   end

   -- Probability for P̂ ---------------------------------------------------------------------
   if I.event and U.trim(I.event) ~= '' then
      if not (p and n) then
         R:note('Need p and n for P(p-hat ...)', 'error')
      else
         local e, err = ev.parse(I.event, { 'phat', 'p', 'x' })
         if not e then
            R:note(err, 'error')
         elseif e.given then
            R:note('Conditional events: use one event at a time', 'error')
         else
            R:section('Probability')
            local count = (e.rv or ''):lower() == 'x'
            local nn = n.num
            local function num(s) return cas.n(U.bound(s)) end
            local l, l_inc, h, h_inc = ev.interval(e, num)
            local d = ev.describe(e, count and 'X' or '`' .. PHR .. '`')
            -- exact: X = n P̂ is binomial
            local ca, cb
            if count then
               ca, cb = ev.int_range(l, l_inc, h, h_inc)
            else
               ca, cb = ev.int_range(l * nn, l_inc, h * nn, h_inc)
               local ex = ev.describe({ lo = e.lo and U.txt(U.simp(U.par(U.bound(e.lo)) .. '*' .. n.val)),
                                        lo_inc = e.lo_inc,
                                        hi = e.hi and U.txt(U.simp(U.par(U.bound(e.hi)) .. '*' .. n.val)),
                                        hi_inc = e.hi_inc,
                                        eq = e.eq and U.txt(U.simp(U.par(U.bound(e.eq)) .. '*' .. n.val)) }, 'X')
               R:step(d .. ' = ' .. ex .. ' (multiply by n = ' .. M(n.val) .. ')')
            end
            ca = math.max(0, ca)
            cb = math.min(nn, cb)
            if ca > cb then
               R:step('No whole numbers in this range ' .. U.IMPL .. ' probability 0')
               R:result(d .. ' exact', '0', { key = 'prob' })
            else
               local ext = binom_text(n.val, p.val, ca, cb)
               local pr = U.simp(ext)
               local rng = ca == cb and ('X = ' .. ca) or (ca .. ' ' .. U.LEQ .. ' X ' .. U.LEQ .. ' ' .. cb)
               R:step('= P(' .. rng .. ') = ' .. M(ext) .. ' ' .. U.eq(pr))
               R:result(d .. ' (binomial)', pr, { key = 'prob' })
            end
            -- normal approximation
            if not count and sd and not e.eq then
               local a = e.lo and U.bound(e.lo) or U.NEGINF
               local b = e.hi and U.bound(e.hi) or U.INF
               local ntext = string.format('normCdf(%s,%s,%s,%s)', a, b, p.val, sd)
               local pn = U.simp(ntext)
               R:step('Normal approximation ' .. M(PHR) .. ' ' .. U.APPROX .. ' '
                      .. M('N(' .. p.val .. ',' .. U.par(U.txt(sd)) .. '^2)') .. ': ' .. M(ntext) .. ' ' .. U.eq(pn))
               R:result(d .. ' (normal approx.)', pn, { key = 'prob_n' })
            end
         end
      end
   end

   -- Sample proportion from a count or an interval --------------------------------------------
   if lo and hi then
      local mid = U.simp('(' .. lo.val .. '+' .. hi.val .. ')/2')
      local half = U.simp('(' .. hi.val .. '-' .. lo.val .. ')/2')
      R:section('Confidence interval')
      R:step(M(PH) .. ' = ' .. M('(' .. lo.val .. '+' .. hi.val .. ')/2') .. ' ' .. U.eq(mid)
             .. ',  E = ' .. M('(' .. hi.val .. '-' .. lo.val .. ')/2') .. ' ' .. U.eq(half))
      if not phat then
         phat = U.read(mid)
         R:result('`' .. PH .. '`', mid, { key = 'phat' })
      end
      if not E then
         E = U.read(half)
         R:result('E', half, { key = 'e' })
      end
   end
   if x and n and not phat then
      local ph = U.simp(U.par(x.val) .. '/' .. U.par(n.val))
      R:step(M(PH) .. ' = ' .. M('x/n') .. ' = ' .. M(x.val .. '/' .. n.val) .. ' ' .. U.eq(ph))
      phat = U.read(ph)
      R:result('`' .. PH .. '`', ph, { key = 'phat' })
   end

   -- z from the level
   local z
   if c then
      local q = U.simp('(1+' .. U.par(c.val) .. ')/2')
      z = U.simp('invNorm(' .. q .. ')')
      R:step('z = ' .. M('invNorm((1+' .. U.par(c.val) .. ')/2)') .. ' ' .. U.eq(z))
      R:result('z', z, { key = 'z' })
   end

   if phat and n then
      local se = U.simp(U.ROOT .. '(' .. U.par(phat.val) .. '*(1-' .. U.par(phat.val) .. ')/' .. U.par(n.val) .. ')')
      R:step('SE = ' .. M(U.ROOT .. '(' .. PH .. '*(1-' .. PH .. ')/n)') .. ' = '
             .. M(U.ROOT .. '(' .. phat.val .. '*(1-' .. phat.val .. ')/' .. n.val .. ')') .. ' ' .. U.eq(se))
      R:result('SE', se, { key = 'se' })
      if z and not (lo and hi) then
         local m = U.simp(U.par(z) .. '*' .. U.par(se))
         local a = U.simp(U.par(phat.val) .. '-' .. U.par(m))
         local b = U.simp(U.par(phat.val) .. '+' .. U.par(m))
         R:step('E = ' .. M('z*SE') .. ' ' .. U.eq(m))
         R:step('Approximate CI = ' .. M('(' .. PH .. '-E,' .. PH .. '+E)') .. ' '
                .. U.APPROX .. ' (' .. U.D(a) .. ', ' .. U.D(b) .. ')')
         if not E then R:result('E', m, { key = 'e' }) end
         R:result('CI lower', a, { key = 'lo' })
         R:result('CI upper', b, { key = 'hi' })
      elseif E and not z then
         -- level of a given interval
         local zz = U.simp(U.par(E.val) .. '/' .. U.par(se))
         local level = U.simp('1-2*normCdf(' .. U.par(zz) .. ',' .. U.INF .. ',0,1)')
         R:step('z = ' .. M('E/SE') .. ' ' .. U.eq(zz))
         R:step('Level = ' .. M('1-2*normCdf(' .. U.txt(zz) .. ',' .. U.INF .. ',0,1)') .. ' ' .. U.eq(level))
         R:result('z', zz, { key = 'z' })
         R:result('Level', level, { key = 'c' })
      end
   end

   -- Sample size from the margin of error
   if E and z and not n then
      local ph = phat and phat.val or '1/2'
      if not phat then
         R:step('No estimate of p given: use ' .. M(PH .. '=1/2') .. ' (largest n)')
      end
      local raw = U.simp(U.par(z) .. '^2*' .. U.par(ph) .. '*(1-' .. U.par(ph) .. ')/' .. U.par(E.val) .. '^2')
      R:step('E = ' .. M('z*' .. U.ROOT .. '(' .. PH .. '*(1-' .. PH .. ')/n)') .. ' ' .. U.IMPL .. ' n = '
             .. M('z^2*' .. PH .. '*(1-' .. PH .. ')/E^2') .. ' ' .. U.eq(raw))
      local rn = cas.n(raw)
      if rn then
         local nn
         if lo and hi then
            nn = math.floor(rn + 0.5)
            R:step('The interval came from a sample ' .. U.IMPL .. ' n = ' .. nn)
         else
            nn = math.ceil(rn - 1e-9)
            R:step('Round up ' .. U.IMPL .. ' n = ' .. nn)
         end
         R:result('n', tostring(nn), { key = 'n' })
      end
   end

   if #R.results == 0 then
      R:note('Enter p and n (and an event), or x and n with a level for a confidence interval')
   end
end

return S
