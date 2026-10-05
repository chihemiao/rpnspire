-- Result/working builder used by the VCE solvers.
--
-- Text strings may contain math segments between backticks, e.g.
--   "P(X < 55) = `normCdf(−∞,55,50,4)` ≈ `0.8944`"
-- Math segments are TI infix and are pretty printed by ui.mathbox.
local fmt = require 'apps.vce.fmt'
local cas = require 'apps.vce.cas'

local report = {}

local mt = {}
mt.__index = mt

function report.new()
   return setmetatable({ results = {}, steps = {}, notes = {}, by_key = {} }, mt)
end

-- Add a result.
---@param label string  Label text (may contain `math`)
---@param value string  CAS result string (exact where possible)
---@param opts? table   { key = 'mu', unit = 'm/s', domain = '0≤q9t' }
function mt:result(label, value, opts)
   opts = opts or {}
   local r = {
      label = label,
      exact = value,
      key = opts.key,
      unit = opts.unit,
      domain = opts.domain,
   }
   table.insert(self.results, r)
   if opts.key then
      self.by_key[opts.key] = r
   end
   return r
end

-- Add a point result (x, y); shown as (x, y)
function mt:pair(label, x, y, opts)
   local r = self:result(label, 'pt(' .. x .. ',' .. y .. ')', opts)
   r.pair = { x, y }
   return r
end

-- Numeric coordinates of a keyed point result
function mt:pair_num(key)
   local r = self.by_key[key]
   if not (r and r.pair) then return nil end
   return cas.n(r.pair[1]), cas.n(r.pair[2])
end

-- Group the following steps under the result `key` they derive; `deps` are
-- the keys whose working it builds on. steps_for(key) then gives the
-- working of one result on its own (e.g. only how x(v) was found).
function mt:tag(key, deps)
   self.cur_tag = key
   if key then
      self.deps = self.deps or {}
      self.deps[key] = deps or self.deps[key] or {}
   end
end

-- Steps for one result and everything it depends on, in order (or nil)
function mt:steps_for(key)
   if not (key and self.deps and self.deps[key]) then return nil end
   local want = {}
   local function add(k)
      if want[k] then return end
      want[k] = true
      for _, d in ipairs(self.deps[k] or {}) do add(d) end
   end
   add(key)
   local out = {}
   for _, st in ipairs(self.steps) do
      if st.tag and want[st.tag] then table.insert(out, st) end
   end
   return #out > 0 and out or nil
end

-- Set the domain of a keyed result (shown under its value)
function mt:domain(key, dom)
   local r = self.by_key[key]
   if r then r.domain = dom end
end

-- Add a step of working (one line; text with `math` segments)
function mt:step(text, ...)
   if select('#', ...) > 0 then
      text = string.format(text, ...)
   end
   table.insert(self.steps, { text = text, tag = self.cur_tag })
end

-- Add a sub-heading inside the working
function mt:section(title)
   table.insert(self.steps, { text = title, section = true, tag = self.cur_tag })
end

-- Add a note. kind: 'info' | 'warn' | 'error'
function mt:note(text, kind)
   table.insert(self.notes, { text = text, kind = kind or 'info' })
end

function mt:get(key)
   local r = self.by_key[key]
   return r and r.exact
end

-- Numeric value of a keyed result
function mt:num(key)
   local r = self.by_key[key]
   return r and cas.n(r.exact)
end

-- Split text into segments { {t = 'text'} | {m = 'math'} }
function report.segments(text)
   local segs = {}
   local i = 1
   local in_math = false
   while true do
      local j = text:find('`', i, true)
      local chunk = text:sub(i, (j or 0) - 1)
      if j == nil then chunk = text:sub(i) end
      if chunk ~= '' then
         table.insert(segs, in_math and { m = chunk } or { t = chunk })
      end
      if not j then break end
      in_math = not in_math
      i = j + 1
   end
   return segs
end

-- Shorthand: math segment
function report.M(s)
   return '`' .. tostring(s) .. '`'
end

-- Shorthand: rounded decimal of a number or expression as a math segment
function report.D(x, dp)
   if type(x) ~= 'number' then
      x = cas.n(x)
   end
   if not x then return '?' end
   return '`' .. fmt.round(x, dp) .. '`'
end

-- Plain text of a step/label (for clipboard)
function report.plain(text)
   local out = {}
   for _, s in ipairs(report.segments(text)) do
      table.insert(out, s.t or fmt.plain(s.m))
   end
   return table.concat(out)
end

return report
