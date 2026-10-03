-- Known problems with expected answers. Run on the calculator (Help >
-- Self-test) to check that the solvers work with the real CAS; the desktop
-- tests run the same cases against the numeric mock.
local report = require 'apps.vce.report'
local solvers = require 'apps.vce.registry'

local T = {}

T.cases = {
   { 'normal', { mu = '50', sd = '4', event = '45<X<55' }, 'p', 0.7887005 },
   { 'normal', { mu = '50', sd = '4', event = 'X<k', p = '0.9' }, 'k', 55.126206 },
   { 'normal', { mu = '50', event = 'X<60', p = '0.95' }, 'sd', 6.0795683 },
   { 'normal2', { e1 = 'X<60', p1 = '0.9', e2 = 'X>40', p2 = '0.2' }, 'mu', 1.7384312 },
   { 'binomial', { n = '10', p = '0.3', event = 'X>=3' }, 'prob', 0.6172172 },
   { 'binomial', { p = '0.1', event = 'X>=1', pr = '>=0.95' }, 'n', 29 },
   { 'discrete', { x = '0,1,2,3', px = '0.1,k,2k,0.3' }, 'k', 0.2 },
   { 'discrete', { x = '0,1,2,3', px = '0.1,k,2k,0.3' }, 'var', 0.89 },
   { 'pdf', { f1 = '3/8*x^2', a1 = '0', b1 = '2' }, 'median', 1.5874011 },
   { 'pdf', { f1 = 'k*x*(2-x)', a1 = '0', b1 = '2' }, 'k', 0.75 },
   { 'pdf', { f1 = 'x', a1 = '0', b1 = '1', f2 = '2-x', a2 = '1', b2 = '2', event = '0.5<X<1.5' }, 'prob', 0.75 },
   { 'lincomb', { mx = '50', sx = '4', my = '30', sy = '3', comb = '2X-3Y', event = 'W>15' }, 'prob', 0.3389877 },
   { 'sampling', { sd = '4', e = '1', c = '95' }, 'n', 62 },
   { 'sampling', { sd = '4', n = '25', xbar = '52', c = '95' }, 'lo', 50.432029 },
   { 'hyptest', { mu0 = '50', h1 = '>', sd = '4', n = '25', xbar = '51.5', mu1 = '52' }, 'p', 0.0303964 },
   { 'hyptest', { mu0 = '50', h1 = '>', sd = '4', n = '25', xbar = '51.5', mu1 = '52' }, 'type2', 0.1962351 },
   { 'suvat', { s = '10', u = '20', a = '-9.8' }, 't1', 0.5833820 },
   { 'kinematics', { type = 'a(t)', f = '6t', x0 = '1', v0 = '2', find = 't=2' }, 'q_x', 13 },
   { 'kinematics', { type = 'v(t)', f = 't^2-4t+3', x0 = '0', t1 = '0', t2 = '4' }, 'dist', 4 },
   { 'kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', x0 = '0', find = 'v=5' }, 'q_x', 10 },
   { 'kinematics', { type = 'a(x)', f = '-4x', x0 = '0', v0 = '4', find = 'x=1' }, 'q_v', 3.4641016 },
   { 'kinematics', { type = 'v(x)', f = '2x+1', x0 = '0', find = 't=1' }, 'q_x', 3.1945280 },
}

-- Run one case; returns ok, got (number|nil), exact string|nil, error|nil
function T.run_case(c)
   local s = solvers.get(c[1])
   local R = report.new()
   local ok, err = pcall(s.solve, c[2], R)
   if not ok then
      return false, nil, nil, type(err) == 'table' and (err.desc or '?') or tostring(err)
   end
   local got = R:num(c[3])
   local exact = R:get(c[3])
   local want = c[4]
   local pass = got ~= nil and math.abs(got - want) <= 1e-4 * math.max(1, math.abs(want))
   return pass, got, exact, nil
end

return T
