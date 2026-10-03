-- Desktop tests for the VCE toolkit (run: lua test_vce.lua)
--
-- The TI CAS is replaced by the numeric mock in testcas.lua, so these tests
-- check solver logic and numbers, not exact symbolic output or TI syntax.
package.path = './?.lua;' .. package.path

-- Minimal TI runtime stubs ---------------------------------------------------
function _G.class(base)
   local classdef = {}
   setmetatable(classdef, {
      __index = base,
      __call = function(_, ...)
         local inst = { class = classdef, super = base or nil }
         setmetatable(inst, { __index = classdef })
         if inst.init then inst:init(...) end
         return inst
      end
   })
   return classdef
end

function string.usub(...) return string.sub(...) end
if not unpack then _G.unpack = table.unpack end

local GC = {
   getStringWidth = function(_, s) return 6 * #(s or '') end,
   getStringHeight = function() return 12 end,
   drawRect = function() end, fillRect = function() end,
   setColorRGB = function() end, setFont = function() end,
   drawString = function() end, drawLine = function() end,
   drawArc = function() end, clipRect = function() end,
   setPen = function() end, fillPolygon = function() end,
}

_G.platform = {
   apiLevel = '2.4',
   withGC = function(fn) return fn(GC) end,
   window = {
      width = function() return 318 end,
      height = function() return 212 end,
      invalidate = function() end,
   },
}
_G.on = {}
_G.clipboard = { text = '', addText = function(s) _G.clipboard.text = s end,
                 getText = function() return _G.clipboard.text end }
_G.var = { store = function() end, list = function() return {} end }
_G.toolpalette = { register = function(m) _G.toolpalette.menu = m end,
                   enableCopy = function() end, enableCut = function() end,
                   enablePaste = function() end }

require 'tableext'
require 'stringext'

local config = require 'config.config'
config.use_document_settings = false

local mock = require 'testcas'
local cas = require 'apps.vce.cas'
cas.backend = mock.evalStr
math.evalStr = mock.evalStr

local Test = require 'testlib'
local report = require 'apps.vce.report'
local fmt = require 'apps.vce.fmt'
local sym = require 'ti.sym'

local VERBOSE = os.getenv('VERBOSE')

-- Helpers ------------------------------------------------------------------------

local function run(solver_id, inputs)
   local solvers = require 'apps.vce.registry'
   local s = solvers.get(solver_id)
   assert(s, 'unknown solver ' .. solver_id)
   local R = report.new()
   local ok, err = pcall(s.solve, inputs, R)
   if not ok then
      error((type(err) == 'table' and (err.desc or '') .. ' ' .. tostring(err.expr) or tostring(err)))
   end
   if VERBOSE then
      local function out(s) io.stderr:write(s .. '\n') end
      out('== ' .. solver_id)
      for _, n in ipairs(R.notes) do out('  note: ' .. report.plain(n.text)) end
      for _, r in ipairs(R.results) do out('  ' .. report.plain(r.label) .. ' = ' .. fmt.plain(r.exact)) end
      for _, st in ipairs(R.steps) do out('    | ' .. report.plain(st.text)) end
   end
   return R
end

local function near(a, b, tol, msg)
   tol = tol or 1e-4
   Test.assert(a ~= nil, (msg or '') .. ': value is nil (expected ' .. tostring(b) .. ')')
   Test.assert(math.abs(a - b) <= tol, string.format('%s: expected %.6f got %.6f', msg or '', b, a))
end

local function rnum(R, key)
   local v = R:num(key)
   if v == nil then
      local keys = {}
      for k in pairs(R.by_key) do table.insert(keys, k) end
      local notes = {}
      for _, n in ipairs(R.notes) do table.insert(notes, report.plain(n.text)) end
      error('missing result ' .. key .. ' (have: ' .. table.concat(keys, ',') .. ') notes: ' .. table.concat(notes, '; '))
   end
   return v
end

local function no_errors(R)
   for _, n in ipairs(R.notes) do
      Test.assert(n.kind ~= 'error', 'unexpected error note: ' .. report.plain(n.text))
   end
