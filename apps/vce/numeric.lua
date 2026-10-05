-- Compile TI infix expressions into Lua functions for fast numeric
-- evaluation (plotting, sign checks). Results are numbers; nil means the
-- value is undefined (domain error, division by zero, non-real).
--
--   local f = numeric.compile('3*q9x^2-1', { 'q9x' })
--   f(2) --> 11
local expr = require 'expressiontree'
local lexer = require 'ti.lexer'
local sym = require 'ti.sym'

local N = {}

local huge, floor, abs = math.huge, math.floor, math.abs

local UNDEF = {} -- sentinel raised for undefined values

local function undef()
   error(UNDEF)
end

local function num(v)
   if type(v) ~= 'number' or v ~= v then undef() end
   return v
end

-- Real power, including odd roots of negative numbers (x^(1/3))
local function rpow(a, b)
   if a >= 0 or b == floor(b) then
      local r = a ^ b
      if r ~= r then undef() end
      return r
   end
   for q = 3, 15, 2 do
      local p = b * q
      if abs(p - floor(p + 0.5)) < 1e-9 then
         p = floor(p + 0.5)
         local r = (-a) ^ b
         if p % 2 ~= 0 then r = -r end
         return r
      end
   end
   undef()
end

local function f1(fn)
   return function(args)
      local a = args[1]
      return function(env) return fn(num(a(env))) end
   end
end

local function asin(x) if x < -1 or x > 1 then undef() end return math.asin(x) end
local function acos(x) if x < -1 or x > 1 then undef() end return math.acos(x) end
local function ln(x) if x <= 0 then undef() end return math.log(x) end
local function sqrt(x) if x < 0 then undef() end return math.sqrt(x) end
local function sinh(x) return (math.exp(x) - math.exp(-x)) / 2 end
local function cosh(x) return (math.exp(x) + math.exp(-x)) / 2 end
local function tanh(x) local a, b = math.exp(x), math.exp(-x) return (a - b) / (a + b) end
local function sign(x) return x > 0 and 1 or (x < 0 and -1 or 0) end
local function tan(x)
   local c = math.cos(x)
   if abs(c) < 1e-15 then undef() end
   return math.sin(x) / c
end
local function sec(x)
   local c = math.cos(x)
   if abs(c) < 1e-15 then undef() end
   return 1 / c
end
local function csc(x)
   local s = math.sin(x)
   if abs(s) < 1e-15 then undef() end
   return 1 / s
end
local function cot(x)
   local s = math.sin(x)
   if abs(s) < 1e-15 then undef() end
   return math.cos(x) / s
end

local INV = sym.POWN1

local FUNCS = {
   sqrt = f1(sqrt), [sym.ROOT] = f1(sqrt),
   abs = f1(abs), ln = f1(ln), exp = f1(math.exp),
   sin = f1(math.sin), cos = f1(math.cos), tan = f1(tan),
   sec = f1(sec), csc = f1(csc), cot = f1(cot),
   arcsin = f1(asin), arccos = f1(acos), arctan = f1(math.atan),
   ['sin' .. INV] = f1(asin), ['cos' .. INV] = f1(acos), ['tan' .. INV] = f1(math.atan),
   sinh = f1(sinh), cosh = f1(cosh), tanh = f1(tanh),
   floor = f1(floor), ceiling = f1(math.ceil), int = f1(floor), sign = f1(sign),
   approx = f1(function(x) return x end), exact = f1(function(x) return x end),
}

FUNCS.log = function(args)
   local a, b = args[1], args[2]
   return function(env)
      local x = num(a(env))
      local base = b and num(b(env)) or 10
      if x <= 0 or base <= 0 or base == 1 then undef() end
      return math.log(x) / math.log(base)
   end
end

local function int_part(x) return x >= 0 and floor(x) or -floor(-x) end
FUNCS.ipart = f1(int_part)
FUNCS.fpart = f1(function(x) return x - int_part(x) end)

FUNCS.mod = function(args)
   local a, b = args[1], args[2]
   return function(env)
      local x, m = num(a(env)), num(b(env))
      if m == 0 then return x end
      return x - m * floor(x / m)
   end
end

