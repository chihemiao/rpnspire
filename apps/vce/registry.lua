-- Registry of VCE solvers.
--   t.list  every solver (tests, self-test, saved problems)
--   t.home  the home screen entries, in order (Probability is one entry)
-- course: 'MM' Mathematical Methods, 'SM' Specialist Mathematics (both are
-- Units 3 & 4 with a technology-active Exam 2).
local group = require 'apps.vce.solvers.group'

local t = {}

-- literal requires: the bundler only follows require('name') with a constant
local graph = require 'apps.vce.solvers.graph'
local params = require 'apps.vce.solvers.params'
local transform = require 'apps.vce.solvers.transform'
local simul = require 'apps.vce.solvers.simul'
local revolution = require 'apps.vce.solvers.revolution'
local demodels = require 'apps.vce.solvers.demodels'
local suvat = require 'apps.vce.solvers.suvat'
local kinematics = require 'apps.vce.solvers.kinematics'
local normal = require 'apps.vce.solvers.normal'
local normal2 = require 'apps.vce.solvers.normal2'
local binomial = require 'apps.vce.solvers.binomial'
local discrete = require 'apps.vce.solvers.discrete'
local pdf = require 'apps.vce.solvers.pdf'
local proportion = require 'apps.vce.solvers.proportion'
local sampling = require 'apps.vce.solvers.sampling'
local lincomb = require 'apps.vce.solvers.lincomb'
local hyptest = require 'apps.vce.solvers.hyptest'

local COURSE = {
   graph = 'MM SM', params = 'MM SM', transform = 'MM', simul = 'MM',
   revolution = 'MM SM', demodels = 'SM', suvat = 'SM', kinematics = 'SM',
   normal = 'MM', normal2 = 'MM', binomial = 'MM', discrete = 'MM', pdf = 'MM', proportion = 'MM',
   sampling = 'SM', lincomb = 'SM', hyptest = 'SM',
}

-- One short line under each home entry (fewer words to read)
local BLURB = {
   graph = 'asymptotes, turning points, intercepts',
   params = "a, b, c from f(1)=3, f'(2)=0, points",
   transform = 'dilate, reflect, translate; (x, y) to (...)',
   simul = 'unique / no / infinitely many solutions',
   revolution = 'area, volume, arc length, surface area',
   demodels = 'growth, cooling, logistic, mixing, Euler',
   suvat = 'any 3 of s, u, v, a, t',
   kinematics = 'a(t), a(v), a(x), v(x), x(t) with working',
}

-- Home groups
graph.group, params.group, transform.group, simul.group = 'Functions', 'Functions', 'Functions', 'Functions'

t.list = {
   graph, params, transform, simul,
   revolution, demodels,
   suvat, kinematics,
   normal, normal2, binomial, discrete, pdf, proportion, sampling, lincomb, hyptest,
}

for _, s in ipairs(t.list) do
   s.course = s.course or COURSE[s.id]
   s.blurb = s.blurb or BLURB[s.id]
end

t.probability = group.new({
   id = 'probability',
   title = 'Probability & statistics',
   short = 'Probability',
   group = 'Probability',
   course = 'MM SM',
   desc = 'Normal, binomial, discrete, PDF, p-hat, CI, aX+bY, hypothesis tests',
   blurb = 'normal, binomial, p-hat, CI, tests ...',
   pick_label = 'Type',
   members = { normal, normal2, binomial, discrete, pdf, proportion, sampling, lincomb, hyptest },
})

t.home = {
   graph, params, transform, simul,
   revolution, demodels,
   suvat, kinematics,
   t.probability,
}

t.by_id = {}
for _, s in ipairs(t.list) do t.by_id[s.id] = s end
t.by_id[t.probability.id] = t.probability

-- Member solver a leaf belongs to (for the home entry of a saved problem)
function t.get(id)
   return t.by_id[id]
end

-- 'MM SM' -> { 'MM', 'SM' }
function t.badges(s)
   local out = {}
   for w in (s.course or ''):gmatch('%S+') do table.insert(out, w) end
   return out
end

return t