end

local test = {}

-- Core modules -----------------------------------------------------------------

function test.cas_input()
   local N = sym.NEGATE
   Test.assert(cas.input('-x^2+3*-t', { x = 'q9x', t = 'q9t' }) == N .. 'q9x^2+3*' .. N .. 'q9t')
   Test.assert(cas.input('a-b', {}) == 'a-b')
   Test.assert(cas.input('x<=-2', { x = 'q9x' }) == 'q9x' .. sym.LEQ .. N .. '2')
   Test.assert(cas.input('sqrt(4)') == sym.ROOT .. '(4)')
   Test.assert(cas.input('f11(t)', { t = 'q9t' }) == 'f11(q9t)')
   Test.assert(cas.input('  ') == nil)
end

function test.cas_parsing()
   local N = sym.NEGATE
   local s = cas.solutions('q9x=' .. N .. '2 or q9x=2', 'q9x')
   Test.assert(#s == 2 and s[2] == '2')
   Test.assert(#cas.solutions('false', 'x') == 0)
   Test.assert(cas.solutions('x^2=4', 'x') == nil)
   local l = cas.list('{1,2,{3,4}}')
   Test.assert(#l == 3 and l[3] == '{3,4}')
   Test.assert(cas.tonum(N .. '1.5' .. sym.EE .. N .. '3') == -1.5e-3)
   Test.assert(cas.display_name('q9t') == 't' and cas.display_name('q7x') == 'X')
end

function test.expand_periodic()
   local U = require 'apps.vce.solvers.util'
   local l = U.expand_solutions({ '@n1*' .. sym.pi, '2' }, 0, 10)
   Test.assert(#l == 5, 'count ' .. #l)
   near(cas.n(l[2]), 2, 1e-9, 'sorted')
   near(cas.n(l[3]), math.pi, 1e-9, 'pi')
   near(cas.n(l[5]), 3 * math.pi, 1e-9, '3pi')
end

function test.fmt_round()
   Test.assert(fmt.round(0.78870045, 4) == '0.7887')
   Test.assert(fmt.round(2.5, 4) == '2.5')
   Test.assert(fmt.round(-0.00001, 4) == sym.NEGATE .. '1*10^(' .. sym.NEGATE .. '5)')
   Test.assert(fmt.round_expr('0.123456*q9t^2', 4) == '0.1235*q9t^2')
   Test.assert(fmt.round_expr('q9t2+12') == 'q9t2+12')
end

function test.event_parse()
   local ev = require 'apps.vce.event'
   local e = ev.parse('45<X<55')
   Test.assert(e.lo == '45' and e.hi == '55' and not e.lo_inc)
   e = ev.parse('X>=3 | X>1')
   Test.assert(e.lo == '3' and e.lo_inc and e.given.lo == '1')
   e = ev.parse('55>x')
   Test.assert(e.hi == '55')
   e = ev.parse('P(X=2)')
   Test.assert(e.eq == '2')
   Test.assert(select(2, ev.int_range(2, false, 5, false)) == 4)
end

-- Pretty printer -------------------------------------------------------------------

function test.mathbox_layout()
   local mb = require 'ui.mathbox'
   mb.rename = cas.display_name
   local N = sym.NEGATE
   local exprs = {
      '3/8*q9x^2', sym.ROOT .. '(2)/2', 'q9x=' .. N .. '2 or q9x=2',
      'integral(3/8*q9x^2,q9x,0,q9m)=1/2', 'piecewise(3/8*q9x^2,0' .. sym.LEQ .. 'q9x' .. sym.LEQ .. '2,0)',
      'normCdf(' .. N .. sym.INFTY .. ',55,50,4)', '{0.1,0.2}', '[[1,2][3,4]]', 'abs(q9t-3)',
      sym.EULER .. '^(' .. N .. 'q9t/2)', '1.5' .. sym.EE .. N .. '7', 'derivative(q9t^3,q9t)', 'bar(X)',
      '(q9x+1)^2', '2*(' .. N .. '3)', 'a-(b-c)', 'log(8,2)', 'root(8,3)', 'nCr(5,2)*0.3^2',
   }
   for _, e in ipairs(exprs) do
      local b = mb.layout(e, 10)
      Test.assert(b and b.w > 0 and b.h > 0, 'layout ' .. e)
      -- drawing must not fail
      local calls = 0
      local g = setmetatable({}, { __index = function(_, k)
         return function() calls = calls + 1 return 6 end
      end })
      mb.draw(b, g, 0, 0)
      Test.assert(calls > 0, 'draw ' .. e)
   end
   -- fraction is taller than a single line
   Test.assert(mb.layout('1/2', 10).h > mb.layout('12', 10).h, 'fraction height')
   -- unparsable input falls back to text
   Test.assert(mb.layout('2+*', 10).w > 0, 'fallback')
end

-- Normal ----------------------------------------------------------------------------

function test.normal_forward()
   local R = run('normal', { mu = '50', sd = '4', event = '45<X<55' })
   no_errors(R)
   near(rnum(R, 'p'), 0.788700, 1e-5, 'P(45<X<55)')
   R = run('normal', { mu = '50', var = '16', event = 'X>58' })
   near(rnum(R, 'p'), 0.0227501, 1e-6, 'P(X>58)')
   near(rnum(R, 'sd'), 4, 1e-9, 'sd from var')
end

function test.normal_conditional()
   local R = run('normal', { mu = '50', sd = '4', event = 'X>55|X>50' })
   near(rnum(R, 'p'), 0.105649774 / 0.5, 1e-5, 'P(X>55|X>50)')
end

function test.normal_inverse()
   local R = run('normal', { mu = '50', sd = '4', event = 'X<k', p = '0.9' })
   no_errors(R)
   near(rnum(R, 'k'), 55.126206, 1e-4, 'k left')
   R = run('normal', { mu = '50', sd = '4', event = 'X>k', p = '0.1' })
   near(rnum(R, 'k'), 55.126206, 1e-4, 'k right')
   R = run('normal', { mu = '50', sd = '4', event = '50-c<X<50+c', p = '0.95' })
   near(rnum(R, 'k'), 7.839856, 1e-3, 'c symmetric')
end

function test.normal_area_to_x()
   local R = run('normal', { mu = '50', sd = '4', q = '0.99' })
   no_errors(R)
   near(rnum(R, 'q'), 50 + 4 * 2.326347874, 1e-4, 'x for area 0.99')
end

function test.normal_find_sigma_mu()
   local R = run('normal', { mu = '50', event = 'X<60', p = '0.95' })
   no_errors(R)
   near(rnum(R, 'sd'), 10 / 1.644853627, 1e-4, 'sigma')
   R = run('normal', { sd = '4', event = 'X>60', p = '0.05' })
   near(rnum(R, 'mu'), 60 - 4 * 1.644853627, 1e-4, 'mu')
end

function test.normal2()
   local R = run('normal2', { e1 = 'X<60', p1 = '0.9', e2 = 'X>40', p2 = '0.2' })
   no_errors(R)
   local z1, z2 = 1.2815515655, 0.8416212336
   local sd = 20 / (z1 - z2)
   near(rnum(R, 'sd'), sd, 1e-4, 'sigma')
   near(rnum(R, 'mu'), 60 - sd * z1, 1e-4, 'mu')
end

-- Binomial ------------------------------------------------------------------------

function test.binomial_probs()
   local R = run('binomial', { n = '10', p = '0.3', event = 'X>=3' })
   no_errors(R)
   near(rnum(R, 'prob'), 0.6172172136, 1e-8, 'P(X>=3)')
   near(rnum(R, 'mean'), 3, 1e-12, 'mean')
   near(rnum(R, 'var'), 2.1, 1e-12, 'var')
   R = run('binomial', { n = '10', p = '0.3', event = 'X=2' })
   near(rnum(R, 'prob'), 0.2334744405, 1e-8, 'P(X=2)')
   R = run('binomial', { n = '10', p = '0.3', event = 'X>2|X>=1' })
   near(rnum(R, 'prob'), 0.6172172136 / (1 - 0.7 ^ 10), 1e-8, 'conditional')
   R = run('binomial', { n = '10', p = '0.3', event = '2<=X<5' })
   near(rnum(R, 'prob'), mock.binom_cdf(10, 0.3, 2, 4), 1e-8, 'range')
end

function test.binomial_params()
   local R = run('binomial', { mean = '6', var = '4.2', event = 'X=6' })
   no_errors(R)
   near(rnum(R, 'n'), 20, 1e-9, 'n from mean/var')
   near(rnum(R, 'p'), 0.3, 1e-9, 'p from mean/var')
end

function test.binomial_find_n_p()
   local R = run('binomial', { p = '0.1', event = 'X>=1', pr = '>=0.95' })
   no_errors(R)
   near(rnum(R, 'n'), 29, 0, 'smallest n')
   R = run('binomial', { n = '4', event = 'X=0', pr = '0.0016' })
   no_errors(R)
   near(rnum(R, 'p'), 0.8, 1e-6, 'p from P(X=0)')
end

-- Discrete ------------------------------------------------------------------------

function test.discrete_unknown()
   local R = run('discrete', { x = '0,1,2,3', px = '0.1,k,2k,0.3', event = 'X>=2' })
   no_errors(R)
   near(rnum(R, 'k'), 0.2, 1e-9, 'k')
   near(rnum(R, 'mean'), 1.9, 1e-9, 'E(X)')
   near(rnum(R, 'var'), (0.2 + 1.6 + 2.7) - 1.9 ^ 2, 1e-9, 'Var(X)')
   near(rnum(R, 'prob'), 0.7, 1e-9, 'P(X>=2)')
end

function test.discrete_two_unknowns()
   local R = run('discrete', { x = '1,2,3', px = 'a,b,0.5', mean = '2.3' })
   no_errors(R)
   near(rnum(R, 'k'), 0.2, 1e-6, 'a')
   near(rnum(R, 'k2'), 0.3, 1e-6, 'b')
end

-- PDF -------------------------------------------------------------------------------

function test.pdf_basic()
   local R = run('pdf', { f1 = '3/8*x^2', a1 = '0', b1 = '2', event = 'X<1', q = '0.99' })
   no_errors(R)
   near(rnum(R, 'mean'), 1.5, 1e-6, 'E(X)')
   near(rnum(R, 'var'), 0.15, 1e-6, 'Var(X)')
   near(rnum(R, 'median'), 4 ^ (1 / 3), 1e-6, 'median')
   near(rnum(R, 'mode'), 2, 1e-3, 'mode')
   near(rnum(R, 'prob'), 1 / 8, 1e-6, 'P(X<1)')
   near(rnum(R, 'q'), (0.99 * 8) ^ (1 / 3), 1e-6, 'percentile')
end

function test.pdf_unknown_k()
   local R = run('pdf', { f1 = 'k*x*(2-x)', a1 = '0', b1 = '2', event = 'X>a', pr = '0.2' })
   no_errors(R)
   near(rnum(R, 'mean'), 1, 1e-6, 'E(X)')
   near(rnum(R, 'median'), 1, 1e-6, 'median')
   -- P(X>k)=0.2 => F(k)=0.8 with F(x)=3/4(x^2-x^3/3)
   local k = R:num('k')
   Test.assert(k ~= nil, 'k solved')
end

function test.pdf_piecewise()
   local R = run('pdf', { f1 = 'x', a1 = '0', b1 = '1', f2 = '2-x', a2 = '1', b2 = '2', event = '0.5<X<1.5' })
   no_errors(R)
   near(rnum(R, 'mean'), 1, 1e-6, 'E(X)')
   near(rnum(R, 'median'), 1, 1e-6, 'median')
   near(rnum(R, 'var'), 1 / 6, 1e-6, 'Var(X)')
   near(rnum(R, 'prob'), 0.75, 1e-6, 'P(0.5<X<1.5)')
   R = run('pdf', { f1 = 'x', a1 = '0', b1 = '1', f2 = '2-x', a2 = '1', b2 = '2', q = '0.875' })
   near(rnum(R, 'q'), 1.5, 1e-6, 'percentile in 2nd piece')
end

function test.pdf_exponential()
   local R = run('pdf', { f1 = '0.5*e^(-0.5x)', a1 = '0', b1 = 'inf', event = 'X>3' })
   no_errors(R)
   near(rnum(R, 'mean'), 2, 1e-4, 'E(X)')
   near(rnum(R, 'median'), 2 * math.log(2), 1e-5, 'median')
   near(rnum(R, 'prob'), math.exp(-1.5), 1e-5, 'P(X>3)')
end

-- Linear combinations -------------------------------------------------------------

function test.lincomb()
   local R = run('lincomb', { mx = '50', sx = '4', my = '30', sy = '3', comb = '2X-3Y', event = 'W>15' })
   no_errors(R)
   near(rnum(R, 'mean'), 10, 1e-9, 'E(2X-3Y)')
   near(rnum(R, 'var'), 4 * 16 + 9 * 9, 1e-9, 'Var(2X-3Y)')
   near(rnum(R, 'prob'), 1 - mock.phi(5 / math.sqrt(145)), 1e-6, 'P(W>15)')
   R = run('lincomb', { mx = '10', vx = '4', comb = 'X1+X2+X3' })
   near(rnum(R, 'var'), 12, 1e-9, 'Var(X1+X2+X3)')
   R = run('lincomb', { mx = '10', vx = '4', comb = '3X' })
   near(rnum(R, 'var'), 36, 1e-9, 'Var(3X)')
   R = run('lincomb', { mx = '10', sx = '2', my = '18', sy = '1', event = 'X1+X2>Y' })
   near(rnum(R, 'mean'), 2, 1e-9, 'E(X1+X2-Y)')
   near(rnum(R, 'prob'), 1 - mock.phi(-2 / 3), 1e-6, 'P(X1+X2>Y)')
end

-- Sampling ------------------------------------------------------------------------------

function test.sampling_ci()
   local R = run('sampling', { sd = '4', n = '25', xbar = '52', c = '95' })
   no_errors(R)
   near(rnum(R, 'se'), 0.8, 1e-12, 'SE')
   near(rnum(R, 'e'), 1.959963985 * 0.8, 1e-6, 'E')
   near(rnum(R, 'lo'), 52 - 1.959963985 * 0.8, 1e-6, 'CI lower')
   R = run('sampling', { sd = '4', e = '1', c = '0.95' })
   near(rnum(R, 'n'), 62, 0, 'sample size')
   R = run('sampling', { sd = '4', e = '1', z = '1.96' })
   near(rnum(R, 'n'), 62, 0, 'sample size z=1.96')
   R = run('sampling', { sd = '4', n = '25', lo = '50.432', hi = '53.568' })
   near(rnum(R, 'xbar'), 52, 1e-9, 'centre')
   near(rnum(R, 'c'), 0.95, 1e-4, 'level from interval')
   R = run('sampling', { mu = '50', sd = '4', n = '16', event = 'Xbar>52' })
   near(rnum(R, 'prob'), 1 - mock.phi(2), 1e-6, 'P(Xbar>52)')
end

-- Hypothesis test ---------------------------------------------------------------------

function test.hyptest()
   local R = run('hyptest', { mu0 = '50', h1 = '>', sd = '4', n = '25', xbar = '51.5', mu1 = '52' })
   no_errors(R)
   near(rnum(R, 'z'), 1.875, 1e-9, 'z')
   near(rnum(R, 'p'), 1 - mock.phi(1.875), 1e-6, 'p-value')
   Test.assert(R:get('decision') == '"reject H0"', 'decision')
   local c = 50 + 0.8 * 1.644853627
   near(rnum(R, 'c'), c, 1e-5, 'critical value')
   near(rnum(R, 'type2'), mock.phi((c - 52) / 0.8), 1e-5, 'Type II')
   R = run('hyptest', { mu0 = '50', h1 = '!=', sd = '4', n = '25', xbar = '48.6', alpha = '0.01' })
   near(rnum(R, 'p'), 2 * mock.phi(-1.75), 1e-6, 'two-sided p')
   Test.assert(R:get('decision') == '"do not reject H0"', 'decision two-sided')
   R = run('hyptest', { mu0 = '50', h1 = '<', sd = '4', n = '25', c = '48.5', mu1 = '48' })
   near(rnum(R, 'type1'), mock.phi(-1.875), 1e-6, 'Type I from rule')
   near(rnum(R, 'type2'), 1 - mock.phi(0.625), 1e-6, 'Type II from rule')
end

-- SUVAT ---------------------------------------------------------------------------------

function test.suvat()
   local R = run('suvat', { u = '0', a = '9.8', t = '2' })
   no_errors(R)
   near(rnum(R, 'v'), 19.6, 1e-9, 'v')
   near(rnum(R, 's'), 19.6, 1e-9, 's')
   R = run('suvat', { s = '10', u = '20', a = '-9.8' })
   near(rnum(R, 't1'), (20 - math.sqrt(400 - 196)) / 9.8, 1e-6, 't1')
   near(rnum(R, 't2'), (20 + math.sqrt(400 - 196)) / 9.8, 1e-6, 't2')
   near(rnum(R, 'v1'), math.sqrt(400 - 196), 1e-6, 'v1')
   R = run('suvat', { u = '5', v = '15', s = '40' })
   near(rnum(R, 't'), 4, 1e-9, 't')
   near(rnum(R, 'a'), 2.5, 1e-9, 'a')
   R = run('suvat', { s = '12', v = '0', t = '3' })
   near(rnum(R, 'u'), 8, 1e-9, 'u')
   near(rnum(R, 'a'), -8 / 3, 1e-9, 'a')
end

function test.suvat_doc_function()
   mock.functions['f11'] = { params = { 'x' }, body = 'x^2+1' }
   local R = run('suvat', { u = 'f11(1)', a = '3', t = '2' })
   near(rnum(R, 'v'), 8, 1e-9, 'v with f11')
   mock.functions['f11'] = nil
end

-- Kinematics ----------------------------------------------------------------------------

function test.kin_a_of_t()
   local R = run('kinematics', { type = 'a(t)', f = '6t', x0 = '1', v0 = '2', find = 't=2', t1 = '0', t2 = '2' })
   no_errors(R)
   near(rnum(R, 'q_v'), 14, 1e-6, 'v(2)')
   near(rnum(R, 'q_x'), 13, 1e-6, 'x(2)')
   near(rnum(R, 'q_a'), 12, 1e-4, 'a(2)')
   near(rnum(R, 'disp'), 12, 1e-6, 'displacement')
   near(rnum(R, 'dist'), 12, 1e-6, 'distance')
   R = run('kinematics', { type = 'a(t)', f = '6t', x0 = '1', v0 = '2', find = 'v=14' })
   near(rnum(R, 'q_t'), 2, 1e-6, 't when v=14')
end

function test.kin_v_of_t_distance()
   local R = run('kinematics', { type = 'v(t)', f = 't^2-4t+3', x0 = '0', t1 = '0', t2 = '4' })
   no_errors(R)
   near(rnum(R, 'disp'), 4 / 3, 1e-6, 'displacement')
   near(rnum(R, 'dist'), 4, 1e-5, 'distance')
end

function test.kin_x_of_t()
   local R = run('kinematics', { type = 'x(t)', f = 't^3-3t', find = 'v=0' })
   no_errors(R)
   near(rnum(R, 'q_t'), 1, 1e-6, 't at rest')
   near(rnum(R, 'q_x'), -2, 1e-6, 'x at rest')
end

function test.kin_a_of_v()
   local R = run('kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', x0 = '0', find = 'v=5' })
   no_errors(R)
   near(rnum(R, 'q_t'), 2 * math.log(2), 1e-5, 't when v=5')
   near(rnum(R, 'q_x'), 10, 1e-5, 'x when v=5')
   R = run('kinematics', { type = 'a(v)', f = '10-0.1v^2', v0 = '0', find = 'a=0' })
   near(rnum(R, 'vterm'), 10, 1e-6, 'terminal velocity')
end

function test.kin_a_of_x()
   local R = run('kinematics', { type = 'a(x)', f = '-4x', x0 = '0', v0 = '4', find = 'x=1' })
   no_errors(R)
   near(rnum(R, 'q_v'), 2 * math.sqrt(3), 1e-6, 'v at x=1')
   near(rnum(R, 'q_a'), -4, 1e-6, 'a at x=1')
   R = run('kinematics', { type = 'a(x)', f = '-4x', x0 = '0', v0 = '4', find = 't=pi/8' })
   near(rnum(R, 'q_x'), math.sqrt(2), 1e-4, 'x at t=pi/8')
end

function test.kin_v_of_x()
   local R = run('kinematics', { type = 'v(x)', f = '2x+1', x0 = '0', find = 't=1' })
   no_errors(R)
   near(rnum(R, 'q_x'), (math.exp(2) - 1) / 2, 1e-4, 'x(1)')
   near(rnum(R, 'q_v'), math.exp(2), 1e-3, 'v(1)')
end

-- Self-test cases (same as on the calculator) ------------------------------------------

function test.selftest_cases()
   local selftest = require 'apps.vce.selftest'
   for _, c in ipairs(selftest.cases) do
      local ok, got, _, err = selftest.run_case(c)
      Test.assert(ok, string.format('%s %s: got %s want %s %s', c[1], c[3], tostring(got), tostring(c[4]), err or ''))
   end
end

-- History persistence --------------------------------------------------------------------

function test.history_save_restore()
   local History = require 'apps.vce.history'
   local h = History.new()
   h:add('normal', { mu = '50', sd = '4' }, 'Q1a')
   h:add('suvat', { u = '0' })
   local h2 = History.load(h:save())
   Test.assert(#h2.items == 2, 'items restored')
   Test.assert(h2.items[1].tag == 'Q1a' and h2.items[1].inputs.mu == '50', 'content restored')
   Test.assert(h2.current == 2, 'current restored')
   local p = h2:add('pdf')
   Test.assert(p.id == 3, 'ids continue')
   Test.assert(#History.load(nil).items == 0, 'nil state')
   Test.assert(#History.load({ items = { { solver = 5 } } }).items == 0, 'bad state ignored')
end

-- UI smoke test: drive the app with key events and paint every screen ---------------------

local function paint_all()
   local ui = require 'ui'
   local calls = 0
   local g = setmetatable({}, { __index = function(_, k)
      if k == 'getStringWidth' then return function(_, s) return 6 * #(s or '') end end
      if k == 'getStringHeight' then return function() return 12 end end
      return function() calls = calls + 1 end
   end })
   ui.paint(ui.GC(g, 0, 0))
   return calls
end

function test.ui_smoke()
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   local solvers = require 'apps.vce.registry'
   local function key(name, ...) ui.on_event(name, ...) end
   local function type_text(s)
      for ch in s:gmatch('[\1-\127\194-\244][\128-\191]*') do key('char', ch) end
   end

   -- error dialogs push modals; fail the test instead
   local dlg_error = require 'dialog.error'
   local orig = dlg_error.display
   local errors = {}
   dlg_error.display = function(title, msg)
      if not tostring(msg):find('^Select') then
         table.insert(errors, tostring(title) .. ': ' .. tostring(msg))
      end
      return orig(title, msg)
   end

   app.open(nil)
   Test.assert(app.screen == 'home', 'starts at home')
   Test.assert(paint_all() > 0, 'home paints')

   for i, s in ipairs(solvers.list) do
      key('char', tostring(i % 10))
      Test.assert(app.screen == 'problem', 'opened ' .. s.id)
      -- fill the solver example through the UI
      for _, f in ipairs(s.fields) do
         local v = s.example and s.example[f.id]
         local row = app.sheet:selected()
         if row and row.id == f.id then
            if f.kind == 'choice' then
               for _ = 1, 10 do
                  if row.options[row.index][1] == (v or row.options[1][1]) then break end
                  key('right')
                  row = app.sheet:selected()
               end
               key('down')
            else
               if v then type_text(v) end
               key('enter_key')
            end
         end
      end
      local R = app.last_report
      Test.assert(R and #R.results > 0, s.id .. ' example has results')
      for _, n in ipairs(R.notes) do
         Test.assert(n.kind ~= 'error', s.id .. ' example error: ' .. report.plain(n.text))
      end
      paint_all()
      -- walk through all rows and toggle results
      for _ = 1, 60 do
         local row = app.sheet:selected()
         if row and row.kind == 'result' then key('enter_key') key('right') key('left') end
         key('down')
      end
      paint_all()
      key('escape')
      Test.assert(app.screen == 'home', 'back home from ' .. s.id)
   end

   -- history, filter, help, self-test
   key('char', 'h')
   Test.assert(app.screen == 'history', 'history screen')
   type_text('nor')
   paint_all()
   key('escape') key('escape')
   app.show_help() paint_all()
   app.show_selftest() paint_all()
   key('escape')

   -- every toolpalette entry runs
   local menu = app.menu()
   app.show_problem(1)
   for _, cat in ipairs(menu) do
      for k = 2, #cat do
         local title = cat[k][1]
         if not title:find('Delete') then
            cat[k][2]()
            -- close dialogs/menus opened by the action
            while #ui.modal > 1 do ui.pop_modal() end
            if ui.get_focus() ~= app.sheet then ui.set_focus(app.sheet) end
            paint_all()
         end
      end
   end

   -- save/restore round trip
   local state = app.save_state()
   app.restore_state(state)
   Test.assert(#app.history.items == #solvers.list + 2 or #app.history.items > 0, 'history kept')
   dlg_error.display = orig
   app.set_dp(4)
   app.set_font('normal')
   Test.assert(#errors == 0, 'errors: ' .. table.concat(errors, '; '))
end

function test.ui_dynamic_fields()
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   app.open(nil)
   app.new_problem('pdf')
   local function type_text(str)
      for ch in str:gmatch('[\1-\127\194-\244][\128-\191]*') do ui.on_event('char', ch) end
   end
   Test.assert(app.sheet:selected().id == 'f1', 'starts on f(x)')
   type_text('x/2')
   ui.on_event('down')
   Test.assert(app.sheet:selected().id == 'a1', 'down after typing f(x) goes to "from"')
   type_text('0') ui.on_event('tab')
   type_text('2') ui.on_event('enter_key')
   Test.assert(app.sheet:selected().id == 'f2', 'enter moves to the 2nd piece')
   -- results toggle by click
   local R = app.last_report
   near(R:num('mean'), 4 / 3, 1e-6, 'mean of x/2 on [0,2]')
   local idx
   for k, r in ipairs(app.sheet.rows) do
      if r.kind == 'result' and r.key == 'res:mean' then idx = k end
   end
   app.sheet:select(idx)
   ui.on_event('enter_key')
   Test.assert(app.sheet:selected().mode == 'approx', 'enter toggles to decimal')
   ui.on_event('enter_key')
   Test.assert(app.sheet:selected().mode == 'exact', 'enter toggles back')
   -- tag via t on a result row, then the history filter finds it
   local p = app.current()
   p.tag = 'Q7c'
   app.show_history()
   app.filter = 'q7'
   app.show_history()
   Test.assert(app.sheet.rows[1].kind == 'link' and app.sheet.rows[1].title:find('Q7c'), 'history filter by tag')
   app.filter = ''
   ui.on_event('escape')
end

Test.run(test)
