-- Shared helpers for VCE solvers
local cas = require 'apps.vce.cas'
local fmt = require 'apps.vce.fmt'
local sym = require 'ti.sym'
local report = require 'apps.vce.report'

local U = {}

U.M = report.M
U.D = report.D
U.NEG = sym.NEGATE
U.INF = sym.INFTY
U.NEGINF = sym.NEGATE .. sym.INFTY
U.LEQ, U.GEQ, U.NEQ = sym.LEQ, sym.GEQ, sym.NEQ
U.APPROX = sym.APPROX
U.IMPL = sym.LIMP
U.PM = sym.PLUSMINUS
U.SQ = sym.SQUARED
U.ROOT = sym.ROOT
U.SUM = sym.SUMSEQ
U.INTG = sym.INTEGRAL
U.mu = '\206\188'
U.sigma = sym.sigma

-- Rename map making every single letter (except e) a local symbol
function U.locals_map(except)
   local map = {}
   local letters = 'abcdfghjklmnopqrstuvwxyz'
   for i = 1, #letters do
      local l = letters:sub(i, i)
      if not (except and except[l]) then
         map[l] = 'q9' .. l
      end
   end
   return map
end

-- Read and evaluate a numeric/expression input.
-- Returns nil if empty, otherwise { src = normalized input, val = CAS
-- result string, num = Lua number|nil }
function U.read(text, map)
   local src = cas.input(text, map)
   if not src then return nil end
   local val, err = cas.eval(src)
   if not val then
      error({ desc = 'Cannot evaluate "' .. text .. '" (error ' .. tostring(err) .. ')' })
   end
   return { src = src, val = val, num = cas.tonum(val) or cas.n(val) }
end

-- Parenthesize if not a simple atom
function U.par(s)
   s = tostring(s)
   if s:match('^[%w_%.]+$') or s:match('^[%w_]+%b()$') then
      return s
   end
   if s:sub(1, 1) == '(' and s:sub(-1) == ')' then
      -- already wrapped as a whole?
      local depth = 0
      local whole = true
      for i = 1, #s do
         local c = s:sub(i, i)
         if c == '(' then depth = depth + 1 elseif c == ')' then depth = depth - 1 end
         if depth == 0 and i < #s then whole = false break end
      end
      if whole then return s end
   end
   return '(' .. s .. ')'
end

-- Simplify expression via CAS (raises)
function U.simp(e)
   return cas.must(e)
end

-- Value text for working: exact form plus decimal when useful
--   "`9/4` = `2.25`" or "`√3` ≈ `1.7321`" or "≈ `0.7887`"
function U.show(e, dp)
   local x = cas.n(e)
   if fmt.has_decimal(e) then
      if x then
         local r = fmt.round(x, dp)
         local rx = cas.tonum(r)
         if rx and math.abs(rx - x) <= 1e-12 * math.max(1, math.abs(x)) then
            return report.M(r)
         end
         return U.APPROX .. ' ' .. report.D(x, dp)
      end
      return report.M(fmt.round_expr(e, dp))
   end
   if x and x == math.floor(x) and cas.tonum(e) then
      return report.M(e)
   end
   if x then
      local r = fmt.round(x, dp)
      return report.M(e) .. ' ' .. U.APPROX .. ' `' .. r .. '`'
   end
   return report.M(e)
end

-- "= value" form for working lines
function U.eq(e, dp)
   local s = U.show(e, dp)
   if s:sub(1, #U.APPROX) == U.APPROX then return s end
   return '= ' .. s
end

-- Number of non-nil entries
function U.count(...)
   local n = 0
   for i = 1, select('#', ...) do
      if select(i, ...) ~= nil then n = n + 1 end
   end
   return n
end

-- Probability text for a relation
function U.rel_text(rel)
   if rel == '=' then return '=' end
   return rel
end

-- Free local symbols (q9*/q7*) in an expression
function U.unknowns(e)
   local _, list = cas.identifiers(e)
   local out = {}
   for _, id in ipairs(list) do
      if id:match('^q[79]%a$') then table.insert(out, id) end
   end
   return out
end

-- Event bound helper: normalize a bound string with local symbols
function U.bound(s)
   if not s then return nil end
   return cas.input(s, U.locals_map())
end

-- Display text of a CAS value for inline text (plain)
function U.txt(e)
   return fmt.plain(fmt.round_expr(e))
end

-- Trim
function U.trim(s)
   return (s or ''):match('^%s*(.-)%s*$')
end

-- Numeric solutions within [lo, hi] (Lua numbers, optional), sorted.
-- Periodic CAS solutions containing arbitrary integers (@n1) are expanded
-- for small integer values.
function U.expand_solutions(sols, lo, hi, limit)
   local out = {}
   local function add(e)
      local v = cas.n(e)
      if v and (not lo or v >= lo - 1e-9) and (not hi or v <= hi + 1e-9) then
         table.insert(out, { e = e, v = v })
      end
   end
   for _, s in ipairs(sols or {}) do
      if s:find('@n') then
         for k = -3, 24 do
            local kk = k < 0 and (U.NEG .. tostring(-k)) or tostring(k)
            add(cas.eval((s:gsub('@n%d+', '(' .. kk .. ')'))) or '')
         end
      else
         add(s)
      end
   end
   table.sort(out, function(a, b) return a.v < b.v end)
   local res = {}
   for _, o in ipairs(out) do
      if #res == 0 or math.abs(res[#res].v - o.v) > 1e-9 then
         table.insert(res, { e = o.e, v = o.v })
      end
      if limit and #res >= limit then break end
   end
   local list = {}
   for _, o in ipairs(res) do table.insert(list, o.e) end
   return list
end

-- Parse a CAS list input like '{1,2,3}' or '1,2,3'
function U.read_list(text, map)
   local src = cas.input(text, map)
   if not src then return nil end
   if src:sub(1, 1) ~= '{' then src = '{' .. src .. '}' end
   local val = cas.eval(src)
   if not val then error({ desc = 'Cannot read list ' .. text }) end
   local items = cas.list(val)
   if not items then error({ desc = 'Not a list: ' .. text }) end
   return items, val, src
end

return U
