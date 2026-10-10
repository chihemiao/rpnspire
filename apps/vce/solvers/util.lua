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

-- Infix string of an expression tree node (for sub-expressions)
function U.tree_infix(node)
   local expr = require 'expressiontree'
   local operators = require 'ti.operators'
   local k = node.kind
   if k == expr.FUNCTION then
      local args = {}
      for i, c in ipairs(node.children) do args[i] = U.tree_infix(c) end
      return node.text .. '(' .. table.concat(args, ',') .. ')'
   elseif k == expr.LIST then
      local args = {}
      for i, c in ipairs(node.children) do args[i] = U.tree_infix(c) end
      return '{' .. table.concat(args, ',') .. '}'
   elseif k == expr.OPERATOR then
      local parts = {}
      for i, c in ipairs(node.children) do parts[i] = '(' .. U.tree_infix(c) .. ')' end
      if node.text == sym.NEGATE then return sym.NEGATE .. parts[1] end
      if #parts == 1 then return parts[1] .. node.text end
      local name = operators.query_info(node.text) or node.text
      return table.concat(parts, name)
   end
   return node.text
end

-- Sub-expressions where f may be undefined: denominators, negative powers,
-- log/root arguments, tan/sec (cos = 0) and cot/csc (sin = 0).
-- Returns list of { expr = string, kind = 'zero'|'nonpos'|'neg' }.
function U.special_subexprs(src)
   local expr = require 'expressiontree'
   local tree = expr.from_string(src)
   local out = {}
   local function walk(n)
      if n.kind == expr.OPERATOR then
         if n.text == '/' and n.children[2] then
            table.insert(out, { expr = U.tree_infix(n.children[2]), kind = 'zero' })
         elseif n.text == '^' and n.children[2] and n.children[2].kind == expr.OPERATOR
                and n.children[2].text == sym.NEGATE then
            table.insert(out, { expr = U.tree_infix(n.children[1]), kind = 'zero' })
         end
      elseif n.kind == expr.FUNCTION and n.children[1] then
         local name = n.text:lower()
         local arg = U.tree_infix(n.children[1])
         if name == 'ln' or name == 'log' then
            table.insert(out, { expr = arg, kind = 'zero' })
         elseif name == 'sqrt' or n.text == sym.ROOT then
            table.insert(out, { expr = arg, kind = 'zero' })
         elseif name == 'tan' or name == 'sec' then
            table.insert(out, { expr = 'cos(' .. arg .. ')', kind = 'zero' })
         elseif name == 'cot' or name == 'csc' then
            table.insert(out, { expr = 'sin(' .. arg .. ')', kind = 'zero' })
         end
      end
      for _, c in ipairs(n.children or {}) do walk(c) end
   end
   local ok = pcall(walk, tree)
   if not ok then return {} end
   return out
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
