-- Registry of VCE solvers (order = home screen order)
local t = {}

t.list = {
   (require 'apps.vce.solvers.normal'),
   (require 'apps.vce.solvers.normal2'),
   (require 'apps.vce.solvers.binomial'),
   (require 'apps.vce.solvers.discrete'),
   (require 'apps.vce.solvers.pdf'),
   (require 'apps.vce.solvers.lincomb'),
   (require 'apps.vce.solvers.sampling'),
   (require 'apps.vce.solvers.hyptest'),
   (require 'apps.vce.solvers.suvat'),
   (require 'apps.vce.solvers.kinematics'),
}

t.by_id = {}
for _, s in ipairs(t.list) do
   t.by_id[s.id] = s
end

function t.get(id)
   return t.by_id[id]
end

return t
