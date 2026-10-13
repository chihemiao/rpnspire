-- Prints the toolkit's home topics as JSON for the website (site/build.mjs):
-- titles, one-line blurbs, courses (MM/SM) and the Chinese text, so the
-- feature list on the site always matches the app. Run from the repo root:
--   lua site/tools/features.lua
package.path = './?.lua;' .. package.path
require 'tableext'
require 'stringext'

local registry = require 'apps.vce.registry'
local zh = require 'apps.vce.i18n_zh'
local version = require 'apps.vce.version'

local function str(s)
   s = tostring(s):gsub('[%c"\\]', function(c)
      local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t' }
      return map[c] or string.format('\\u%04x', c:byte())
   end)
   return '"' .. s .. '"'
end

local function json(v)
   if type(v) == 'table' then
      if #v > 0 or next(v) == nil then
         local parts = {}
         for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
         return '[' .. table.concat(parts, ',') .. ']'
      end
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do parts[#parts + 1] = str(k) .. ':' .. json(v[k]) end
      return '{' .. table.concat(parts, ',') .. '}'
   elseif type(v) == 'string' then
      return str(v)
   elseif v == nil then
      return 'null'
   end
   return tostring(v)
end

local function courses(s)
   local out = {}
   for w in (s.course or ''):gmatch('%S+') do out[#out + 1] = w end
   return out
end

local function entry(s)
   local z = zh.SOLVERS[s.id]
   return {
      id = s.id,
      title = s.title,
      short = s.short,
      blurb = s.blurb or '',
      desc = s.desc or '',
      course = courses(s),
      zh = {
         short = z and z[1] or '',
         title = z and z[2] or '',
         desc = z and z[3] or '',
         blurb = zh.BLURBS[s.id] or '',
      },
   }
end

local out = {}
for _, s in ipairs(registry.home) do
   local e = entry(s)
   if s.members then
      e.members = {}
      for _, m in ipairs(s.members) do table.insert(e.members, entry(m)) end
   end
   table.insert(out, e)
end

print(json({ version = version, topics = out }))
