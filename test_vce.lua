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
-- Chinese text of the bilingual document (vce_zh.lua installs it; the
-- English-only documents do not, see test.english_only)
local i18n_zh = require 'apps.vce.i18n_zh'
require('apps.vce.i18n').install(i18n_zh)

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
   -- view-only inputs (graph window, kinematics Find) as the app applies them
   if s.view then s.view(inputs, R) end
   if VERBOSE then
      local function out(s) io.stderr:write(s .. '\n') end
      out('== ' .. solver_id)
      for _, n in ipairs(R.notes) do out('  note: ' .. report.plain(n.text)) end
      for _, r in ipairs(R.results) do out('  ' .. report.plain(r.label) .. ' = ' .. fmt.plain(r.exact)) end
      for _, st in ipairs(R.steps) do out('    | ' .. report.plain(st.text)) end
   end
   return R
end

local function U_neg(x) return sym.NEGATE .. x end

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

function test.cas_memo()
   local calls = 0
   local orig = cas.backend
   cas.backend = function(e) calls = calls + 1 return orig(e) end
   Test.assert(cas.pure('derivative(q9x^2,q9x)|q9x>0 and q9x<1'), 'built-ins and local symbols are pure')
   Test.assert(not cas.pure('f11(q9x)'), 'document function')
   Test.assert(not cas.pure('q9x+mass'), 'document variable')
   cas.eval('2+3')
   cas.eval('2+3')
   Test.assert(calls == 1, 'pure expression evaluated once')
   cas.eval('mass+1')
   cas.eval('mass+1')
   Test.assert(calls == 3, 'document expressions always evaluated')
   cas.clear_memo()
   cas.eval('2+3')
   Test.assert(calls == 4, 'memo cleared')
   cas.backend = orig
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

-- Calculus: numeric evaluator, plot ----------------------------------------------------

function test.numeric_compile()
   local numeric = require 'apps.vce.numeric'
   local N = sym.NEGATE
   local f = numeric.compile(N .. 'q9x^2+3*q9x', { 'q9x' })
   near(f(2), 2, 1e-12, 'polynomial')
   near(numeric.compile('q9x^(1/3)', { 'q9x' })(-8), -2, 1e-12, 'odd root of a negative')
   Test.assert(numeric.compile('ln(q9x)', { 'q9x' })(-1) == nil, 'ln of a negative is undefined')
   Test.assert(numeric.compile('1/q9x', { 'q9x' })(0) == nil, 'division by zero is undefined')
   near(numeric.compile(sym.EULER .. '^(q9x)', { 'q9x' })(1), math.exp(1), 1e-12, 'e^x')
   near(numeric.compile('derivative(q9x^3,q9x)', { 'q9x' })(2), 12, 1e-5, 'derivative()')
   near(numeric.compile('piecewise(q9x,q9x<0,2*q9x)', { 'q9x' })(3), 6, 1e-12, 'piecewise')
   Test.assert(numeric.compile('q9x+zz', { 'q9x' }) == nil, 'free symbol rejected')
   -- endpoint singularity: integral of 1/sqrt(x) on [0, 1] = 2
   near(numeric.integrate(function(x) return 1 / math.sqrt(x) end, 0, 1, 200), 2, 2e-3, 'singular endpoint')
   near(numeric.integrate(function(x) return x * x end, 0, 3, 50), 9, 1e-9, 'x^2')
end

function test.plot_draw()
   local plot = require 'ui.plot'
   local calls = 0
   local g = setmetatable({}, { __index = function(_, k)
      if k == 'getStringWidth' then return function(_, s) return 6 * #(s or '') end end
      if k == 'getStringHeight' then return function() return 12 end end
      return function() calls = calls + 1 end
   end })
   local spec = {
      xmin = -4, xmax = 4,
      curves = { { fn = function(x) return x ~= 1 and 1 / (x - 1) or nil end },
                 { kind = 'param', fx = math.cos, fy = math.sin, tmin = 0, tmax = 2 * math.pi } },
      asymptotes = { { kind = 'v', x = 1 }, { kind = 'h', y = 0 }, { kind = 'f', fn = function(x) return x end } },
      points = { { x = 0, y = -1, kind = 'max', label = 'max' }, { x = 2, y = 1, kind = 'hole' } },
      shade = { { kind = 'x', top = function(x) return x * x end, a = 0, b = 1 } },
      field = { fn = function(x, y) return x + y end },
   }
   plot.auto_range(spec)
   Test.assert(spec.ymin < spec.ymax, 'y range')
   plot.draw(g, { x = 0, y = 0, width = 300, height = 180 }, spec, { labels = true, cursor = { x = 0.5, y = 2 } })
   Test.assert(calls > 50, 'plot draws (' .. calls .. ' calls)')
   Test.assert(plot.nice_step(7.3) > 0, 'nice step')
end

function test.plot_cache()
   local plot = require 'ui.plot'
   local evals = 0
   local g = setmetatable({}, { __index = function(_, k)
      if k == 'getStringWidth' then return function(_, s) return 6 * #(s or '') end end
      if k == 'getStringHeight' then return function() return 12 end end
      return function() end
   end })
   local spec = { xmin = -3, xmax = 3, curves = { { fn = function(x) evals = evals + 1 return x * x end } },
                  points = { { x = 0, y = 0, kind = 'min', label = 'min (0, 0)' } } }
   local r = { x = 10, y = 20, width = 200, height = 120 }
   plot.draw(g, r, spec, { labels = true })
   local first = evals
   Test.assert(first > 100, 'curve sampled')
   plot.draw(g, { x = 10, y = 60, width = 200, height = 120 }, spec, { labels = true, cursor = { x = 1, y = 1 } })
   Test.assert(evals == first, 'repaint (moved, with cursor) replays without sampling')
   spec.xmin = -4
   plot.draw(g, r, spec, { labels = true })
   Test.assert(evals > first, 'new window samples again')
end

-- Function graph analysis ---------------------------------------------------------------

local function all_pairs(R, key)
   local out = {}
   for _, r in ipairs(R.results) do
      if r.key == key and r.pair then
         table.insert(out, { cas.n(r.pair[1]), cas.n(r.pair[2]) })
      end
   end
   return out
end

local function count_key(R, key)
   local n = 0
   for _, r in ipairs(R.results) do if r.key == key then n = n + 1 end end
   return n
end

-- number on the right of an equation result such as 'q9x=2'
local function rhs_num(R, key)
   local e = R:get(key)
   Test.assert(e, 'missing result ' .. key)
   return cas.n(e:match('=(.+)$'))
end

-- value of the line 'q9y=...' at x
local function line_at(eq, x)
   local rhs = eq:match('^q9y=(.+)$')
   return rhs and cas.n(cas.with(rhs, { { 'q9x', cas.num(x) } }))
end