FUNCS.round = function(args)
   local a, b = args[1], args[2]
   return function(env)
      local p = 10 ^ (b and num(b(env)) or 12)
      local x = num(a(env)) * p
      return (x >= 0 and floor(x + 0.5) or -floor(-x + 0.5)) / p
   end
end

FUNCS.root = function(args)
   local a, b = args[1], args[2]
   return function(env)
      local n = num(b(env))
      return rpow(num(a(env)), 1 / n)
   end
end

FUNCS.max = function(args)
   return function(env)
      local m = -huge
      for _, a in ipairs(args) do m = math.max(m, num(a(env))) end
      return m
   end
end

FUNCS.min = function(args)
   return function(env)
      local m = huge
      for _, a in ipairs(args) do m = math.min(m, num(a(env))) end
      return m
   end
end

-- piecewise(e1, c1, e2, c2, ..., [else])
FUNCS.piecewise = function(args)
   return function(env)
      local i = 1
      while i <= #args do
         if i == #args then return args[i](env) end
         if args[i + 1](env) == true then return args[i](env) end
         i = i + 2
      end
      undef()
   end
end

FUNCS.when = function(args)
   local c, a, b = args[1], args[2], args[3]
   return function(env)
      if c(env) == true then return a(env) end
      if b then return b(env) end
      undef()
   end
end

local BIN = {
   ['+'] = function(a, b) return a + b end,
   ['-'] = function(a, b) return a - b end,
   ['*'] = function(a, b) return a * b end,
   ['/'] = function(a, b)
      if b == 0 then undef() end
      return a / b
   end,
   ['^'] = rpow,
}

local REL = {
   ['='] = function(a, b) return a == b end,
   ['<'] = function(a, b) return a < b end,
   ['>'] = function(a, b) return a > b end,
   [sym.LEQ] = function(a, b) return a <= b end,
   [sym.GEQ] = function(a, b) return a >= b end,
   [sym.NEQ] = function(a, b) return a ~= b end,
}

local build

local function build_children(node, vars)
   local out = {}
   for i, c in ipairs(node.children) do out[i] = build(c, vars) end
   return out
end

-- derivative(e, x): central difference in the compiled variable x
local function build_derivative(node, vars)
   local e, v = node.children[1], node.children[2]
   local idx = v and #node.children == 2 and v.kind == expr.SYMBOL and vars[v.text:lower()]
   if not idx then error('unsupported derivative') end
   local f = build(e, vars)
   return function(env)
      local x = num(env[idx])
      local h = 1e-6 * math.max(1, abs(x))
      env[idx] = x + h
      local ok1, a = pcall(f, env)
      env[idx] = x - h
      local ok2, b = pcall(f, env)
      env[idx] = x
      if ok1 and ok2 then return (num(a) - num(b)) / (2 * h) end
      -- one-sided near the edge of the domain
      local ok0, c = pcall(f, env)
      if not ok0 then undef() end
      if ok1 then return (num(a) - num(c)) / h end
      if ok2 then return (num(c) - num(b)) / h end
      undef()
   end
end

build = function(node, vars)
   local k = node.kind
   if k == expr.NUMBER then
      local t = node.text:gsub(sym.EE .. sym.NEGATE, 'e-'):gsub(sym.EE, 'e')
      local v = tonumber(t)
      if not v then error('bad number ' .. node.text) end
      return function() return v end
   elseif k == expr.SYMBOL then
      local name = node.text
      local low = name:lower()
      local idx = vars[low]
      if idx then
         return function(env) return env[idx] end
      end
      if name == sym.pi or low == 'pi' then return function() return math.pi end end
      if name == sym.EULER then
         local e = math.exp(1)
         return function() return e end
      end
      if name == sym.INFTY then return function() return huge end end
      if low == 'true' then return function() return true end end
      if low == 'false' then return function() return false end end
      error('free symbol ' .. name)
   elseif k == expr.FUNCTION then
      local name = node.text
      if name:lower() == 'derivative' then
         return build_derivative(node, vars)
      end
      local f = FUNCS[name] or FUNCS[name:lower()]
      if not f then error('unknown function ' .. name) end
      return f(build_children(node, vars))
   elseif k == expr.OPERATOR then
      local op = node.text
      local ch = build_children(node, vars)
      if op == sym.NEGATE then
         local a = ch[1]
         return function(env) return -num(a(env)) end
      elseif op == '^' and node.children[1].kind == expr.SYMBOL and node.children[1].text == sym.EULER then
         local b = ch[2]
         return function(env)
            local r = math.exp(num(b(env)))
            if r == huge then undef() end
            return r
         end
      elseif BIN[op] then
         local f, a, b = BIN[op], ch[1], ch[2]
         if #ch > 2 then
            return function(env)
               local acc = num(ch[1](env))
               for i = 2, #ch do acc = f(acc, num(ch[i](env))) end
               return acc
            end
         end
         return function(env) return f(num(a(env)), num(b(env))) end
      elseif REL[op] then
         local f, a, b = REL[op], ch[1], ch[2]
         return function(env) return f(num(a(env)), num(b(env))) end
      elseif op == 'and' then
         local a, b = ch[1], ch[2]
         return function(env) return a(env) == true and b(env) == true end
      elseif op == 'or' then
         local a, b = ch[1], ch[2]
         return function(env) return a(env) == true or b(env) == true end
      elseif op == '!' then
         local a = ch[1]
         return function(env)
            local n = num(a(env))
            if n < 0 or n ~= floor(n) then undef() end
            local r = 1
            for i = 2, n do r = r * i end
            return r
         end
      end
      error('unsupported operator ' .. op)
   end
   error('unsupported expression')
