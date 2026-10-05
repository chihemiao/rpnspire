-- Register the VCE toolkit in rpnspire's app list (.a)
local apps = require 'apps.apps'
local fmt = require 'apps.vce.fmt'

apps.add('VCE Specialist toolkit', 'graphs, calculus, kinematics, probability', function(stack)
   local app = require 'apps.vce.app'
   app.open({
      push = function(value)
         stack:push_infix(fmt.plain(value))
      end,
   })
end)
