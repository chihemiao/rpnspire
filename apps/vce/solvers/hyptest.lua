-- Hypothesis test for a population mean (σ known): p-value, decision,
-- critical values, Type I and Type II errors
local cas = require 'apps.vce.cas'
local U = require 'apps.vce.solvers.util'

local M = U.M
local mu_s, sigma_s = U.mu, U.sigma
local XBAR = 'bar(X)'
local xbar_t = '`bar(x)`'
local alpha_s = '\206\177'

local S = {
   id = 'hyptest',
   title = 'Hypothesis test (mean), Type I/II error',
   short = 'Hyp. test',
   group = 'Probability',
   desc = 'p-value, reject H0?, critical xbar, Type I and Type II error',
   fields = {
      { id = 'mu0', label = mu_s .. '0', hint = 'H0: ' .. mu_s .. ' = ' .. mu_s .. '0' },
      { id = 'h1', label = 'H1', kind = 'choice',
        options = { { '>', mu_s .. ' > ' .. mu_s .. '0' }, { '<', mu_s .. ' < ' .. mu_s .. '0' }, { '!=', mu_s .. ' ' .. U.NEQ .. ' ' .. mu_s .. '0' } } },
      { id = 'sd', label = sigma_s, hint = 'population SD' },
      { id = 'n', label = 'n', hint = 'sample size' },
      { id = 'xbar', label = xbar_t, hint = 'observed sample mean' },
      { id = 'alpha', label = alpha_s, hint = 'significance level (default 0.05)' },
      { id = 'c', label = 'crit ' .. xbar_t, hint = 'decision rule: reject if xbar beyond c' },
      { id = 'mu1', label = 'true ' .. mu_s, hint = 'actual mean, for Type II error' },
   },
   example = { mu0 = '50', h1 = '>', sd = '4', n = '25', xbar = '51.5', mu1 = '52' },
}

local function ncdf(lo, hi, mu, sd)
   return string.format('normCdf(%s,%s,%s,%s)', lo or U.NEGINF, hi or U.INF, mu, sd)
end