end

-- Compile expression string with the given variable names (list).
-- Returns a function(...) -> number|nil, or nil, error message.
function N.compile(src, varnames)
   if type(src) ~= 'string' or src == '' then return nil, 'empty' end
   local vars = {}
   for i, v in ipairs(varnames or {}) do vars[v:lower()] = i end
   local ok, fn = pcall(function()
      local tokens = lexer.tokenize(src)
      if not tokens or #tokens == 0 then error('tokenize') end
      local tree = expr.from_infix(tokens)
      return build(tree, vars)
   end)
   if not ok then
      return nil, type(fn) == 'table' and (fn.desc or '?') or tostring(fn)
   end
   return function(...)
      local env = { ... }
      local ok2, v = pcall(fn, env)
      if not ok2 then return nil end
      if type(v) ~= 'number' or v ~= v then return nil end
      return v
   end
end

-- Compile, falling back to CAS evaluation (slow) when unsupported
function N.compile_or_cas(src, varnames)
   local f = N.compile(src, varnames)
   if f then return f, true end
   local cas = require 'apps.vce.cas'
   return function(...)
      local assigns = {}
      for i, v in ipairs(varnames) do
         table.insert(assigns, { v, cas.num((select(i, ...))) })
      end
      return cas.n(cas.with(src, assigns))
   end, false
end

-- Numeric derivative of f at x (central difference); nil if undefined
function N.deriv(f, x, h)
   h = h or 1e-5 * math.max(1, abs(x))
   local a, b = f(x + h), f(x - h)
   if not a or not b then return nil end
   return (a - b) / (2 * h)
end

-- Bisection on a sign change of g in [a, b]
function N.bisect(g, a, b, iters)
   local ga = g(a)
   if not ga then return nil end
   for _ = 1, iters or 60 do
      local m = (a + b) / 2
      local gm = g(m)
      if not gm then return nil end
      if gm == 0 then return m end
      if (ga < 0) == (gm < 0) then
         a, ga = m, gm
      else
         b = m
      end
   end
   return (a + b) / 2
end

-- Integrate f on [a, b] (finite): 3-point Gauss-Legendre on n panels after
-- the substitution x = a + (b-a)(3u^2 - 2u^3), which never evaluates the
-- endpoints and tames integrable endpoint singularities such as 1/sqrt(x).
local GL = { { -math.sqrt(0.6), 5 / 9 }, { 0, 8 / 9 }, { math.sqrt(0.6), 5 / 9 } }

function N.integrate(f, a, b, n)
   n = n or 200
   local w = b - a
   local s = 0
   for i = 0, n - 1 do
      for _, p in ipairs(GL) do
         local u = (i + (p[1] + 1) / 2) / n
         local v = f(a + w * u * u * (3 - 2 * u))
         if not v then return nil end
         s = s + p[2] * v * 6 * u * (1 - u) * w
      end
   end
   return s / (2 * n)
end

N.UNDEF = UNDEF

return N
