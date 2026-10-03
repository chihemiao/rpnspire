-- Sample means: distribution of X̄, confidence intervals, margin of error,
-- sample size
local cas = require 'apps.vce.cas'
local ev = require 'apps.vce.event'
local U = require 'apps.vce.solvers.util'

local M = U.M
local mu_s, sigma_s = U.mu, U.sigma
local XBAR = 'bar(X)'

local S = {
   id = 'sampling',
   title = 'Sample mean & confidence interval',
   short = 'CI / sample',
   group = 'Probability',
   desc = 'Xbar ~ N(' .. mu_s .. ', ' .. sigma_s .. U.SQ .. '/n), CI, margin of error, sample size',
   fields = {
      { id = 'mu', label = mu_s, hint = 'population mean (for P(Xbar...))' },
      { id = 'sd', label = sigma_s .. ' (s)', hint = 'population or sample SD' },
      { id = 'n', label = 'n', hint = 'sample size' },
      { id = 'xbar', label = '`bar(x)`', hint = 'sample mean' },
      { id = 'c', label = 'Level', hint = 'confidence level: 95 or 0.95' },
      { id = 'z', label = 'z', hint = 'optional: use z = 1.96' },
      { id = 'e', label = 'E (M)', hint = 'margin of error' },
      { id = 'w', label = 'width', hint = 'width of CI (= 2E)' },
      { id = 'lo', label = 'CI lower', hint = 'given interval (a, b)' },
      { id = 'hi', label = 'CI upper', hint = '' },
      { id = 'event', label = 'Event', hint = 'Xbar>52   49<Xbar<51' },
   },
   example = { sd = '4', n = '25', xbar = '52', c = '95' },
}

