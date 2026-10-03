-- Bridge to the TI-Nspire CAS (math.evalStr) used by the VCE toolkit.
--
-- All solver maths goes through this module so that desktop tests can swap
-- the backend for a mock (see testcas.lua).
local sym = require 'ti.sym'

local cas = {}

local NEG = sym.NEGATE
cas.NEG = NEG
cas.INF = sym.INFTY
cas.NEGINF = NEG .. sym.INFTY
cas.E = sym.EULER

-- Backend: function(expr) -> result_string | nil, error_code
cas.backend = nil

-- Optional call log (list of expressions), used by tests
cas.log = nil

local function backend(expr)
   -- luacheck: ignore math
   local f = cas.backend or math.evalStr
   return f(expr)
end

-- Apply evaluation settings needed by the solvers (exact where possible,
-- radians for kinematics, real results). Each setting is applied separately
-- so an unsupported name cannot block the others.
function cas.init()
   -- luacheck: ignore math
   if not math.setEvalSettings then return end
   local settings = {
      { 'Calculation Mode', 'Auto' },
      { 'Angle', 'Radian' },
      { 'Real or Complex Format', 'Real' },
      { 'Exponential Format', 'Normal' },
   }
   for _, s in ipairs(settings) do
      pcall(math.setEvalSettings, { s })
   end
end

-- Evaluate expression; returns result string or nil, error
---@param expr string
---@return string|nil, any
function cas.eval(expr)
   if cas.log then table.insert(cas.log, expr) end
   local ok, res, err = pcall(backend, expr)
   if not ok then
      return nil, res
   end
   if res == nil then
      return nil, err or 'error'
   end
   return res
end

-- Evaluate or raise an error table
function cas.must(expr)
   local res, err = cas.eval(expr)
   if not res then
      error({ desc = 'CAS error ' .. tostring(err), code = err, expr = expr })
   end
   return res
end

-- Format and evaluate (raises on error)
function cas.f(fmt, ...)
   return cas.must(string.format(fmt, ...))
end

-- Wrap in parentheses
function cas.p(s)
   return '(' .. tostring(s) .. ')'
end

-- Approximate value as string (raises on error)
function cas.approx(expr)
   return cas.must('approx(' .. expr .. ')')
end

-- Convert CAS output to Lua number (nil if not a plain number)
---@param s string|number
---@return number|nil
function cas.tonum(s)
   if type(s) == 'number' then return s end
   if type(s) ~= 'string' then return nil end
   s = s:gsub(NEG, '-'):gsub(sym.EE, 'e'):gsub('%s', '')
   if s == sym.INFTY or s == '+' .. sym.INFTY then return math.huge end
   if s == '-' .. sym.INFTY then return -math.huge end
   if s:sub(1, 1) == '(' and s:sub(-1) == ')' then
      s = s:sub(2, -2)
   end
   return tonumber(s)
end

-- Numeric value of an expression (uses approx() when needed)
---@return number|nil
function cas.n(expr)
   local x = cas.tonum(expr)
   if x then return x end
   local res = cas.eval('approx(' .. expr .. ')')
   return res and cas.tonum(res)
end

-- Lua number to CAS string
---@param x number
---@return string
function cas.num(x)
   if x ~= x then return 'undef' end
   if x == math.huge then return sym.INFTY end
   if x == -math.huge then return NEG .. sym.INFTY end
   if x == math.floor(x) and math.abs(x) < 1e15 then
      local s = string.format('%d', math.abs(x))
      return (x < 0 and NEG or '') .. s
   end
   local s = string.format('%.14g', math.abs(x))
   local m, e = s:match('^([%d%.]+)e([-+]%d+)$')
   if m then
      local ev = tonumber(e)
      s = '(' .. m .. '*10^(' .. (ev < 0 and NEG or '') .. tostring(math.abs(ev)) .. '))'
   end
   return (x < 0 and NEG or '') .. s
end

-- True if string is a CAS boolean true
function cas.is_true(s)
   return s == 'true'
end

-- Strip one pair of enclosing quotes
function cas.unquote(s)
   if s and s:sub(1, 1) == '"' and s:sub(-1) == '"' then
      return s:sub(2, -2)
   end
   return s
end