function test.graph_rational()
   local R = run('graph', { f = '(x^2-1)/(x-2)', xmin = '-6', xmax = '8' })
   no_errors(R)
   near(rhs_num(R, 'va'), 2, 1e-9, 'x = 2')
   Test.assert(count_key(R, 'oa') == 1, 'one oblique asymptote (both sides)')
   near(line_at(R:get('oa'), 10), 12, 1e-3, 'y = x + 2')
   local mx, my = R:pair_num('max')
   near(mx, 2 - math.sqrt(3), 1e-6, 'max x')
   near(my, 4 - 2 * math.sqrt(3), 1e-6, 'max y')
   local nx, ny = R:pair_num('min')
   near(nx, 2 + math.sqrt(3), 1e-6, 'min x')
   near(ny, 4 + 2 * math.sqrt(3), 1e-6, 'min y')
   Test.assert(#all_pairs(R, 'xint') == 2, 'two x-intercepts')
   near(select(2, R:pair_num('yint')), 0.5, 1e-9, 'y-intercept')
   Test.assert(count_key(R, 'cusp') == 0, 'no corners near the asymptote')
   Test.assert(R.graph and #R.graph.asymptotes == 2 and #R.graph.curves == 1, 'graph spec')
end

function test.graph_asymptotes_and_points()
   local R = run('graph', { f = 'x*e^(-x)', xmin = '-1', xmax = '6' })
   near(rhs_num(R, 'ha'), 0, 1e-9, 'y = 0')
   near(select(1, R:pair_num('max')), 1, 1e-6, 'max at x = 1')
   local px, py = R:pair_num('poi')
   near(px, 2, 1e-6, 'inflection x')
   near(py, 2 * math.exp(-2), 1e-6, 'inflection y')
   Test.assert(count_key(R, 'poi') == 1, 'one inflection point')

   R = run('graph', { f = '1/(x^2-1)', xmin = '-4', xmax = '4' })
   Test.assert(count_key(R, 'va') == 2 and count_key(R, 'ha') == 1, 'x = ' .. '\194\177' .. '1, y = 0')

   R = run('graph', { f = 'ln(x)', xmin = '-1', xmax = '5' })
   near(rhs_num(R, 'va'), 0, 1e-9, 'ln: x = 0')
   Test.assert(count_key(R, 'endpoint') == 0, 'ln: no endpoint')

   R = run('graph', { f = 'tan(x)', xmin = '-3', xmax = '3' })
   Test.assert(count_key(R, 'va') == 2 and count_key(R, 'cusp') == 0, 'tan: two asymptotes')

   R = run('graph', { f = 'sqrt(x^2+1)', xmin = '-6', xmax = '6' })
   Test.assert(count_key(R, 'oa') == 2, 'y = ' .. '\194\177' .. 'x')
end

function test.graph_discontinuities()
   local R = run('graph', { f = '(x^2-4)/(x-2)', xmin = '-5', xmax = '5' })
   local hx, hy = R:pair_num('hole')
   near(hx, 2, 1e-9, 'hole x')
   near(hy, 4, 1e-6, 'hole y')
   Test.assert(count_key(R, 'va') == 0 and count_key(R, 'poi') == 0, 'removable, straight line')

   R = run('graph', { f = 'sqrt(x-1)', xmin = '-2', xmax = '6' })
   near(select(1, R:pair_num('endpoint')), 1, 1e-9, 'closed endpoint')

   R = run('graph', { f = 'abs(x^2-4)', xmin = '-4', xmax = '4' })
   local c = all_pairs(R, 'cusp')
   Test.assert(#c == 2, 'corners at ' .. '\194\177' .. '2')
   near(c[2][1], 2, 1e-9, 'corner x')
   Test.assert(count_key(R, 'poi') == 0, 'no inflection at a corner')

   R = run('graph', { f = 'x^(2/3)', xmin = '-3', xmax = '3' })
   near(select(1, R:pair_num('cusp')), 0, 1e-9, 'cusp at 0')

   R = run('graph', { f = 'x^(1/3)', xmin = '-3', xmax = '3' })
   Test.assert(count_key(R, 'cusp') == 1 and count_key(R, 'poi') == 1, 'vertical tangent: inflection, not differentiable')
end

function test.graph_options()
   local R = run('graph', { f = '1/x', xmin = '-4', xmax = '4', asym = 'hide', labels = 'hide', turn = 'hide' })
   local hide = R.graph.hide or {}
   Test.assert(hide.asym and hide.max and hide.min, 'hidden features')
   Test.assert(R.graph_labels == false, 'labels off')
   R = run('graph', { f = 'x^2', xmin = '3', xmax = '1' })
   Test.assert(#R.notes > 0, 'bad window reported')
end

-- Area, volume, arc length, surface area ----------------------------------------------

function test.revolution_y_of_x()
   local R = run('revolution', { type = 'y', f = 'sqrt(x)', a = '0', b = '4', axis = 'x' })
   no_errors(R)
   near(rnum(R, 'area'), 16 / 3, 1e-3, 'area')
   near(rnum(R, 'vol'), 8 * math.pi, 1e-6, 'disc volume')
   near(rnum(R, 'len'), 4.646783762, 1e-4, 'arc length')
   near(rnum(R, 'sa'), math.pi / 6 * (17 ^ 1.5 - 1), 1e-3, 'surface area')
   Test.assert(R.graph and #R.graph.shade == 1, 'shaded region')

   R = run('revolution', { type = 'y', f = 'x^2-1', a = '-2', b = '2', axis = 'x' })
   near(rnum(R, 'area'), 4, 1e-6, 'area split at the zeros')
   near(rnum(R, 'area_signed'), 4 / 3, 1e-6, 'signed integral')
   near(rnum(R, 'vol'), 2 * math.pi * (32 / 5 - 16 / 3 + 2), 1e-5, 'volume')
end

function test.revolution_between_and_y_axis()
   local R = run('revolution', { type = 'y', f = 'x^2', g = 'x', a = '0', b = '1', axis = 'y' })
   near(rnum(R, 'area'), 1 / 6, 1e-6, 'area between curves')
   near(rnum(R, 'vol_shell'), math.pi / 6, 1e-6, 'shells')

   R = run('revolution', { type = 'x', f = 'y^2', a = '0', b = '2', axis = 'y' })
   near(rnum(R, 'area'), 8 / 3, 1e-6, 'x = g(y) area')
   near(rnum(R, 'vol'), 32 * math.pi / 5, 1e-5, 'x = g(y) volume about y-axis')
end

function test.revolution_y_limits_and_letters()
   -- y = x^2 between y = 1 and y = 4, beside the y-axis
   local R = run('revolution', { type = 'y', f = 'x^2', lim = 'y', a = '1', b = '4', axis = 'y' })
   no_errors(R)
   near(rnum(R, 'area'), 14 / 3, 1e-6, 'area beside the y-axis')
   near(rnum(R, 'vol'), 7.5 * math.pi, 1e-6, 'volume about the y-axis: pi*int(y, 1, 4)')
   Test.assert(R.graph and R.graph.hlines and #R.graph.hlines == 2, 'lines y = 1 and y = 4')
   -- the same typed as 'y=1' and 'y=4'
   R = run('revolution', { type = 'y', f = 'x^2', a = 'y=1', b = 'y=4', axis = 'y' })
   near(rnum(R, 'vol'), 7.5 * math.pi, 1e-6, 'limits typed as y=...')
   -- about the x-axis: shells 2*pi*int(y*sqrt(y), 1, 4)
   R = run('revolution', { type = 'y', f = 'x^2', lim = 'y', a = '1', b = '4', axis = 'x' })
   near(rnum(R, 'vol_shell'), 2 * math.pi * 0.4 * 31, 1e-5, 'shells about the x-axis')
   -- a letter in the limits: answers in terms of a, and a box to give V
   local S = require 'apps.vce.solvers.revolution'
   local I = { type = 'y', f = 'sqrt(x)', a = '0', b = 'a', axis = 'x' }
   R = run('revolution', I)
   local asks = false
   for _, n in ipairs(R.notes) do
      Test.assert(n.kind ~= 'error', 'no error: ' .. report.plain(n.text))
      if n.text:find('^Answers in terms of a') then asks = true end
   end
   Test.assert(asks, 'says the answers are in terms of a')
   Test.assert(R:get('vol') and R:get('vol'):find('q9a', 1, true), 'volume in terms of a')
   Test.assert(not R.graph, 'no graph without a value for a')
   local shown = false
   for _, f in ipairs(S.fields) do
      if f.id == 'known' then shown = f.show(I) end
   end
   Test.assert(shown, 'given box shown when there is a letter')
   -- a given volume finds a, then everything is worked out
   I.known = 'V=8pi'
   R = run('revolution', I)
   no_errors(R)
   near(rnum(R, 'param_a'), 4, 1e-6, 'a from V = 8pi')
   near(rnum(R, 'vol'), 8 * math.pi, 1e-6, 'volume with a = 4')
   near(rnum(R, 'area'), 16 / 3, 1e-3, 'area with a = 4')
   Test.assert(R.graph, 'graph once a is known')
   I.known = 'A=16/3'
   R = run('revolution', I)
   near(rnum(R, 'param_a'), 4, 1e-4, 'a from the area')
   I.known = 'a=4'
   R = run('revolution', I)
   near(rnum(R, 'vol'), 8 * math.pi, 1e-6, 'a given directly')
   -- a letter in the curve
   R = run('revolution', { type = 'y', f = 'k*x', a = '0', b = '2', axis = 'x', known = 'V=24pi' })
   near(rnum(R, 'param_k'), 3, 1e-4, 'k from V: pi*k^2*8/3 = 24pi')
end

function test.revolution_parametric()
   local R = run('revolution', { type = 'param', f = '2cos(t)', g = '2sin(t)', a = '0', b = 'pi', axis = 'x' })
   near(rnum(R, 'len'), 2 * math.pi, 1e-5, 'semicircle length')
   near(rnum(R, 'area'), 2 * math.pi, 1e-5, 'semicircle area')
   near(rnum(R, 'vol'), 32 * math.pi / 3, 1e-4, 'sphere volume')
   near(rnum(R, 'sa'), 16 * math.pi, 1e-4, 'sphere surface area')
   Test.assert(R.graph.curves[1].kind == 'param', 'parametric curve')
   R = run('revolution', { type = 'y', f = 'x', a = '2', b = '1' })
   Test.assert(#R.notes > 0 and R:num('area') == nil, 'bad limits')
end

-- DE models -----------------------------------------------------------------------------

function test.demodels_growth_cooling()
   local R = run('demodels', { type = 'growth', y0 = '100', t1 = '5', y1 = '150', find = 't=10' })
   no_errors(R)
   near(rnum(R, 'k'), math.log(1.5) / 5, 1e-9, 'k')
   near(rnum(R, 'q_y'), 225, 1e-6, 'N(10)')
   near(rnum(R, 'double'), 5 * math.log(2) / math.log(1.5), 1e-6, 'doubling time')
   R = run('demodels', { type = 'growth', y0 = '80', half = '3', find = 'N=10' })
   near(rnum(R, 'q_t'), 9, 1e-6, 'three half-lives')

   R = run('demodels', { type = 'cooling', y0 = '90', cap = '20', t1 = '5', y1 = '60', find = 't=10' })
   near(rnum(R, 'k'), math.log(7 / 4) / 5, 1e-9, 'cooling k')
   near(rnum(R, 'q_y'), 20 + 70 * (4 / 7) ^ 2, 1e-6, 'T(10)')
end

function test.demodels_logistic_mixing()
   local R = run('demodels', { type = 'logistic', y0 = '10', cap = '100', k = '0.4', find = 't=5' })
   near(rnum(R, 'tinf'), math.log(9) / 0.4, 1e-6, 'fastest growth')
   near(rnum(R, 'maxrate'), 10, 1e-9, 'rK/4')
   near(rnum(R, 'q_y'), 100 / (1 + 9 * math.exp(-2)), 1e-6, 'P(5)')

   R = run('demodels', { type = 'mixing', V0 = '100', rin = '2', cin = '0.5', rout = '2', y0 = '0', find = 't=20' })
   near(rnum(R, 'qlim'), 50, 1e-9, 'limiting amount')
   near(rnum(R, 'q_y'), 50 - 50 * math.exp(-0.4), 1e-6, 'Q(20)')
end

function test.demodels_euler_related()
   local R = run('demodels', { type = 'general', f = 'x+y', x0 = '0', yg0 = '1', h = '0.1', xn = '0.3' })
   near(rnum(R, 'euler'), 1.362, 1e-9, 'Euler')
   Test.assert(R.graph and R.graph.field, 'slope field')

   R = run('demodels', { type = 'related', rel = '4/3*pi*r^3', rate = '10', at = '5' })
   near(rnum(R, 'dq'), 100 * math.pi, 1e-4, 'dV/dr')
   near(rnum(R, 'rate'), 10 / (100 * math.pi), 1e-6, 'dr/dt from dV/dt')
   R = run('demodels', { type = 'related', given = 'dx', rel = '4/3*pi*r^3', rate = '10', at = '5' })
   near(rnum(R, 'rate'), 1000 * math.pi, 1e-3, 'dV/dt from dr/dt')
end

function test.kin_formula_working_and_domain()
   local R = run('kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', x0 = '0', find = 'v=5' })
   local st = R:steps_for('xv')
   Test.assert(st and #st >= 3, 'x(v) has its own working')
   local text = {}
   for _, s in ipairs(st) do table.insert(text, report.plain(s.text)) end
   text = table.concat(text, ' | ')
   Test.assert(text:find('Given a', 1, true) and text:find('dx/dv = v/a', 1, true), 'given and x(v) steps: ' .. text)
   Test.assert(not text:find('dt/dv', 1, true), 'no t(v) steps in x(v) working')
   Test.assert(R.by_key.xv.domain == '0<q9v' .. sym.LEQ .. '10', 'x(v) domain: ' .. tostring(R.by_key.xv.domain))
   Test.assert(R.by_key.tv.domain == R.by_key.xv.domain, 't(v) domain')
   near(rnum(R, 'q_a'), -2.5, 1e-9, 'a at v = 5')
   Test.assert(R:steps_for('q_x') == nil, 'numeric answers have no separate working')

   R = run('kinematics', { type = 'a(x)', f = '-4x', x0 = '0', v0 = '4' })
   Test.assert(R.by_key.v2x.domain == U_neg('2') .. sym.LEQ .. 'q9x' .. sym.LEQ .. '2', 'v^2 domain: ' .. tostring(R.by_key.v2x.domain))
   Test.assert(R.by_key.vx.domain == '0' .. sym.LEQ .. 'q9x' .. sym.LEQ .. '2', 'v(x) domain: ' .. tostring(R.by_key.vx.domain))

   R = run('kinematics', { type = 'a(t)', f = '6t', x0 = '1', v0 = '2' })
   Test.assert(R.by_key.xt.domain == 'q9t' .. sym.GEQ .. '0', 'x(t) domain')
end

function test.kin_find_choice()
   local function notes(R)
      local t = {}
      for _, n in ipairs(R.notes) do table.insert(t, report.plain(n.text)) end
      return t
   end
   local function keys(R)
      local t = {}
      for _, r in ipairs(R.results) do t[r.key] = true end
      return t
   end
   -- only the chosen quantity, labelled with the condition
   local R = run('kinematics', { type = 'a(t)', f = '6t', x0 = '1', v0 = '2', want = 'x', find = 't=2' })
   Test.assert(#R.results == 1 and R.results[1].key == 'q_x', 'only x shown')
   near(rnum(R, 'q_x'), 13, 1e-6, 'x when t = 2')
   Test.assert(report.plain(R.results[1].label):find('t = 2', 1, true), 'label names the condition')
   R = run('kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', x0 = '0', want = 'a', find = 'v=5' })
   Test.assert(#R.results == 1, 'only a shown')
   near(rnum(R, 'q_a'), -2.5, 1e-9, 'a when v = 5')
   -- without a 'when': the formulas for that quantity
   R = run('kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', x0 = '0', want = 'x' })
   local k = keys(R)
   Test.assert(k.xv and not k.tv and not k.av, 'only x formulas')
   -- the constant found on the way stays
   R = run('kinematics', { type = 'a(v)', f = '-k*v^2', v0 = '10', x0 = '0', c2 = 'a=-4.9 when v=7',
                           want = 'x', find = 'v=5' })
   k = keys(R)
   Test.assert(k.param_k and k.q_x and not k.q_t, 'constant and x only')
   -- not enough conditions: one clear note naming what to give
   R = run('kinematics', { type = 'a(t)', f = '6t', v0 = '2', want = 'x', find = 't=2' })
   local n = notes(R)
   Test.assert(#R.results == 0, 'nothing to show')
   Test.assert(#n == 1 and n[1]:find('^Not enough conditions to find x when t = 2: give x0'), 'asks for x0: ' .. table.concat(n, '; '))
   R = run('kinematics', { type = 'a(t)', f = '6t', want = 'v', find = 't=2' })
   Test.assert(notes(R)[1]:find('give v0', 1, true), 'asks for v0')
   R = run('kinematics', { type = 'a(x)', f = '-4x', want = 't', find = 'x=1' })
   Test.assert(notes(R)[1]:find('give t0', 1, true), 'asks for t0')
   -- everything: values that can be found, plus a note for the rest
   R = run('kinematics', { type = 'a(t)', f = '6t', v0 = '2', find = 't=2' })
   near(rnum(R, 'q_v'), 14, 1e-6, 'v still found')
   n = notes(R)
   Test.assert(#n == 1 and n[1]:find('find x when t = 2: give x0', 1, true), 'note for x only: ' .. table.concat(n, '; '))
   -- asking for the quantity in the condition
   R = run('kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', want = 'v', find = 'v=5' })
   Test.assert(notes(R)[1]:find('^You already know v'), 'already known')
   -- switching Find only changes the view: no new solve
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   app.open(nil)
   app.new_problem('kinematics', { type = 'a(t)', f = '6t', x0 = '1', v0 = '2', find = 't=2' })
   local all = #app.last_report.results
   local calls = 0
   local orig = cas.backend
   cas.backend = function(e) calls = calls + 1 return orig(e) end
   for i, r in ipairs(app.sheet.rows) do
      if r.id == 'want' then app.sheet:select(i) end
   end
   ui.on_event('right')
   Test.assert(app.current().inputs.want == 'x', 'Find set to x')
   Test.assert(#app.last_report.results == 1 and #app.last_report.results < all, 'only x shown in the app')
   Test.assert(calls == 0, 'no new solve (' .. calls .. ' CAS calls)')
   ui.on_event('left')
   Test.assert(#app.last_report.results == all, 'everything again')
   cas.backend = orig
   ui.on_event('escape')
end

function test.kin_unknown_constant()
   -- a = -k v^2 with a = -4.9 when v = 7 (k = 0.1), v0 = 10
   local R = run('kinematics', { type = 'a(v)', f = '-k*v^2', v0 = '10', x0 = '0', c2 = 'a=-4.9 when v=7', find = 'v=5' })
   no_errors(R)
   near(rnum(R, 'param_k'), 0.1, 1e-12, 'k')
   near(rnum(R, 'q_t'), 1, 1e-6, 't when v = 5')
   near(rnum(R, 'q_x'), 10 * math.log(2), 1e-6, 'x when v = 5')
   -- same with function notation, and no initial state at all
   R = run('kinematics', { type = 'a(v)', f = '-k*v^2', c2 = 'a(7)=-4.9', find = 'a=-0.4' })
   near(rnum(R, 'param_k'), 0.1, 1e-12, 'k from a(7)')
   local vs = {}
   for _, r in ipairs(R.results) do
      if r.key and r.key:find('^q_v') then table.insert(vs, math.abs(cas.n(r.exact))) end
   end
   Test.assert(#vs >= 1 and math.abs(vs[1] - 2) < 1e-6, 'v when a = -0.4')
   local general = false
   for _, st in ipairs(R.steps) do
      if report.plain(st.text):find('+c', 1, true) then general = true end
   end
   Test.assert(general, 'general solution with +c without an initial state')
   -- missing condition
   R = run('kinematics', { type = 'a(v)', f = '-k*v', v0 = '10' })
   local warned = false
   for _, n in ipairs(R.notes) do
      if n.text:find('Unknown constant k', 1, true) then warned = true end
   end
   Test.assert(warned, 'asks for a condition')
end

-- Self-test cases (same as on the calculator) ------------------------------------------

-- Functions (Maths Methods) ------------------------------------------------------------

local function has_note(R, pat)
   for _, n in ipairs(R.notes) do
      if report.plain(n.text):find(pat) then return true end
   end
   return false
end

local function has_step(R, pat)
   for _, st in ipairs(R.steps) do
      if report.plain(st.text):find(pat) then return true end
   end
   return false
end

function test.cas_input_implicit()
   local U = require 'apps.vce.solvers.util'
   local map = U.locals_map()
   Test.assert(cas.input('kx+2y', map, false, true) == 'q9k*q9x+2q9y', 'kx -> k*x')
   Test.assert(cas.input('k(x-1)', map, false, true) == 'q9k*(q9x-1)', 'k(x-1) -> k*(x-1)')
   Test.assert(cas.input('sin(x)+ln(x)', map, false, true) == 'sin(q9x)+ln(q9x)', 'functions kept')
   Test.assert(cas.input('kx', map) == 'kx', 'off unless asked')
   Test.assert(cas.display_name('q8l') == '\206\187', 'free parameter shows as lambda')
end

function test.params_conditions()
   -- f(x) = ax^3+bx^2+c with f(1)=3, f'(2)=0, (0,1): -x^3+3x^2+1
   local R = run('params', { f = 'a*x^3+b*x^2+c', c1 = 'f(1)=3', c2 = "f'(2)=0", c3 = '(0,1)' })
   no_errors(R)
   near(rnum(R, 'param_a'), -1, 1e-6, 'a')
   near(rnum(R, 'param_b'), 3, 1e-6, 'b')
   near(rnum(R, 'param_c'), 1, 1e-9, 'c')
   Test.assert(R.graph and #R.graph.points >= 1, 'graph with the given point')
   Test.assert(has_step(R, '^Solve the 3 equations'), 'solved simultaneously')
   -- turning point and a point; implicit products
   R = run('params', { f = 'ax^2+bx+c', c1 = 'tp(1,2)', c2 = '(0,3)' })
   no_errors(R)
   near(rnum(R, 'param_a'), 1, 1e-6, 'a from tp')
   near(rnum(R, 'param_b'), -2, 1e-6, 'b from tp')
   near(rnum(R, 'param_c'), 3, 1e-9, 'c from point')
   -- tangent and asymptotes
   R = run('params', { f = 'a*x^2+b*x', c1 = 'tangent y=2x+1 at x=1' })
   near(rnum(R, 'param_a'), -1, 1e-6, 'a from tangent')
   near(rnum(R, 'param_b'), 4, 1e-6, 'b from tangent')
   R = run('params', { f = 'a/(x-b)+c', c1 = 'x=2 asymptote', c2 = 'asymptote y=3', c3 = '(3,5)' })
   near(rnum(R, 'param_b'), 2, 1e-6, 'vertical asymptote')
   near(rnum(R, 'param_c'), 3, 1e-6, 'horizontal asymptote')
   near(rnum(R, 'param_a'), 2, 1e-6, 'a from the point')
   Test.assert(R.graph.asymptotes and #R.graph.asymptotes == 2, 'asymptotes drawn')
   -- one unknown, and too few conditions
   R = run('params', { f = 'k*e^(-x)', c1 = 'f(0)=4' })
   near(rnum(R, 'param_k'), 4, 1e-9, 'k')
   R = run('params', { f = 'a*x^2+b', c1 = 'f(1)=2' })
   Test.assert(has_note(R, '2 unknowns %(a, b%) need 2 conditions'), 'asks for another condition')
   R = run('params', { f = 'a*x+b', c1 = 'f(1)' })
   Test.assert(has_note(R, 'Condition 1'), 'bad condition reported')
   -- the number of condition boxes follows the number of unknowns
   local S = require 'apps.vce.solvers.params'
   local shown = 0
   for _, f in ipairs(S.fields) do
      if f.id:match('^c%d') and (not f.show or f.show({ f = 'a*x^3+b*x^2+c' })) then shown = shown + 1 end
   end
   Test.assert(shown == 3, 'three boxes for a, b, c (got ' .. shown .. ')')
end

function test.transform_forms()
   -- image written with f
   local R = run('transform', { f = 'x^2', g = '-2f(3x-6)+4', pt = '(1,1)' })
   no_errors(R)
   near(rnum(R, 'A'), -2, 1e-9, 'A')
   near(rnum(R, 'n'), 3, 1e-9, 'n')
   near(rnum(R, 'b'), -2, 1e-9, 'b')
   near(rnum(R, 'c'), 4, 1e-9, 'c')
   local x, y = R:pair_num('image')
   near(x, 7 / 3, 1e-9, 'image x')
   near(y, 2, 1e-9, 'image y')
   local order = {}
   for _, r in ipairs(R.results) do
      if r.key and r.key:find('^step') then table.insert(order, r.exact) end
   end
   Test.assert(#order == 5, 'five transformations')
   Test.assert(order[1]:find('^Dilation by a factor of 2 from the x%-axis'), 'dilation first: ' .. order[1])
   Test.assert(order[3]:find('Reflection in the x%-axis'), 'then reflection')
   Test.assert(order[4]:find('2 units in the positive direction of the x%-axis'), 'then translations: ' .. order[4])
   Test.assert(R.graph and #R.graph.curves == 2 and #R.graph.points == 2, 'f, image and the point on the graph')
   -- image as a rule: matched with f
   R = run('transform', { f = 'x^2', g = '3(x-1)^2+2' })
   near(rnum(R, 'A'), 3, 1e-9, 'A from rule')
   near(rnum(R, 'n'), 1, 1e-9, 'n from rule')
   near(rnum(R, 'b'), -1, 1e-9, 'b from rule')
   near(rnum(R, 'c'), 2, 1e-9, 'c from rule')
   R = run('transform', { f = 'sqrt(x)', g = '2sqrt(3-x)+1' })
   near(rnum(R, 'n'), -1, 1e-9, 'reflection in the y-axis')
   near(rnum(R, 'b'), -3, 1e-9, 'b for 3-x')
   -- expanded rule: found by search
   R = run('transform', { f = 'x^2', g = 'x^2-2x+3' })
   near(rnum(R, 'b'), -1, 1e-9, 'search b')
   near(rnum(R, 'c'), 2, 1e-9, 'search c')
   -- not of the form
   R = run('transform', { f = 'x^2', g = 'x^3' })
   Test.assert(has_note(R, 'Could not write the image'), 'not a transformation of f')
   R = run('transform', { g = 'f(x^2)' })
   Test.assert(has_note(R, 'must be linear'), 'inside must be linear')
end

function test.simul_parameter()
   local R = run('simul', { e1 = 'kx+2y=k', e2 = '2x+(k-3)y=k-2' })
   no_errors(R)
   local function rhs(key)
      local e = R:get(key)
      return e and cas.n(e:match('=(.+)$'))
   end
   near(rhs('none'), -1, 1e-6, 'no solution when k = -1')
   near(rhs('many'), 4, 1e-6, 'infinitely many when k = 4')
   Test.assert(R:get('unique'):find(sym.NEQ, 1, true), 'unique when k is not -1 or 4')
   Test.assert(R:get('general'):find('q8l', 1, true), 'general solution uses a free parameter')
   -- unique solution at k = 0: 2y = 0, 2x - 3y = -2 -> x = -1, y = 0
   local x = cas.n('(' .. R:get('sol_x') .. ')|q9k=0')
   near(x, -1, 1e-9, 'x(k) at k = 0')
   -- three unknowns
   R = run('simul', { e1 = 'x+y+z=1', e2 = 'x+2y+3z=2', e3 = '2x+3y+kz=3' })
   no_errors(R)
   near(rhs('many'), 4, 1e-6, '3x3: infinitely many when k = 4')
   Test.assert(R:get('none') == '"no value"', '3x3: never inconsistent')
   -- no parameter
   R = run('simul', { e1 = 'x+y=3', e2 = 'x-y=1' })
   near(rnum(R, 'x'), 2, 1e-9, 'x')
   near(rnum(R, 'y'), 1, 1e-9, 'y')
   R = run('simul', { e1 = 'x+y=3', e2 = '2x+2y=5' })
   Test.assert(R:get('kind') == '"none"', 'parallel lines')
   R = run('simul', { e1 = 'x*y=3', e2 = 'x-y=1' })
   Test.assert(has_note(R, 'not linear'), 'non-linear rejected')
end

function test.proportion()
   local R = run('proportion', { p = '0.3', n = '50', event = 'P>0.36' })
   no_errors(R)
   near(rnum(R, 'mean'), 0.3, 1e-12, 'E(p-hat)')
   near(rnum(R, 'sd'), math.sqrt(0.3 * 0.7 / 50), 1e-9, 'SD(p-hat)')
   -- P(p-hat > 0.36) = P(X > 18) = P(X >= 19), X ~ Bi(50, 0.3)
   near(rnum(R, 'prob'), mock.binom_cdf(50, 0.3, 19, 50), 1e-9, 'exact binomial')
   local sd = math.sqrt(0.3 * 0.7 / 50)
   near(rnum(R, 'prob_n'), 1 - mock.phi((0.36 - 0.3) / sd), 1e-6, 'normal approximation')
   -- CI from a count
   R = run('proportion', { n = '100', x = '24', c = '95' })
   local se = math.sqrt(0.24 * 0.76 / 100)
   near(rnum(R, 'phat'), 0.24, 1e-12, 'p-hat')
   near(rnum(R, 'lo'), 0.24 - 1.959964 * se, 1e-5, 'CI lower')
   near(rnum(R, 'hi'), 0.24 + 1.959964 * se, 1e-5, 'CI upper')
   -- sample size (p-hat unknown -> 1/2), and from a given interval
   R = run('proportion', { e = '0.03', c = '95' })
   near(rnum(R, 'n'), 1068, 0, 'n with p-hat = 1/2')
   R = run('proportion', { lo = '0.21', hi = '0.29', c = '95' })
   near(rnum(R, 'n'), 450, 0, 'n from the interval')
   R = run('proportion', { lo = '0.2', hi = '0.3', n = '100' })
   near(rnum(R, 'c'), 2 * mock.phi(0.05 / math.sqrt(0.25 * 0.75 / 100)) - 1, 1e-6, 'level of an interval')
   R = run('proportion', { p = '0.3', n = '10', event = 'X>=3' })
   near(rnum(R, 'prob'), mock.binom_cdf(10, 0.3, 3, 10), 1e-9, 'count event')
end

function test.probability_group()
   local solvers = require 'apps.vce.registry'
   local G = solvers.get('probability')
   Test.assert(G.is_group and #G.members == 9, 'one Probability entry with 9 kinds')
   local home_ids = {}
   for _, s in ipairs(solvers.home) do home_ids[s.id] = true end
   Test.assert(home_ids.probability and not home_ids.normal and not home_ids.binomial, 'members are not on home')
   for _, s in ipairs(solvers.list) do
      Test.assert(s.course and s.course:match('^[MS][MS]'), 'course marked for ' .. s.id)
   end
   -- inputs are kept per kind
   local ex = G.example_for('binomial')
   Test.assert(ex.type == 'binomial' and ex['binomial.n'] == '10', 'prefixed example')
   local R = report.new()
   G.solve({ type = 'normal', ['normal.mu'] = '50', ['normal.sd'] = '4', ['normal.event'] = '45<X<55',
             ['binomial.n'] = '3' }, R)
   near(rnum(R, 'p'), mock.phi(1.25) - mock.phi(-1.25), 1e-6, 'normal through the group')
   R = report.new()
   G.solve({}, R)
   Test.assert(has_note(R, 'Choose the kind'), 'asks for the kind first')
   -- member fields only show for their kind
   local shown = {}
   for _, f in ipairs(G.fields) do
      if f.show and f.show({ type = 'pdf' }) then shown[f.owner] = true end
   end
   Test.assert(shown.pdf and not shown.normal, 'only the chosen kind\'s fields')
end

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

   -- fill a solver's example through the UI (ids prefixed inside a group)
   local function fill(s, prefix)
      for _, f in ipairs(s.fields) do
         local v = s.example and s.example[f.id]
         local id = prefix .. f.id
         for i, r in ipairs(app.sheet.rows) do
            if r.id == id then
               app.sheet:select(i)
               if f.kind == 'choice' then
                  for _ = 1, 10 do
                     local row = app.sheet:selected()
                     if row.options[row.index][1] == (v or row.options[1][1]) then break end
                     key('right')
                  end
               elseif v then
                  type_text(v)
                  key('enter_key')
               end
               break
            end
         end
      end
   end

   local function check_and_walk(s)
      local R = app.last_report
      Test.assert(R and #R.results > 0, s.id .. ' example has results')
      for _, n in ipairs(R.notes) do
         Test.assert(n.kind ~= 'error', s.id .. ' example error: ' .. report.plain(n.text))
      end
      paint_all()
      -- walk through all rows and toggle results
      for _ = 1, 60 do
         local row = app.sheet:selected()
         if row and row.kind == 'result' then
            key('enter_key')
            if app.screen == 'detail' then
               -- formula: its own working; esc returns to the same row
               Test.assert(paint_all() > 0, s.id .. ' formula working paints')
               key('down') key('escape')
               Test.assert(app.screen == 'problem' and app.sheet:selected().key == row.key,
                           s.id .. ' back from formula working')
            end
            key('right') key('left')
         end
         key('down')
      end
      paint_all()
   end

   for i, h in ipairs(solvers.home) do
      local members = h.is_group and h.members or { h }
      for k, s in ipairs(members) do
         key('char', tostring(i % 10))
         Test.assert(app.screen == 'problem', 'opened ' .. h.id)
         if h.is_group then
            -- a list of the kinds of question comes first; a digit picks one
            Test.assert(app.sheet:selected().kind == 'link', h.id .. ': list of kinds first')
            paint_all()
            key('char', tostring(k % 10))
            Test.assert(app.current().inputs.type == s.id, h.id .. ': picked ' .. s.id)
         end
         fill(s, h.is_group and (s.id .. '.') or '')
         check_and_walk(s)
         key('escape')
         Test.assert(app.screen == 'home', 'back home from ' .. s.id)
      end
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
   Test.assert(#app.history.items > 0, 'history kept')
   dlg_error.display = orig
   app.set_dp(4)
   app.set_font('normal')
   app.settings.mode = 'exact'
   Test.assert(#errors == 0, 'errors: ' .. table.concat(errors, '; '))
end

function test.ui_dynamic_fields()
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   app.settings.mode = 'exact'
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
   local before = app.sheet:selected().mode
   Test.assert(before == 'exact', 'results start exact')
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

function test.ui_graph_view()
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   local i18n = require 'apps.vce.i18n'
   local function key(name, ...) ui.on_event(name, ...) end
   app.open(nil)
   for _, lang in ipairs({ 'en', 'bi' }) do
      app.set_lang(lang)
      app.new_problem('graph', { f = '(x^2-1)/(x-2)', xmin = '-6', xmax = '8', turn = 'hide' })
      local gi
      for i, r in ipairs(app.sheet.rows) do
         if r.kind == 'graph' then gi = i end
      end
      Test.assert(gi, 'graph row shown')
      app.sheet:select(gi)
      Test.assert(paint_all() > 0, 'sheet with graph paints')
      local depth = #ui.modal
      key('enter_key')
      Test.assert(#ui.modal == depth + 1, 'full-screen graph opened')
      local gv = ui.modal[#ui.modal].main
      Test.assert(gv.hide.max and gv.hide.min, 'solver options carried over')
      Test.assert(paint_all() > 0, 'graph view paints')
      local x0 = gv.cx
      key('right')
      Test.assert(gv.cx > x0, 'trace moves right')
      key('up') key('up') key('down')
      Test.assert(gv.point_idx ~= nil, 'jumps between marked points')
      local w = gv.spec.xmax - gv.spec.xmin
      key('char', '+')
      Test.assert(math.abs((gv.spec.xmax - gv.spec.xmin) - w / 2) < 1e-9, 'zoom in')
      key('char', '5')
      key('char', '+') key('char', '\226\136\146') key('char', '8') key('char', '4')
      key('char', 'l') key('char', 'a') key('tab')
      Test.assert(gv.hide.asym and gv.hide.max, 'asymptotes toggled, other options kept')
      paint_all()
      key('escape')
      Test.assert(#ui.modal == depth, 'graph closed')
      Test.assert(ui.get_focus() == app.sheet, 'focus back on the sheet')
      Test.assert(math.abs(app.sheet.rows[gi].spec.xmax - 8) < 1e-9, 'window restored')
   end
   -- the other solvers' graphs (parametric curve, slope field) also open and paint
   for _, c in ipairs({ { 'revolution', { type = 'param', f = '2cos(t)', g = '2sin(t)', a = '0', b = 'pi' } },
                        { 'demodels', { type = 'general', f = 'x+y', x0 = '0', yg0 = '1', h = '0.1', xn = '0.3' } } }) do
      app.new_problem(c[1], c[2])
      for i, r in ipairs(app.sheet.rows) do
         if r.kind == 'graph' then app.sheet:select(i) end
      end
      local depth = #ui.modal
      key('enter_key')
      Test.assert(#ui.modal == depth + 1, c[1] .. ' graph opened')
      key('right') key('left') key('up')
      Test.assert(paint_all() > 0, c[1] .. ' graph paints')
      key('enter_key')
      Test.assert(#ui.modal == depth, c[1] .. ' graph closed')
   end
   app.set_lang('en')
   Test.assert(i18n.lang == 'en')
end

function test.ui_solve_cache()
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   local function key(name, ...) ui.on_event(name, ...) end
   local calls = 0
   local orig = cas.backend
   cas.backend = function(e) calls = calls + 1 return orig(e) end
   math.evalStr = cas.backend
   app.open(nil)
   app.new_problem('graph', { f = '(x^2-1)/(x-2)', xmin = '-6', xmax = '8' })
   Test.assert(calls > 5, 'first solve uses the CAS')
   -- enter through unchanged fields: no new solve
   calls = 0
   app.sheet:select_first()
   for _ = 1, 4 do key('enter_key') end
   Test.assert(calls == 0, 'unchanged fields do not solve again (' .. calls .. ' CAS calls)')
   -- a view option only changes the picture
   local row
   for i, r in ipairs(app.sheet.rows) do
      if r.id == 'asym' then app.sheet:select(i) row = r end
   end
   key('right')
   Test.assert(calls == 0, 'show/hide option does not solve again')
   local g
   for _, r in ipairs(app.sheet.rows) do if r.kind == 'graph' then g = r end end
   Test.assert(g and g.spec.hide.asym, 'option applied to the graph')
   Test.assert(row and app.current()._cache, 'cached')
   -- changing the window solves again
   app.current().inputs.xmax = '9'
   app.refresh_problem(true)
   Test.assert(calls > 0, 'new window solves again')
   cas.backend = orig
   math.evalStr = orig
end

function test.ui_formula_working()
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   local function key(name, ...) ui.on_event(name, ...) end
   app.open(nil)
   app.new_problem('kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', x0 = '0' })
   local function count(kind)
      local n = 0
      for _, r in ipairs(app.sheet.rows) do if r.kind == kind then n = n + 1 end end
      return n
   end
   local all_steps = count('step')
   local idx, row
   for i, r in ipairs(app.sheet.rows) do
      if r.kind == 'result' and r.rkey == 'xv' then idx, row = i, r end
   end
   Test.assert(row and row.detail, 'x(v) is a formula with its own working')
   Test.assert(row.caption and row.caption:find('q9v', 1, true), 'domain shown under x(v)')
   local vt
   for _, r in ipairs(app.sheet.rows) do if r.rkey == 'vterm' then vt = r end end
   Test.assert(vt and not vt.detail, 'a number keeps enter = exact/decimal')
   app.sheet:select(idx)
   Test.assert(app.hint.left:find('working', 1, true), 'hint explains enter')
   key('enter_key')
   Test.assert(app.screen == 'detail', 'enter opens the working')
   Test.assert(count('step') < all_steps and count('step') >= 3, 'only the steps for x(v)')
   Test.assert(app.sheet:selected().rkey == 'xv', 'formula selected')
   local mode = app.sheet:selected().mode
   key('enter_key')
   Test.assert(app.sheet:selected().mode ~= mode, 'enter switches exact/decimal here')
   Test.assert(paint_all() > 0, 'paints')
   key('escape')
   Test.assert(app.screen == 'problem' and app.sheet:selected().rkey == 'xv', 'back on x(v)')
   Test.assert(app.sheet:selected().mode ~= mode, 'mode kept')
   app.settings.mode = 'exact'
end

function test.ui_new_user_flow()
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   local solvers = require 'apps.vce.registry'
   local function key(name, ...) ui.on_event(name, ...) end
   app.settings.mode = 'exact'
   app.open(nil)
   -- home: a legend for MM / SM, badges on every topic, numbers 1-9
   local rows = app.sheet.rows
   Test.assert(rows[1].kind == 'legend', 'MM / SM legend first')
   local links = 0
   for _, r in ipairs(rows) do
      if r.kind == 'link' and r.action and r.action[1] == 'new' then
         links = links + 1
         Test.assert(r.badges and #r.badges >= 1, 'badge on ' .. r.title)
         Test.assert(r.desc and #r.desc <= 48, 'short line under ' .. r.title)
      end
   end
   Test.assert(links == #solvers.home and links <= 10, 'one entry per topic (' .. links .. ')')
   Test.assert(paint_all() > 0, 'home paints')

   -- Probability: choose the kind of question first
   key('char', '9')
   Test.assert(app.current().solver == 'probability', 'probability opened')
   Test.assert(app.hint.left:find('number', 1, true), 'hint says press a number')
   key('char', '3')
   Test.assert(app.current().inputs.type == 'binomial', 'digit picks the kind')
   local sel = app.sheet:selected()
   Test.assert(sel.kind == 'choice' and sel.id == 'type', 'the Type box comes first')
   Test.assert(app.title.right:find('MM', 1, true), 'course shown in the title')
   -- an empty problem offers an example; it fills in and shows the answers
   local ex
   for i, r in ipairs(app.sheet.rows) do
      if r.action and r.action[1] == 'example' then ex = i end
   end
   Test.assert(ex, 'example offered')
   app.sheet:select(ex)
   Test.assert(app.hint.left:find('sample', 1, true), 'example hint')
   key('enter_key')
   Test.assert(app.current().inputs['binomial.n'] == '10', 'example filled in')
   Test.assert(app.sheet:selected().kind == 'result', 'answers selected')
   Test.assert(app.sheet.scroll_y > 0, 'scrolled to the answers')
   for _, r in ipairs(app.sheet.rows) do
      Test.assert(not (r.action and r.action[1] == 'example'), 'example link gone once filled')
   end
   -- enter on the Type box opens a list (many kinds); choosing switches kind, inputs kept
   app.sheet:select(2)
   local depth = #ui.modal
   key('enter_key')
   Test.assert(#ui.modal == depth + 1, 'list of kinds opened')
   paint_all()
   local dlg = ui.modal[#ui.modal]
   local list = dlg.main.children and dlg.main.children[#dlg.main.children]
   list:set_selection(1)
   list:on_enter_key()
   Test.assert(#ui.modal == depth, 'list closed')
   Test.assert(app.current().inputs.type == 'normal', 'switched to normal')
   app.current().inputs.type = 'binomial'
   app.refresh_problem(true)
   Test.assert(app.last_report and #app.last_report.results > 0, 'binomial inputs kept after switching')
   key('escape')
   Test.assert(app.screen == 'home', 'home again')

   -- old saved problems of a member kind still open
   app.new_problem('normal', { mu = '50', sd = '4', event = 'X<55' })
   Test.assert(#app.last_report.results > 0, 'member solver opens directly')
   key('escape')

   -- implicit products are shown as products
   app.new_problem('simul', { e1 = 'kx+2y=k', e2 = '2x+(k-3)y=k-2' })
   local disp = app.sheet:input_display(app.sheet.rows[2], 'kx+2y=k')
   Test.assert(disp:find('q9k*q9x', 1, true), 'kx shown as k*x')
   paint_all()
   key('escape')

   -- settings screen applies at once and is saved
   app.set_colors('comfort')
   app.set_dp(4)
   app.show_settings()
   Test.assert(app.screen == 'settings', 'settings screen')
   for i, r in ipairs(app.sheet.rows) do
      if r.id == 'colors' then app.sheet:select(i) end
   end
   key('right')
   Test.assert(app.settings.colors == 'plain' and ui.sheet.colors.bg == 0xFFFFFF, 'plain colours')
   for i, r in ipairs(app.sheet.rows) do
      if r.id == 'dp' then app.sheet:select(i) end
   end
   key('right')
   Test.assert(app.settings.dp == 5, 'decimal places changed')
   Test.assert(app.save_state().settings.colors == 'plain', 'colours saved')
   paint_all()
   app.set_colors('comfort')
   app.set_dp(4)
   key('escape')
   Test.assert(app.screen == 'home', 'esc goes home from settings')
end

-- Bilingual (中英) mode ------------------------------------------------------------------

local function has_cjk(str)
   return str:find('[\227-\233]') ~= nil
end

function test.i18n_translations()
   local i18n = require 'apps.vce.i18n'
   local solvers = require 'apps.vce.registry'
   i18n.lang = 'bi'
   Test.assert(i18n.t('Results') == 'Results 结果', 'UI string')
   Test.assert(i18n.term('binomial', 'var') == 'variance 方差', 'term')
   Test.assert(i18n.term('suvat', 't2') == 'time 时间', 'term with numeric suffix')
   Test.assert(has_cjk(i18n.note('Enter any three of s, u, v, a, t')), 'note translated')
   Test.assert(i18n.note('Enter any three of s, u, v, a, t'):find('^Enter any three'), 'English kept first')
   Test.assert(i18n.section('When v = 5') == 'When v = 5  当 v = 5 时', 'section')
   for _, s in ipairs(solvers.list) do
      Test.assert(i18n.SOLVERS[s.id], 'solver title for ' .. s.id)
      local title, short, desc = i18n.solver(s)
      Test.assert(has_cjk(title) and has_cjk(short) and has_cjk(desc), 'bilingual title ' .. s.id)
   end
   i18n.lang = 'en'
   Test.assert(i18n.t('Results') == 'Results', 'English mode untouched')
   Test.assert(i18n.term('binomial', 'var') == nil, 'no terms in English mode')
   Test.assert(i18n.note('Enter any three of s, u, v, a, t') == 'Enter any three of s, u, v, a, t', 'English note')
end

function test.i18n_coverage()
   local i18n = require 'apps.vce.i18n'
   local solvers = require 'apps.vce.registry'
   local selftest = require 'apps.vce.selftest'
   i18n.lang = 'bi'
   local missing = {}
   -- every result of the examples and self-test cases has a bilingual term
   local cases = {}
   for _, s in ipairs(solvers.list) do table.insert(cases, { s.id, s.example }) end
   for _, c in ipairs(selftest.cases) do table.insert(cases, { c[1], c[2] }) end
   for _, c in ipairs(cases) do
      local R = run(c[1], c[2])
      for _, r in ipairs(R.results) do
         if not i18n.term(c[1], r.key) then
            table.insert(missing, c[1] .. ':' .. tostring(r.key))
         end
      end
   end
   -- notes shown for empty / incomplete input are translated
   local notes = {}
   for _, s in ipairs(solvers.list) do
      local R = run(s.id, s.id == 'kinematics' and { f = '6t' } or {})
      for _, n in ipairs(R.notes) do table.insert(notes, n.text) end
   end
   for _, extra in ipairs({
      { 'normal', { event = 'X<k' } }, { 'normal', { mu = '1', event = '1<' } },
      { 'binomial', { n = '10', p = '0.3', event = 'X>' } }, { 'discrete', { x = '1,2', px = '0.5' } },
      { 'pdf', { f1 = 'x' } }, { 'suvat', { u = '1', v = '2', a = '3', t = '4' } },
      { 'kinematics', { type = 'a(t)', f = '6t', find = 'q' } }, { 'lincomb', { comb = '2X' } },
      { 'graph', { f = 'x+k' } }, { 'graph', { f = 'x', xmin = '3', xmax = '1' } },
      { 'revolution', { type = 'x', f = 'x', a = '0', b = '1' } }, { 'revolution', { f = 'x', a = '2', b = '1' } },
      { 'revolution', { type = 'param', f = 't' } }, { 'demodels', { type = 'related', rel = 'x*y', rate = '1', at = '1' } },
      { 'revolution', { type = 'y', f = 'sqrt(x)', a = '0', b = 'a' } },
      { 'revolution', { type = 'y', f = 'sqrt(x)', a = '0', b = 'a', known = 'W=2' } },
      { 'revolution', { type = 'y', f = 'x^2', g = 'x', lim = 'y', a = '0', b = '1' } },
      { 'demodels', { type = 'cooling' } }, { 'demodels', { type = 'logistic' } }, { 'demodels', { type = 'mixing' } },
      { 'demodels', { type = 'general' } }, { 'demodels', { type = 'related' } }, { 'demodels', { type = 'growth', y0 = '5' } },
      { 'kinematics', { type = 'a(t)', f = '6t', v0 = '2', find = 't=2' } },
      { 'kinematics', { type = 'a(t)', f = '6t', want = 'v', find = 't=2' } },
      { 'kinematics', { type = 'a(x)', f = '-4x', want = 't', find = 'x=1' } },
      { 'kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', want = 'x' } },
      { 'kinematics', { type = 'a(v)', f = '-v/2', v0 = '10', want = 'v', find = 'v=5' } },
   }) do
      local R = run(extra[1], extra[2])
      for _, n in ipairs(R.notes) do table.insert(notes, n.text) end
   end
   for _, text in ipairs(notes) do
      if not has_cjk(i18n.note(text)) then table.insert(missing, 'note: ' .. report.plain(text)) end
   end
   i18n.lang = 'en'
   Test.assert(#missing == 0, 'untranslated: ' .. table.concat(missing, '; '))
end

-- vce.tns and rpn.tns do not load i18n_zh: no Chinese and no language choice
function test.english_only()
   local app = require 'apps.vce.app'
   local i18n = require 'apps.vce.i18n'
   local solvers = require 'apps.vce.registry'
   local function no_cjk(row, where)
      for _, k in ipairs({ 'title', 'text', 'label', 'hint', 'desc', 'term', 'value' }) do
         local v = row[k]
         if type(v) == 'string' then Test.assert(not has_cjk(v), where .. ': ' .. v) end
      end
      for _, o in ipairs(row.options or {}) do
         Test.assert(not has_cjk(tostring(o[2])), where .. ' option: ' .. tostring(o[2]))
      end
   end
   i18n.install(nil)
   local ok, err = pcall(function()
      Test.assert(not i18n.has_zh and i18n.set('bi') == 'en', 'no bilingual mode without the Chinese text')
      app.open(nil)
      app.set_lang('bi')
      Test.assert(i18n.lang == 'en' and app.settings.lang == 'en', 'language stays English')
      for _, r in ipairs(app.sheet.rows) do
         no_cjk(r, 'home')
         if r.id == 'settings' then Test.assert(not r.desc:find('language'), 'settings blurb') end
      end
      app.show_settings()
      for _, r in ipairs(app.sheet.rows) do
         Test.assert(r.id ~= 'lang', 'no language setting')
         no_cjk(r, 'settings')
      end
      for _, sub in ipairs(app.menu()) do
         for _, it in ipairs(sub) do
            if type(it) == 'table' then
               Test.assert(not it[1]:find('Language'), 'no language menu item')
               Test.assert(not has_cjk(it[1]), 'menu: ' .. it[1])
            end
         end
      end
      for _, h in ipairs(i18n.help()) do
         Test.assert(not h[2]:find('Language'), 'help line about the language setting')
         Test.assert(not has_cjk(h[2]), 'help: ' .. h[2])
      end
      for _, s in ipairs(solvers.home) do
         app.new_problem(s.id)
         app.fill_example()
         for _, r in ipairs(app.sheet.rows) do no_cjk(r, s.id) end
      end
      local state = app.save_state()
      state.settings.lang = 'bi'
      app.restore_state(state)
      Test.assert(i18n.lang == 'en', 'a saved bilingual setting is ignored')
   end)
   i18n.install(i18n_zh)
   i18n.set('en')
   app.settings.lang = nil
   Test.assert(ok, tostring(err))
end

-- every help line has its Chinese
function test.i18n_help()
   local i18n = require 'apps.vce.i18n'
   for _, h in ipairs(i18n.HELP) do
      Test.assert(i18n.HELP_ZH[h[2]], 'help not translated: ' .. h[2])
   end
   i18n.set('bi')
   local rows = i18n.help()
   i18n.set('en')
   Test.assert(#rows == #i18n.HELP and has_cjk(rows[1][2]) and rows[#rows][2]:find('Language'), 'bilingual help')
end

function test.ui_bilingual()
   local ui = require 'ui'
   local app = require 'apps.vce.app'
   local i18n = require 'apps.vce.i18n'
   local solvers = require 'apps.vce.registry'
   app.settings.mode = 'exact'
   app.open(nil)
   app.set_lang('bi')
   Test.assert(i18n.lang == 'bi', 'language switched')
   Test.assert(has_cjk(app.title.left), 'home title bilingual')
   local errors = {}
   local dlg_error = require 'dialog.error'
   local orig = dlg_error.display
   dlg_error.display = function(title, msg)
      table.insert(errors, tostring(msg))
      return orig(title, msg)
   end
   for _, s in ipairs(solvers.list) do
      app.new_problem(s.id, s.example and (function()
         local t = {}
         for k, v in pairs(s.example) do t[k] = v end
         return t
      end)())
      local rows = app.sheet.rows
      local saw_term, saw_label = false, false
      for _, r in ipairs(rows) do
         if r.kind == 'result' and r.term and has_cjk(r.term) then saw_term = true end
         if (r.kind == 'input' or r.kind == 'choice') and (has_cjk(r.label or '') or has_cjk(r.hint or '')) then
            saw_label = true
         end
         if r.kind == 'step' and not r.section then
            Test.assert(not has_cjk(r.text), s.id .. ': working step must stay English: ' .. r.text)
         end
      end
      Test.assert(saw_term, s.id .. ': result terms are bilingual')
      Test.assert(saw_label, s.id .. ': field labels/hints are bilingual')
      paint_all()
      -- walk and toggle
      for _ = 1, 40 do
         local row = app.sheet:selected()
         if row and row.kind == 'result' then ui.on_event('enter_key') end
         ui.on_event('down')
      end
      paint_all()
   end
   app.show_help()
   local zh_help = false
   for _, r in ipairs(app.sheet.rows) do
      if r.kind == 'step' and has_cjk(r.text) then zh_help = true end
   end
   Test.assert(zh_help, 'help has Chinese text')
   paint_all()
   app.show_history() paint_all()
   -- menu titles are bilingual and every entry runs
   local menu = app.menu()
   Test.assert(has_cjk(menu[1][1]), 'menu category bilingual')
   app.show_problem(#app.history.items)
   for _, cat in ipairs(menu) do
      for k = 2, #cat do
         if not cat[k][1]:find('Delete') and not cat[k][1]:find('Language') then
            cat[k][2]()
            while #ui.modal > 1 do ui.pop_modal() end
            if ui.get_focus() ~= app.sheet then ui.set_focus(app.sheet) end
            paint_all()
         end
      end
   end
   -- language is saved with the document
   local state = app.save_state()
   Test.assert(state.settings.lang == 'bi', 'language saved')
   app.set_lang('en')
   app.restore_state(state)
   Test.assert(i18n.lang == 'bi', 'language restored')
   app.set_lang('en')
   app.set_dp(4)
   app.set_font('normal')
   app.settings.mode = 'exact'
   dlg_error.display = orig
   local real = {}
   for _, e in ipairs(errors) do
      if not e:find('Select') and not e:find('请先') then table.insert(real, e) end
   end
   Test.assert(#real == 0, 'errors: ' .. table.concat(real, '; '))
end

function test.sheet_cjk_wrapping()
   local ui = require 'ui'
   require 'views.sheet'
   local sh = ui.sheet(ui.rel { top = 0, left = 0, width = 120, height = 100 })
   sh:layout_children(ui.rect(0, 0, 318, 212))
   sh:set_rows({ { kind = 'note', text = 'Enter x\n请输入一个很长很长很长很长很长的中文句子用于测试换行' } })
   local lines
   sh:with_layout(function()
      lines = #sh.rows[1]._lay.content.lines
   end)
   Test.assert(lines >= 3, 'CJK text wraps onto several lines (got ' .. tostring(lines) .. ')')
end

Test.run(test)
