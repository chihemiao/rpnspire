-- Browser entry for the website demo (bundled to site/dist/emu/vce_web.txt,
-- run by site/public/emu/emulator.js after site/public/emu/host.lua). It is
-- the real toolkit on the numeric mock CAS (testcas.lua), with the exact
-- answers of the website's worked examples (site/emu/recorded.lua). It is
-- not part of any .tns document.
-- luacheck: globals WEB_LANG platform math host_screen host_results
platform.apiLevel = '2.4'

local mock = require 'testcas'
local recorded = require 'site.emu.recorded'

math.evalStr = function(s)
   local r = recorded[s]
   if r then return r end
   return mock.evalStr(s)
end

local lang = WEB_LANG == 'bi' and 'bi' or 'en'
if lang == 'bi' then
   require('apps.vce.i18n').install(require('apps.vce.i18n_zh'))
end
require('apps.vce.entry')(lang)

-- For the site's tests (site/test/emu.test.mjs): the open screen and the
-- answer rows of the open problem as "key=value" lines
local app = require 'apps.vce.app'

function host_screen()
   return app.screen
end

function host_results()
   local out = {}
   for _, r in ipairs(app.sheet and app.sheet.rows or {}) do
      if r.kind == 'result' then
         out[#out + 1] = tostring(r.rkey) .. '=' .. tostring(r.exact or r.value)
      end
   end
   return table.concat(out, '\n')
end