-- Split `str` at top-level separators. `sep` is a single ASCII char or a word
-- like 'or'/'and' (matched as a whole word).
---@return string[]
function cas.split_top(str, sep)
   local parts = {}
   local depth = 0
   local start = 1
   local i, n = 1, #str
   local word = #sep > 1
   while i <= n do
      local c = str:sub(i, i)
      if c == '(' or c == '[' or c == '{' then
         depth = depth + 1
      elseif c == ')' or c == ']' or c == '}' then
         depth = depth - 1
      elseif c == '"' then
         local j = str:find('"', i + 1, true)
         if j then i = j end
      elseif depth == 0 then
         if word then
            if str:sub(i, i + #sep - 1) == sep then
               local before = i > 1 and str:sub(i - 1, i - 1) or ' '
               local after = str:sub(i + #sep, i + #sep)
               if not before:match('[%w_]') and not after:match('[%w_]') then
                  table.insert(parts, str:sub(start, i - 1))
                  start = i + #sep
                  i = start - 1
               end
            end
         elseif c == sep then
            table.insert(parts, str:sub(start, i - 1))
            start = i + 1
         end
      end
      i = i + 1
   end
   table.insert(parts, str:sub(start))
   for k, v in ipairs(parts) do
      parts[k] = v:match('^%s*(.-)%s*$')
   end
   return parts
end

-- Parse a CAS list '{a,b,c}' into a Lua table of strings
---@return string[]|nil
function cas.list(str)
   if not str then return nil end
   str = str:match('^%s*(.-)%s*$')
   if str:sub(1, 1) ~= '{' or str:sub(-1) ~= '}' then return nil end
   local inner = str:sub(2, -2)
   if inner:match('^%s*$') then return {} end
   return cas.split_top(inner, ',')
end

-- Make a CAS list from Lua strings
function cas.mklist(items)
   return '{' .. table.concat(items, ',') .. '}'
end

-- Parse solve() output for variable `var`.
--   'x=1 or x=2' -> {'1','2'}
--   'false'      -> {}
-- Returns nil when the result is not in solved form.
---@return string[]|nil
function cas.solutions(res, var)
   if not res then return nil end
   if res == 'false' then return {} end
   if res == 'true' then return nil end
   local out = {}
   local lvar = var:lower()
   for _, alt in ipairs(cas.split_top(res, 'or')) do
      local found = nil
      for _, conj in ipairs(cas.split_top(alt, 'and')) do
         local lhs, rhs = conj:match('^([%w_]+)%s*=%s*(.+)$')
         if lhs and lhs:lower() == lvar then
            found = rhs
            break
         end
      end
      if not found then return nil end
      table.insert(out, found)
   end
   return out
end

-- Solve equation for var, optional constraint (e.g. 'x>0'); returns list of
-- solution strings or nil if the CAS could not solve explicitly.
function cas.solve(eq, var, constraint)
   local expr = 'solve(' .. eq .. ',' .. var .. ')'
   if constraint and constraint ~= '' then
      expr = expr .. '|' .. constraint
   end
   local res = cas.eval(expr)
   return cas.solutions(res, var), res
end

-- Numeric solve within [lo, hi] (Lua numbers or strings). Returns string or nil.
function cas.nsolve(eq, var, lo, hi)
   local expr
   if lo and hi then
      expr = string.format('nSolve(%s,%s,%s,%s)', eq, var,
                           type(lo) == 'number' and cas.num(lo) or lo,
                           type(hi) == 'number' and cas.num(hi) or hi)
   else
      expr = string.format('nSolve(%s,%s)', eq, var)
   end
   local res = cas.eval(expr)
   if res and cas.tonum(res) then
      return res
   end
   return nil
end

-- Identifier helpers -------------------------------------------------------

-- Iterate over a string and call fn(kind, text, next_char) for each chunk.
-- Kinds: 'id' (ASCII identifier [A-Za-z][A-Za-z0-9_]*), 'num' (number
-- literal), 'sym' (one UTF-8 multibyte character), 'other' (ASCII char).
local function scan(str, fn)
   local i, n = 1, #str
   while i <= n do
      local c = str:sub(i, i)
      local b = c:byte()
      if c:match('%a') then
         local j = i
         while j < n and str:sub(j + 1, j + 1):match('[%w_]') do
            j = j + 1
         end
         fn('id', str:sub(i, j), str:sub(j + 1, j + 1))
         i = j + 1
      elseif c:match('%d') or (c == '.' and str:sub(i + 1, i + 1):match('%d')) then
         local j = i
         while j < n and str:sub(j + 1, j + 1):match('[%d%.]') do
            j = j + 1
         end
         fn('num', str:sub(i, j), str:sub(j + 1, j + 1))
         i = j + 1
      elseif b >= 192 then
         local len = b >= 240 and 4 or (b >= 224 and 3 or 2)
         fn('sym', str:sub(i, i + len - 1), str:sub(i + len, i + len))
         i = i + len
      else
         fn('other', c, str:sub(i + 1, i + 1))
         i = i + 1
      end
   end
end
cas.scan = scan

-- Display names for internal variable names
--   q9<x>  -> x  (local lower case symbol)
--   q7<x>  -> X  (local upper case symbol)
--   q8<x>  -> x  (dummy integration variable)
function cas.display_name(word)
   local p, l = word:match('^q([789])(%a%w*)$')
   if p then
      if p == '7' then return l:upper() end
      return l
   end
   return word
end

-- Internal name for a local symbol
function cas.local_name(letter)
   if letter:match('^%u$') then
      return 'q7' .. letter:lower()
   end
   return 'q9' .. letter:lower()
end

-- Rename identifiers using map (keys compared case-insensitively unless
-- `case` is true). Identifiers followed by '(' (function calls) are kept.
function cas.rename(str, map, case)
   local out = {}
   scan(str, function(kind, text, nextc)
      if kind == 'id' and nextc ~= '(' then
         local key = case and text or text:lower()
         local repl = map[key]
         if repl then
            text = repl
         end
      end
      table.insert(out, text)
   end)
   return table.concat(out)
end

-- Collect free identifiers (not function calls) in expression
---@return table<string, boolean>, string[]
function cas.identifiers(str)
   local set, list = {}, {}
   local skip = { ['and'] = true, ['or'] = true, ['not'] = true, ['true'] = true,
                  ['false'] = true, undef = true, xor = true }
   scan(str, function(kind, text, nextc)
      if kind == 'id' and nextc ~= '(' and not skip[text] and not set[text] then
         set[text] = true
         table.insert(list, text)
      end
   end)
   return set, list
end

-- Normalize user input for the CAS:
--   ASCII aliases (<=, >=, !=, pi, inf, sqrt), unary minus -> NEGATE,
--   e -> Euler's e, '×'/'·' -> '*', optional identifier renaming.
---@param str string
---@param map? table  Rename map for identifiers (lower case keys)
---@param case? boolean Case sensitive rename map
function cas.input(str, map, case)
   if not str then return nil end
   str = str:match('^%s*(.-)%s*$')
   if str == '' then return nil end

   str = str:gsub('<=', sym.LEQ):gsub('>=', sym.GEQ):gsub('!=', sym.NEQ):gsub('/=', sym.NEQ)
   str = str:gsub(sym.TIMES, '*'):gsub(sym.CDOT, '*'):gsub(sym.DIVIDE, '/')
   str = str:gsub('%*%*', '^')

   local aliases = {
      pi = sym.pi, inf = sym.INFTY, infinity = sym.INFTY, oo = sym.INFTY,
      e = sym.EULER,
   }

   -- After these chunks a '-' is a negation, not a subtraction
   local unary_ctx = {
      [''] = true, ['('] = true, ['['] = true, ['{'] = true, [','] = true,
      ['='] = true, ['<'] = true, ['>'] = true, ['^'] = true, ['*'] = true,
      ['/'] = true, ['+'] = true, ['-'] = true, ['|'] = true,
      [sym.LEQ] = true, [sym.GEQ] = true, [sym.NEQ] = true, [NEG] = true,
      [sym.STORE] = true, [sym.ROOT] = true,
      ['and'] = true, ['or'] = true, ['not'] = true,
   }

   local out = {}
   local prev = ''
   scan(str, function(kind, text, nextc)
      local key = case and text or text:lower()
      if kind == 'id' then
         if nextc ~= '(' and map and map[key] then
            text = map[key]
         elseif nextc ~= '(' and aliases[key] then
            text = aliases[key]
         elseif key == 'sqrt' and nextc == '(' then
            text = sym.ROOT
         end
      elseif kind == 'other' and text == '-' and unary_ctx[prev] then
         text = NEG
      end
      if not text:match('^%s+$') then
         prev = kind == 'id' and text:lower() or text
         if kind == 'id' and not unary_ctx[prev] then prev = 'id' end
      end
      table.insert(out, text)
   end)
   return table.concat(out)
end

-- True if expression contains any of the identifiers in `names` (list)
function cas.uses(expr, names)
   local set = cas.identifiers(expr)
   for _, n in ipairs(names) do
      if set[n] then return true end
   end
   return false
end

-- Substitute: expr | a=b and c=d
function cas.with(expr, assigns)
   local parts = {}
   for _, a in ipairs(assigns) do
      table.insert(parts, a[1] .. '=' .. cas.p(a[2]))
   end
   if #parts == 0 then return expr end
   return '(' .. expr .. ')|' .. table.concat(parts, ' and ')
end

return cas