function S.solve(I, R)
   local mu = U.read(I.mu)
   local sd = U.read(I.sd)
   local n = U.read(I.n)
   local xbar = U.read(I.xbar)
   local c = U.read(I.c)
   local z = U.read(I.z)
   local E = U.read(I.e)
   local W = U.read(I.w)
   local lo, hi = U.read(I.lo), U.read(I.hi)

   if c and c.num and c.num > 1 then
      c = U.read(U.par(c.val) .. '/100')
   end

   -- Interval given -> centre and margin
   if lo and hi then
      local xb = U.simp('(' .. lo.val .. '+' .. hi.val .. ')/2')
      local m = U.simp('(' .. hi.val .. '-' .. lo.val .. ')/2')
      R:step('`bar(x)` = ' .. M('(' .. lo.val .. '+' .. hi.val .. ')/2') .. ' ' .. U.eq(xb)
             .. ',  E = ' .. M('(' .. hi.val .. '-' .. lo.val .. ')/2') .. ' ' .. U.eq(m))
      if not xbar then
         xbar = U.read(xb)
         R:result('`bar(x)`', xb, { key = 'xbar' })
      end
      if not E then
         E = U.read(m)
         R:result('E', m, { key = 'e' })
      end
   end
   if W and not E then
      local m = U.simp(U.par(W.val) .. '/2')
      R:step('E = width/2 ' .. U.eq(m))
      E = U.read(m)
      R:result('E', m, { key = 'e' })
   end

   -- z value from confidence level
   local zexpr
   if z then
      zexpr = z.val
      if c then
         R:step('Using z = ' .. M(z.val) .. ' for ' .. M(c.val) .. ' confidence')
      end
   elseif c then
      local q = U.simp('(1+' .. U.par(c.val) .. ')/2')
      zexpr = U.simp('invNorm(' .. q .. ')')
      R:step('z = ' .. M('invNorm((1+' .. U.par(c.val) .. ')/2)') .. ' = ' .. M('invNorm(' .. q .. ')') .. ' ' .. U.eq(zexpr))
      R:result('z', zexpr, { key = 'z' })
   end

   local se
   if sd and n then
      se = U.simp(U.par(sd.val) .. '/' .. U.ROOT .. '(' .. n.val .. ')')
      R:step('SD(' .. M(XBAR) .. ') = ' .. M(sigma_s .. '/' .. U.ROOT .. '(n)') .. ' = ' .. M(U.par(sd.val) .. '/' .. U.ROOT .. '(' .. n.val .. ')') .. ' ' .. U.eq(se))
      R:result('SD(' .. M(XBAR) .. ')', se, { key = 'se' })
   end

   -- Margin of error and interval
   if zexpr and se and not E then
      local m = U.simp(U.par(zexpr) .. '*' .. U.par(se))
      R:step('E = ' .. M('z*' .. sigma_s .. '/' .. U.ROOT .. '(n)') .. ' = ' .. M(U.par(U.txt(zexpr)) .. '*' .. U.par(se)) .. ' ' .. U.eq(m))
      E = U.read(m)
      R:result('E', m, { key = 'e' })
   end
   if xbar and E and not (lo and hi) then
      local a = U.simp(U.par(xbar.val) .. '-' .. U.par(E.val))
      local b = U.simp(U.par(xbar.val) .. '+' .. U.par(E.val))
      R:step('CI = ' .. M('(' .. xbar.val .. '-' .. U.par(U.txt(E.val)) .. ',' .. xbar.val .. '+' .. U.par(U.txt(E.val)) .. ')')
             .. ' ' .. U.APPROX .. ' (' .. U.D(a) .. ', ' .. U.D(b) .. ')')
      R:result('CI lower', a, { key = 'lo' })
      R:result('CI upper', b, { key = 'hi' })
   end

   -- Sample size
   if E and zexpr and sd and not n then
      local raw = U.simp('(' .. U.par(zexpr) .. '*' .. U.par(sd.val) .. '/' .. U.par(E.val) .. ')^2')
      local rn = cas.n(raw)
      R:step('E = ' .. M('z*' .. sigma_s .. '/' .. U.ROOT .. '(n)') .. ' ' .. U.IMPL .. ' n = ' .. M('(z*' .. sigma_s .. '/E)^2')
             .. ' = ' .. M('(' .. U.par(U.txt(zexpr)) .. '*' .. U.par(sd.val) .. '/' .. U.par(E.val) .. ')^2') .. ' ' .. U.eq(raw))
      if rn then
         local nn = math.ceil(rn - 1e-9)
         R:step('Round up ' .. U.IMPL .. ' n = ' .. nn)
         R:result('n', tostring(nn), { key = 'n' })
      end
   elseif E and zexpr and n and not sd then
      local s = U.simp(U.par(E.val) .. '*' .. U.ROOT .. '(' .. n.val .. ')/' .. U.par(zexpr))
      R:step(sigma_s .. ' = ' .. M('E*' .. U.ROOT .. '(n)/z') .. ' ' .. U.eq(s))
      R:result(sigma_s, s, { key = 'sd' })
   elseif E and se and not zexpr then
      local zz = U.simp(U.par(E.val) .. '/' .. U.par(se))
      local level = U.simp('1-2*normCdf(' .. U.par(zz) .. ',' .. U.INF .. ',0,1)')
      R:step('z = ' .. M('E/SD(' .. XBAR .. ')') .. ' ' .. U.eq(zz))
      R:step('Level = ' .. M('1-2*normCdf(' .. U.txt(zz) .. ',' .. U.INF .. ',0,1)') .. ' ' .. U.eq(level))
      R:result('z', zz, { key = 'z' })
      R:result('Level', level, { key = 'c' })
   end

   -- Probability for the sample mean
   if I.event and U.trim(I.event) ~= '' then
      if not (mu and se) then
         R:note('Need ' .. mu_s .. ', ' .. sigma_s .. ' and n for P(Xbar ...)', 'error')
         return
      end
      local e, err = ev.parse(I.event, { 'xbar', 'x', 'w', 'm' })
      if not e then
         R:note(err, 'error')
         return
      end
      local l, h = U.bound(e.lo), U.bound(e.hi)
      R:step(M(XBAR) .. ' ~ N' .. M('(' .. mu.val .. ',' .. U.par(sd.val) .. '^2/' .. n.val .. ')'))
      local expr = string.format('normCdf(%s,%s,%s,%s)', l or U.NEGINF, h or U.INF, mu.val, se)
      local p = U.simp(expr)
      local d = ev.describe(e, '`bar(X)`')
      R:step(d .. ' = ' .. M(expr) .. ' ' .. U.eq(p))
      R:result(d, p, { key = 'prob' })
   end

   if #R.results == 0 then
      R:note('Enter ' .. sigma_s .. ', n and xbar with a level, or E to find n')
   end
end

return S
