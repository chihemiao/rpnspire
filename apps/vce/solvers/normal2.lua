-- Normal distribution: find μ and σ from two probability conditions
local ev = require 'apps.vce.event'
local U = require 'apps.vce.solvers.util'

local M = U.M
local mu_s, sigma_s = U.mu, U.sigma

local S = {
   id = 'normal2',
   title = 'Normal: find ' .. mu_s .. ' and ' .. sigma_s,
   short = 'Normal ' .. mu_s .. ',' .. sigma_s,
   group = 'Probability',
   desc = 'Two conditions like P(X<60)=0.9, P(X>40)=0.2',
   fields = {
      { id = 'e1', label = 'Event 1', hint = 'X<60' },
      { id = 'p1', label = 'Pr 1', hint = '0.9' },
      { id = 'e2', label = 'Event 2', hint = 'X>40' },
      { id = 'p2', label = 'Pr 2', hint = '0.2' },
   },
   example = { e1 = 'X<60', p1 = '0.9', e2 = 'X>40', p2 = '0.2' },
}

-- Returns bound, z-expression and description for 'P(event) = p'
local function condition(R, etext, ptext_, idx)
   local e, err = ev.parse(etext)
   if not e then error({ desc = 'Event ' .. idx .. ': ' .. err }) end
   local p = U.read(ptext_)
   if not p then error({ desc = 'Enter Pr ' .. idx }) end
   local rv = e.rv:upper()
   local b, z
   if e.hi and not e.lo then
      b = U.read(e.hi).val
      z = 'invNorm(' .. p.val .. ')'
      R:step('P(' .. rv .. ' < ' .. M(b) .. ') = ' .. M(p.val))
   elseif e.lo and not e.hi then
      b = U.read(e.lo).val
      local pc = U.simp('1-' .. U.par(p.val))
      z = 'invNorm(' .. pc .. ')'
      R:step('P(' .. rv .. ' > ' .. M(b) .. ') = ' .. M(p.val) .. ' ' .. U.IMPL .. ' P(' .. rv .. ' < ' .. M(b) .. ') = ' .. M(pc))
   else
      error({ desc = 'Event ' .. idx .. ' must be X<k or X>k' })
   end
   local zv = U.simp(z)
   R:step(U.IMPL .. ' ' .. M('(' .. b .. '-' .. mu_s .. ')/' .. sigma_s) .. ' = ' .. M(z) .. ' ' .. U.eq(zv))
   return b, z, zv
end

function S.solve(I, R)
   if not (I.e1 and I.p1 and I.e2 and I.p2) then
      R:note('Enter two events with their probabilities')
      return
   end
   local b1, _, z1 = condition(R, I.e1, I.p1, 1)
   local b2, _, z2 = condition(R, I.e2, I.p2, 2)

   R:step('Solve simultaneously: ' .. M(mu_s .. '+' .. U.par(U.txt(z1)) .. '*' .. sigma_s .. '=' .. b1)
          .. ', ' .. M(mu_s .. '+' .. U.par(U.txt(z2)) .. '*' .. sigma_s .. '=' .. b2))
   local sexpr = string.format('(%s-%s)/(%s-%s)', U.par(b1), U.par(b2), U.par(z1), U.par(z2))
   local s = U.simp(sexpr)
   local m = U.simp(string.format('%s-%s*%s', U.par(b1), U.par(s), U.par(z1)))
   local sn = U.read(s).num
   if sn and sn <= 0 then
      R:note(sigma_s .. ' is not positive: check events/probabilities', 'error')
   end
   R:step(sigma_s .. ' ' .. U.eq(s) .. ',  ' .. mu_s .. ' ' .. U.eq(m))
   R:result(mu_s, m, { key = 'mu' })
   R:result(sigma_s, s, { key = 'sd' })
   R:result(sigma_s .. U.SQ, U.simp(U.par(s) .. '^2'), { key = 'var' })
end

return S