function S.solve(I, R)
   local mu0 = U.read(I.mu0)
   local sd = U.read(I.sd)
   local n = U.read(I.n)
   local xbar = U.read(I.xbar)
   local alpha = U.read(I.alpha)
   local c = U.read(I.c)
   local mu1 = U.read(I.mu1)
   local h1 = I.h1 or '>'

   if not (mu0 and sd and n) then
      R:note('Enter ' .. mu_s .. '0, ' .. sigma_s .. ' and n')
      return
   end

   local rel = h1 == '!=' and U.NEQ or h1
   R:step('H0: ' .. mu_s .. ' = ' .. M(mu0.val) .. ',   H1: ' .. mu_s .. ' ' .. rel .. ' ' .. M(mu0.val))
   local se = U.simp(U.par(sd.val) .. '/' .. U.ROOT .. '(' .. n.val .. ')')
   R:step('Under H0: ' .. M(XBAR) .. ' ~ N' .. M('(' .. mu0.val .. ',' .. U.par(sd.val) .. '^2/' .. n.val .. ')')
          .. ',  SD = ' .. M(se))
   R:result('SD(' .. M(XBAR) .. ')', se, { key = 'se' })

   if not alpha and not c then
      alpha = U.read('0.05')
   end

   -- p-value ----------------------------------------------------------------
   if xbar then
      local zexpr = U.simp('(' .. xbar.val .. '-' .. U.par(mu0.val) .. ')/' .. U.par(se))
      R:step('z = ' .. M('(bar(x)-' .. mu_s .. '0)/(' .. sigma_s .. '/' .. U.ROOT .. '(n))') .. ' = '
             .. M('(' .. xbar.val .. '-' .. U.par(mu0.val) .. ')/' .. U.par(se)) .. ' ' .. U.eq(zexpr))
      R:result('z', zexpr, { key = 'z' })
      local pexpr
      if h1 == '>' then
         pexpr = ncdf(xbar.val, nil, mu0.val, se)
         R:step('p = P(' .. M(XBAR) .. ' ' .. U.GEQ .. ' ' .. M(xbar.val) .. ' | ' .. mu_s .. ' = ' .. M(mu0.val) .. ') = ' .. M(pexpr))
      elseif h1 == '<' then
         pexpr = ncdf(nil, xbar.val, mu0.val, se)
         R:step('p = P(' .. M(XBAR) .. ' ' .. U.LEQ .. ' ' .. M(xbar.val) .. ' | ' .. mu_s .. ' = ' .. M(mu0.val) .. ') = ' .. M(pexpr))
      else
         local d = U.simp('abs(' .. xbar.val .. '-' .. U.par(mu0.val) .. ')')
         local up = U.simp(U.par(mu0.val) .. '+' .. U.par(d))
         pexpr = '2*' .. ncdf(up, nil, mu0.val, se)
         R:step('p = 2P(' .. M(XBAR) .. ' ' .. U.GEQ .. ' ' .. M(up) .. ' | ' .. mu_s .. ' = ' .. M(mu0.val) .. ') = ' .. M(pexpr))
      end
      local p = U.simp(pexpr)
      R:step('p ' .. U.eq(p))
      R:result('p-value', p, { key = 'p' })
      if alpha then
         local pn, an = cas.n(p), alpha.num
         if pn and an then
            if pn < an then
               R:step('p = ' .. U.D(pn) .. ' < ' .. M(alpha.val) .. ' ' .. U.IMPL .. ' reject H0: evidence that ' .. mu_s .. ' ' .. rel .. ' ' .. M(mu0.val))
               R:result('Decision', '"reject H0"', { key = 'decision' })
            else
               R:step('p = ' .. U.D(pn) .. ' > ' .. M(alpha.val) .. ' ' .. U.IMPL .. ' do not reject H0 (insufficient evidence)')
               R:result('Decision', '"do not reject H0"', { key = 'decision' })
            end
         end
      end
   end

   -- Critical value(s) / Type I error ---------------------------------------
   local c1, c2
   if alpha and not c then
      if h1 == '>' then
         c1 = U.simp(string.format('invNorm(1-%s,%s,%s)', U.par(alpha.val), mu0.val, se))
         R:step('Reject H0 if ' .. xbar_t .. ' > c:  c = ' .. M(string.format('invNorm(1-%s,%s,%s)', U.par(alpha.val), mu0.val, se)) .. ' ' .. U.eq(c1))
      elseif h1 == '<' then
         c1 = U.simp(string.format('invNorm(%s,%s,%s)', alpha.val, mu0.val, se))
         R:step('Reject H0 if ' .. xbar_t .. ' < c:  c = ' .. M(string.format('invNorm(%s,%s,%s)', alpha.val, mu0.val, se)) .. ' ' .. U.eq(c1))
      else
         c1 = U.simp(string.format('invNorm(%s/2,%s,%s)', U.par(alpha.val), mu0.val, se))
         c2 = U.simp(string.format('invNorm(1-%s/2,%s,%s)', U.par(alpha.val), mu0.val, se))
         R:step('Reject H0 if ' .. xbar_t .. ' < ' .. U.D(c1) .. ' or ' .. xbar_t .. ' > ' .. U.D(c2)
                .. ' (' .. M(string.format('invNorm(%s/2,%s,%s)', U.par(alpha.val), mu0.val, se)) .. ')')
      end
      if c2 then
         R:result('crit lower', c1, { key = 'c1' })
         R:result('crit upper', c2, { key = 'c2' })
      else
         R:result('critical ' .. xbar_t, c1, { key = 'c' })
      end
      R:result('P(Type I)', alpha.val, { key = 'type1' })
      R:step('P(Type I error) = P(reject H0 | H0 true) = ' .. alpha_s .. ' = ' .. M(alpha.val))
   elseif c then
      if h1 == '!=' then
         -- symmetric about mu0
         c2 = c.val
         c1 = U.simp('2*' .. U.par(mu0.val) .. '-' .. U.par(c.val))
         if (cas.n(c1) or 0) > (cas.n(c2) or 0) then c1, c2 = c2, c1 end
         local a = U.simp('1-' .. ncdf(c1, c2, mu0.val, se))
         R:step('P(Type I) = 1 - P(' .. M(c1) .. ' < ' .. M(XBAR) .. ' < ' .. M(c2) .. ' | ' .. mu_s .. ' = ' .. M(mu0.val) .. ') ' .. U.eq(a))
         R:result('P(Type I)', a, { key = 'type1' })
      else
         c1 = c.val
         local expr = h1 == '>' and ncdf(c.val, nil, mu0.val, se) or ncdf(nil, c.val, mu0.val, se)
         local a = U.simp(expr)
         R:step('P(Type I) = P(' .. M(XBAR) .. ' ' .. (h1 == '>' and '>' or '<') .. ' ' .. M(c.val) .. ' | ' .. mu_s .. ' = ' .. M(mu0.val) .. ') = ' .. M(expr) .. ' ' .. U.eq(a))
         R:result('P(Type I)', a, { key = 'type1' })
      end
   end

   -- Type II error -------------------------------------------------------------
   if mu1 and c1 then
      local expr
      if h1 == '>' then
         expr = ncdf(nil, c1, mu1.val, se)
         R:step('P(Type II) = P(' .. M(XBAR) .. ' < ' .. U.D(c1) .. ' | ' .. mu_s .. ' = ' .. M(mu1.val) .. ') = ' .. M(ncdf(nil, U.txt(c1), mu1.val, se)))
      elseif h1 == '<' then
         expr = ncdf(c1, nil, mu1.val, se)
         R:step('P(Type II) = P(' .. M(XBAR) .. ' > ' .. U.D(c1) .. ' | ' .. mu_s .. ' = ' .. M(mu1.val) .. ') = ' .. M(ncdf(U.txt(c1), nil, mu1.val, se)))
      else
         expr = ncdf(c1, c2, mu1.val, se)
         R:step('P(Type II) = P(' .. U.D(c1) .. ' < ' .. M(XBAR) .. ' < ' .. U.D(c2) .. ' | ' .. mu_s .. ' = ' .. M(mu1.val) .. ')')
      end
      local beta = U.simp(expr)
      R:step('P(Type II) ' .. U.eq(beta) .. ',  power = 1 - P(Type II) ' .. U.eq(U.simp('1-' .. U.par(beta))))
      R:result('P(Type II)', beta, { key = 'type2' })
      R:result('power', U.simp('1-' .. U.par(beta)), { key = 'power' })
   end
end

return S
