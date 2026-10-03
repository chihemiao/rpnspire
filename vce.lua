-- VCE Specialist Maths toolkit (standalone document entry point)
platform.apiLevel = '2.4'
-- luacheck: ignore platform on toolpalette

require 'tableext'
require 'stringext'

local ui = require 'ui'
local app = require 'apps.vce.app'
local dlg_error = require 'dialog.error'

local pending_state = nil
local started = false

local function start()
   if started then return end
   started = true
   toolpalette.enableCopy(true)
   toolpalette.enableCut(true)
   toolpalette.enablePaste(true)
   if pending_state then
      app.restore_state(pending_state)
      pending_state = nil
   end
   app.open(nil)
end

function on.construction()
   start()
end

function on.restore(state)
   if started then
      app.restore_state(state)
   else
      pending_state = state
   end
end

function on.save()
   return app.save_state()
end

function on.activate()
   app.register_menu()
end

function on.resize(w, h)
   if not started then start() end
   ui.resize(w, h)
end

function on.mouseDown(x, y) ui.on_event('mouse_down', x, y) end
function on.rightMouseDown(x, y) ui.on_event('rmouse_down', x, y) end
function on.escapeKey() ui.on_event('escape') end
function on.tabKey() ui.on_event('tab') end
function on.backtabKey() ui.on_event('backtab') end
function on.returnKey() ui.on_event('return') end
function on.enterKey() ui.on_event('enter_key') end
function on.arrowRight() ui.on_event('right') end
function on.arrowLeft() ui.on_event('left') end
function on.arrowUp() ui.on_event('up') end
function on.arrowDown() ui.on_event('down') end
function on.charIn(c) ui.on_event('char', c) end
function on.backspaceKey() ui.on_event('backspace') end
function on.clearKey() ui.on_event('clear') end
function on.contextMenu() ui.on_event('ctx') end
function on.help() ui.on_event('help') end
function on.cut() ui.on_event('cut') end
function on.copy() ui.on_event('copy') end
function on.paste() ui.on_event('paste') end

function on.paint(gc)
   ui.paint(ui.GC(gc, 0, 0))
end

if platform.registerErrorHandler then
   platform.registerErrorHandler(function(line, msg)
      print(string.format('ERROR (line %d) %s', line or 0, msg or ''))
      dlg_error.display('Internal Error', msg)
      return true
   end)
end
