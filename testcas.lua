-- Numeric mock of the TI-Nspire CAS used by desktop tests.
--
-- It evaluates TI infix strings numerically (normCdf, invNorm, binomCdf,
-- integral, derivative, solve, nSolve, ...). Expressions that still contain
-- free variables are returned unevaluated, so symbolic results can be
-- substituted and evaluated later (e.g. "expr|q9t=2"). It is NOT a CAS: it
-- only lets tests check that solvers build mathematically correct
-- expressions. Real TI syntax still has to be validated on a calculator.
local expr = require 'expressiontree'
local lexer = require 'ti.lexer'
local sym = require 'ti.sym'

local M = {}

-- User-defined functions available to the mock: name -> {params, body}
M.functions = {}

local FREE = {} -- sentinel error for free variables

local function free()
   error(FREE)
end

local function is_list(v) return type(v) == 'table' and v.list end
local function mklist(t) t.list = true; return t end

-- Normal distribution ------------------------------------------------------

local function erfc(x)
   -- Numerical Recipes erfc approximation (fractional error < 1.2e-7),
   -- refined below for better precision via series for small |x|.
   local z = math.abs(x)
   local t = 1 / (1 + 0.5 * z)
   local r = t * math.exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 +
      t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 +
      t * (-0.82215223 + t * 0.17087277)))))))))
   if x >= 0 then return r else return 2 - r end
end

local function erf_series(x)
   -- Maclaurin series, accurate for |x| < 3
   local sum, term, n = x, x, 0
   repeat
      n = n + 1
      term = -term * x * x / n
      local add = term / (2 * n + 1)
      sum = sum + add
   until math.abs(add) < 1e-17 or n > 200
   return 2 / math.sqrt(math.pi) * sum
end

local function phi(z)
   if z == math.huge then return 1 end
   if z == -math.huge then return 0 end
   local x = z / math.sqrt(2)
   if math.abs(x) < 3 then
      return 0.5 * (1 + erf_series(x))
   end
   return 0.5 * erfc(-x)
end

local function pdf_std(z)
   return math.exp(-z * z / 2) / math.sqrt(2 * math.pi)
end

local function inv_phi(p)
   if p <= 0 then return -math.huge end
   if p >= 1 then return math.huge end
   -- Acklam's algorithm
   local a = { -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
               1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00 }
   local b = { -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
               6.680131188771972e+01, -1.328068155288572e+01 }
   local c = { -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
               -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00 }
   local d = { 7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
               3.754408661907416e+00 }
   local plow, phigh = 0.02425, 1 - 0.02425
   local x
   if p < plow then
      local q = math.sqrt(-2 * math.log(p))
      x = (((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) * q + c[6]) /
          ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1)
   elseif p <= phigh then
      local q = p - 0.5
      local r = q * q
      x = (((((a[1] * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * r + a[6]) * q /
          (((((b[1] * r + b[2]) * r + b[3]) * r + b[4]) * r + b[5]) * r + 1)
   else
      local q = math.sqrt(-2 * math.log(1 - p))
      x = -(((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) * q + c[6]) /
           ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1)
   end
   -- Newton refinement
   for _ = 1, 2 do
      local e = phi(x) - p
      x = x - e / pdf_std(x)
   end
   return x
end

local function ncr(n, r)
   if r < 0 or r > n then return 0 end
   r = math.min(r, n - r)
   local v = 1
   for i = 1, r do
      v = v * (n - r + i) / i
   end
   return math.floor(v + 0.5)
end

local function binom_pdf(n, p, k)
   if k < 0 or k > n or k ~= math.floor(k) then return 0 end
   return ncr(n, k) * p ^ k * (1 - p) ^ (n - k)
end

local function binom_cdf(n, p, a, b)
   a = math.max(0, math.ceil(a))
   b = math.min(n, math.floor(b))
   local s = 0
   for k = a, b do s = s + binom_pdf(n, p, k) end
   return s
end

-- Numerics -----------------------------------------------------------------

local function simpson(f, a, b, n)
   n = n or 200
   if n % 2 == 1 then n = n + 1 end
   local h = (b - a) / n
   local s = f(a) + f(b)
   for i = 1, n - 1 do
      s = s + (i % 2 == 1 and 4 or 2) * f(a + i * h)
   end
   return s * h / 3
end

local function integrate(f, a, b)
   if a == b then return 0 end
   if a > b then return -integrate(f, b, a) end
   if a == -math.huge and b == math.huge then
      return integrate(f, -math.huge, 0) + integrate(f, 0, math.huge)
   end
   if b == math.huge then
      -- x = a + t/(1-t)
      return simpson(function(t)
         if t >= 1 then return 0 end
         local x = a + t / (1 - t)
         return f(x) / ((1 - t) * (1 - t))
      end, 0, 1 - 1e-9, 2000)
   end
   if a == -math.huge then
      return simpson(function(t)
         if t >= 1 then return 0 end
         local x = b - t / (1 - t)
         return f(x) / ((1 - t) * (1 - t))
      end, 0, 1 - 1e-9, 2000)
   end
   -- composite with more intervals for accuracy
   return simpson(f, a, b, 400)
end

local function bisect(f, a, b)
   local fa = f(a)
   for _ = 1, 200 do
      local m = (a + b) / 2
      local fm = f(m)
      if fm == 0 then return m end
      if (fa < 0) == (fm < 0) then
         a, fa = m, fm
      else
         b = m
      end
      if math.abs(b - a) < 1e-13 * math.max(1, math.abs(a)) then break end
   end
   return (a + b) / 2
end

local function find_roots(f, lo, hi, samples)
   samples = samples or 4000
   local roots = {}
   local function safe(x)
      local ok, v = pcall(f, x)
      if ok and type(v) == 'number' and v == v and math.abs(v) ~= math.huge then return v end
      return nil
   end
   local step = (hi - lo) / samples
   local px, pv = lo, safe(lo)
   if pv == 0 then table.insert(roots, lo) end
   for i = 1, samples do
      local x = lo + i * step
      local v = safe(x)
      if v and v == 0 then
         table.insert(roots, x)
      elseif v and pv and (v < 0) ~= (pv < 0) then
         local r = bisect(function(t) return safe(t) or 0 end, px, x)
         -- reject poles: value must be small near root
         local fr = safe(r)
         if fr and math.abs(fr) < 1e-6 * (1 + math.abs(v) + math.abs(pv)) then
            table.insert(roots, r)
         end
      end
      px, pv = x, v
   end
   -- dedupe
   local out = {}
   for _, r in ipairs(roots) do
      if #out == 0 or math.abs(out[#out] - r) > 1e-9 * (1 + math.abs(r)) then
         table.insert(out, r)
      end
   end
   return out
end

-- Formatting -----------------------------------------------------------------

local function fmtnum(x)
   if x ~= x then return 'undef' end
   if x == math.huge then return sym.INFTY end
   if x == -math.huge then return sym.NEGATE .. sym.INFTY end
   local s
   if x == math.floor(x) and math.abs(x) < 1e15 then
      s = string.format('%d', math.abs(x))
   else
      s = string.format('%.12g', math.abs(x))
      if s:find('e') then
         local m, e = s:match('^([%d%.]+)e([-+]%d+)$')
         local ev = tonumber(e)
         s = m .. sym.EE .. (ev < 0 and sym.NEGATE or '') .. tostring(math.abs(ev))
      end
   end
   return (x < 0 and sym.NEGATE or '') .. s
end

local function fmtval(v)
   if type(v) == 'number' then return fmtnum(v) end
   if type(v) == 'boolean' then return v and 'true' or 'false' end
   if type(v) == 'string' then return '"' .. v .. '"' end
   if is_list(v) then
      local parts = {}
      for _, x in ipairs(v) do table.insert(parts, fmtval(x)) end
      return '{' .. table.concat(parts, ',') .. '}'
   end
   return tostring(v)
end
M.format = fmtval

-- Evaluator -------------------------------------------------------------------

local eval

local function elementwise(a, b, f)
   if is_list(a) and is_list(b) then
      local r = {}
      for i = 1, math.max(#a, #b) do r[i] = f(a[i], b[i]) end
      return mklist(r)
   elseif is_list(a) then
      local r = {}
      for i = 1, #a do r[i] = f(a[i], b) end
      return mklist(r)
   elseif is_list(b) then
      local r = {}
      for i = 1, #b do r[i] = f(a, b[i]) end
      return mklist(r)
   end
   return f(a, b)
end

local function num(v)
   if type(v) ~= 'number' then error('number expected') end
   return v
end

local function copy_env(env)
   local e = {}
   for k, v in pairs(env) do e[k] = v end
   return e
end

local function with_var(env, name, value)
   local e = copy_env(env)
   e[name:lower()] = value
   return e
end

-- Split an equation node into f(x) = lhs - rhs
local function eq_fn(node, var, env)
   local lhs, rhs = node, nil
   if node.kind == expr.OPERATOR and node.text == '=' then
      lhs, rhs = node.children[1], node.children[2]
   end
   return function(x)
      local e = with_var(env, var, x)
      local l = num(eval(lhs, e))
      if rhs then return l - num(eval(rhs, e)) end
      return l
   end
end

-- Interval for variable from constraint list
local function bounds_for(var, ctx, lo, hi)
   lo, hi = lo or -1000, hi or 1000
   for _, c in ipairs(ctx and ctx.constraints or {}) do
      local op, a, b = c.text, c.children[1], c.children[2]
      local function isvar(n) return n.kind == expr.SYMBOL and n.text:lower() == var:lower() end
      local ok, val
      if isvar(a) then
         ok, val = pcall(eval, b, ctx.env)
         if ok and type(val) == 'number' then
            if op == '>' or op == sym.GEQ then lo = math.max(lo, val) end
            if op == '<' or op == sym.LEQ then hi = math.min(hi, val) end
         end
      elseif isvar(b) then
         ok, val = pcall(eval, a, ctx.env)
         if ok and type(val) == 'number' then
            if op == '<' or op == sym.LEQ then lo = math.max(lo, val) end
            if op == '>' or op == sym.GEQ then hi = math.min(hi, val) end
         end
      end
   end
   return lo, hi
end

local function collect_constraints(node, out)
   if node.kind == expr.OPERATOR and node.text == 'and' then
      for _, c in ipairs(node.children) do collect_constraints(c, out) end
   else
      table.insert(out, node)
   end
   return out
end

local function fn_lower(name)
   return name:lower()
end

local funcs = {}

funcs['normcdf'] = function(args, env)
   local v = {}
   for i, a in ipairs(args) do v[i] = num(eval(a, env)) end
   local lo, hi, mu, sd = v[1], v[2], v[3] or 0, v[4] or 1
   return phi((hi - mu) / sd) - phi((lo - mu) / sd)
end

funcs['normpdf'] = function(args, env)
   local x = num(eval(args[1], env))
   local mu = args[2] and num(eval(args[2], env)) or 0
   local sd = args[3] and num(eval(args[3], env)) or 1
   return pdf_std((x - mu) / sd) / sd
end

funcs['invnorm'] = function(args, env)
   local p = num(eval(args[1], env))
   local mu = args[2] and num(eval(args[2], env)) or 0
   local sd = args[3] and num(eval(args[3], env)) or 1
   return mu + sd * inv_phi(p)
end

funcs['binompdf'] = function(args, env)
   local n, p = num(eval(args[1], env)), num(eval(args[2], env))
   if args[3] then return binom_pdf(n, p, num(eval(args[3], env))) end
   local r = {}
   for k = 0, n do r[k + 1] = binom_pdf(n, p, k) end
   return mklist(r)
end

funcs['binomcdf'] = function(args, env)
   local n, p = num(eval(args[1], env)), num(eval(args[2], env))
   if #args == 3 then return binom_cdf(n, p, 0, num(eval(args[3], env))) end
   return binom_cdf(n, p, num(eval(args[3], env)), num(eval(args[4], env)))
end

funcs['ncr'] = function(args, env)
   return ncr(num(eval(args[1], env)), num(eval(args[2], env)))
end

funcs['approx'] = function(args, env) return eval(args[1], env) end
funcs['exact'] = funcs['approx']

local function unary(f)
   return function(args, env)
      return elementwise(eval(args[1], env), nil, function(a) return f(num(a)) end)
   end
end

funcs['abs'] = unary(math.abs)
funcs['sqrt'] = unary(function(x) if x < 0 then error('nonreal') end return math.sqrt(x) end)
funcs[sym.ROOT] = funcs['sqrt']
funcs['ln'] = unary(function(x) if x <= 0 then error('domain') end return math.log(x) end)
funcs['exp'] = unary(math.exp)
funcs['sin'] = unary(math.sin)
funcs['cos'] = unary(math.cos)
funcs['tan'] = unary(math.tan)
funcs['arcsin'] = unary(math.asin)
funcs['arccos'] = unary(math.acos)
funcs['arctan'] = unary(function(x) return math.atan(x) end)
funcs['floor'] = unary(math.floor)
funcs['ceiling'] = unary(math.ceil)
funcs['int'] = unary(math.floor)
funcs['sign'] = unary(function(x) return x > 0 and 1 or (x < 0 and -1 or 0) end)
funcs['log'] = function(args, env)
   local x = num(eval(args[1], env))
   local b = args[2] and num(eval(args[2], env)) or 10
   return math.log(x) / math.log(b)
end
funcs['round'] = function(args, env)
   local x = num(eval(args[1], env))
   local d = args[2] and num(eval(args[2], env)) or 0
   local m = 10 ^ d
   return math.floor(x * m + 0.5) / m
end

funcs['sum'] = function(args, env)
   local l = eval(args[1], env)
   if not is_list(l) then return num(l) end
   local s = 0
   for _, v in ipairs(l) do s = s + num(v) end
   return s
end

funcs['dim'] = function(args, env)
   local l = eval(args[1], env)
   return #l
end

funcs['max'] = function(args, env)
   local vals = {}
   for _, a in ipairs(args) do
      local v = eval(a, env)
      if is_list(v) then for _, x in ipairs(v) do table.insert(vals, x) end else table.insert(vals, v) end
   end
   local m = -math.huge
   for _, v in ipairs(vals) do m = math.max(m, num(v)) end
   return m
end

funcs['min'] = function(args, env)
   local vals = {}
   for _, a in ipairs(args) do
      local v = eval(a, env)
      if is_list(v) then for _, x in ipairs(v) do table.insert(vals, x) end else table.insert(vals, v) end
   end
   local m = math.huge
   for _, v in ipairs(vals) do m = math.min(m, num(v)) end
   return m
end

funcs['seq'] = function(args, env)
   local var = args[2].text
   local a, b = num(eval(args[3], env)), num(eval(args[4], env))
   local step = args[5] and num(eval(args[5], env)) or 1
   local r = {}
   for i = a, b, step do
      table.insert(r, eval(args[1], with_var(env, var, i)))
   end
   return mklist(r)
end

funcs['when'] = function(args, env)
   local c = eval(args[1], env)
   if c then return eval(args[2], env) end
   return args[3] and eval(args[3], env) or 'undef'
end

funcs['piecewise'] = function(args, env)
   local i = 1
   while i <= #args do
      if i == #args then return eval(args[i], env) end
      if eval(args[i + 1], env) == true then return eval(args[i], env) end
      i = i + 2
   end
   return 0 / 0
end

funcs['integral'] = function(args, env)
   if #args < 4 then free() end
   local var = args[2].text
   local a, b = num(eval(args[3], env)), num(eval(args[4], env))
   return integrate(function(x) return num(eval(args[1], with_var(env, var, x))) end, a, b)
end
funcs[sym.INTEGRAL] = funcs['integral']
funcs['nint'] = funcs['integral']

funcs['derivative'] = function(args, env)
   local var = args[2].text:lower()
   local at = env[var]
   if at == nil then free() end
   local order = args[3] and num(eval(args[3], env)) or 1
   local function f(x) return num(eval(args[1], with_var(env, var, x))) end
   local h = 1e-4 * math.max(1, math.abs(at))
   if order == 2 then
      return (f(at + h) - 2 * f(at) + f(at - h)) / (h * h)
   end
   return (f(at + h) - f(at - h)) / (2 * h)
end
funcs['d'] = funcs['derivative']
funcs['nderivative'] = funcs['derivative']

local function solve_impl(args, env, ctx, single)
   local var = args[2].text
   if args[2].kind == expr.OPERATOR and args[2].text == '=' then
      -- nSolve(eq, x=guess)
      var = args[2].children[1].text
   end
   local f = eq_fn(args[1], var, env)
   local lo, hi = bounds_for(var, ctx, nil, nil)
   if args[3] and args[4] then
      lo, hi = num(eval(args[3], env)), num(eval(args[4], env))
   end
   -- Probe for free variables
   local ok, err = pcall(f, (lo + hi) / 2)
   if not ok and err == FREE then free() end
   local bounded = (hi - lo) <= 100
   local roots = find_roots(f, lo, hi, bounded and 300 or (single and 2000 or 4000))
   return roots, var
end

local function solve_system(args, env)
   local vars = {}
   for _, v in ipairs(args[2].children) do table.insert(vars, v.text) end
   local eqs = collect_constraints(args[1], {})
   local fs = {}
   for i, eq in ipairs(eqs) do fs[i] = eq end
   local function F(x)
      local e = copy_env(env)
      for i, v in ipairs(vars) do e[v:lower()] = x[i] end
      local r = {}
      for i, eq in ipairs(fs) do
         r[i] = num(eval(eq.children[1], e)) - num(eval(eq.children[2], e))
      end
      return r
   end
   local x = {}
   for i = 1, #vars do x[i] = 0.1 * i end
   local n = #vars
   for _ = 1, 50 do
      local f0 = F(x)
      local J = {}
      for j = 1, n do
         local xh = {}
         for i = 1, n do xh[i] = x[i] end
         xh[j] = xh[j] + 1e-7
         local fh = F(xh)
         for i = 1, n do
            J[i] = J[i] or {}
            J[i][j] = (fh[i] - f0[i]) / 1e-7
         end
      end
      -- solve J d = -f0 (Gaussian elimination)
      local A = {}
      for i = 1, n do
         A[i] = {}
         for j = 1, n do A[i][j] = J[i][j] end
         A[i][n + 1] = -f0[i]
      end
      for c = 1, n do
         local piv = c
         for r = c + 1, n do if math.abs(A[r][c]) > math.abs(A[piv][c]) then piv = r end end
         A[c], A[piv] = A[piv], A[c]
         for r = c + 1, n do
            local f = A[r][c] / A[c][c]
            for k = c, n + 1 do A[r][k] = A[r][k] - f * A[c][k] end
         end
      end
      local d = {}
      for i = n, 1, -1 do
         local sum = A[i][n + 1]
         for k = i + 1, n do sum = sum - A[i][k] * d[k] end
         d[i] = sum / A[i][i]
      end
      local maxd = 0
      for i = 1, n do
         x[i] = x[i] + d[i]
         maxd = math.max(maxd, math.abs(d[i]))
      end
      if maxd < 1e-13 then break end
   end
   return { system = vars, values = x }
end

funcs['solve'] = function(args, env, ctx)
   if args[2].kind == expr.LIST then
      return solve_system(args, env)
   end
   local roots, var = solve_impl(args, env, ctx, false)
   if #roots == 0 then return { solved = var, roots = {} } end
   return { solved = var, roots = roots }
end

funcs['nsolve'] = function(args, env, ctx)
   local roots = solve_impl(args, env, ctx, true)
   if #roots == 0 then error('no solution') end
   if args[2].kind == expr.OPERATOR and args[2].text == '=' then
      -- pick root closest to guess
      local g = num(eval(args[2].children[2], env))
      table.sort(roots, function(a, b) return math.abs(a - g) < math.abs(b - g) end)
   end
   return roots[1]
end

funcs['zeros'] = function(args, env, ctx)
   local roots = solve_impl(args, env, ctx, false)
   return mklist(roots)
end

local function fopt(args, env, ctx, sign)
   local var = args[2].text
   local lo, hi = bounds_for(var, ctx, -100, 100)
   local function f(x) return sign * num(eval(args[1], with_var(env, var, x))) end
   local best, bx = -math.huge, lo
   local n = 2000
   for i = 0, n do
      local x = lo + (hi - lo) * i / n
      local ok, v = pcall(f, x)
      if ok and v > best then best, bx = v, x end
   end
   -- golden refinement
   local a, b = math.max(lo, bx - (hi - lo) / n), math.min(hi, bx + (hi - lo) / n)
   for _ = 1, 100 do
      local m1, m2 = a + (b - a) * 0.382, a + (b - a) * 0.618
      if f(m1) > f(m2) then b = m2 else a = m1 end
   end
   return { solved = var, roots = { (a + b) / 2 } }
end

funcs['fmax'] = function(args, env, ctx) return fopt(args, env, ctx, 1) end
funcs['fmin'] = function(args, env, ctx) return fopt(args, env, ctx, -1) end

funcs['limit'] = function(args, env)
   local var = args[2].text
   local p = num(eval(args[3], env))
   local x = p == math.huge and 1e7 or (p == -math.huge and -1e7 or p + 1e-7)
   return num(eval(args[1], with_var(env, var, x)))
end

funcs['string'] = function(args, env)
   return fmtval(eval(args[1], env))
end

funcs['gettype'] = function(args, env)
   local name = args[1].text:lower()
   if M.functions[name] then return 'FUNC' end
   if env[name] ~= nil then return 'NUM' end
   return 'NONE'
end

local function apply_user_fn(name, args, env)
   local def = M.functions[name]
   local e = copy_env(env)
   for i, p in ipairs(def.params) do
      e[p] = eval(args[i], env)
   end
   local tree = expr.from_infix(lexer.tokenize(def.body))
   return eval(tree, e)
end

local binops = {
   ['+'] = function(a, b) return a + b end,
   ['-'] = function(a, b) return a - b end,
   ['*'] = function(a, b) return a * b end,
   ['/'] = function(a, b) if b == 0 then error('divide by zero') end return a / b end,
   ['^'] = function(a, b)
      if a < 0 and b ~= math.floor(b) then
         -- odd roots of negative numbers
         local inv = 1 / b
         if math.abs(inv - math.floor(inv + 0.5)) < 1e-12 and math.floor(inv + 0.5) % 2 == 1 then
            return -((-a) ^ b)
         end
         error('nonreal')
      end
      return a ^ b
   end,
}

local relops = {
   ['='] = function(a, b) return math.abs(a - b) < 1e-12 * (1 + math.abs(a)) end,
   ['<'] = function(a, b) return a < b end,
   ['>'] = function(a, b) return a > b end,
   [sym.LEQ] = function(a, b) return a <= b end,
   [sym.GEQ] = function(a, b) return a >= b end,
   [sym.NEQ] = function(a, b) return a ~= b end,
}

eval = function(node, env, ctx)
   local k = node.kind
   if k == expr.NUMBER then
      local t = node.text:gsub(sym.EE .. sym.NEGATE, 'e-'):gsub(sym.EE, 'e')
      return tonumber(t)
   elseif k == expr.SYMBOL then
      local name = node.text
      local low = name:lower()
      if name == sym.pi or low == 'pi' then return math.pi end
      if name == sym.EULER then return math.exp(1) end
      if name == sym.INFTY then return math.huge end
      if low == 'true' then return true end
      if low == 'false' then return false end
      local v = env[low]
      if v == nil then free() end
      return v
   elseif k == expr.STRING then
      return node.text:sub(2, -2)
   elseif k == expr.LIST then
      local r = {}
      for i, c in ipairs(node.children) do r[i] = eval(c, env) end
      return mklist(r)
   elseif k == expr.FUNCTION then
      local name = fn_lower(node.text)
      if M.functions[name] then
         return apply_user_fn(name, node.children, env)
      end
      local f = funcs[name] or funcs[node.text]
      if not f then error('unknown function ' .. node.text) end
      return f(node.children, env, ctx or { env = env })
   elseif k == expr.OPERATOR then
      local op = node.text
      local ch = node.children
      if op == sym.NEGATE then
         return elementwise(eval(ch[1], env), nil, function(a) return -num(a) end)
      elseif op == '|' then
         local e = copy_env(env)
         local constraints = {}
         local conds = collect_constraints(ch[2], {})
         for _, c in ipairs(conds) do
            if c.kind == expr.OPERATOR and c.text == '=' and c.children[1].kind == expr.SYMBOL then
               e[c.children[1].text:lower()] = eval(c.children[2], e)
            else
               table.insert(constraints, c)
            end
         end
         return eval(ch[1], e, { env = e, constraints = constraints })
      elseif op == '!' then
         local n = num(eval(ch[1], env))
         local r = 1
         for i = 2, n do r = r * i end
         return r
      elseif binops[op] then
         local a = eval(ch[1], env)
         local b = eval(ch[2], env)
         return elementwise(a, b, function(x, y) return binops[op](num(x), num(y)) end)
      elseif relops[op] then
         local a, b = eval(ch[1], env), eval(ch[2], env)
         return relops[op](num(a), num(b))
      elseif op == 'and' then
         return eval(ch[1], env) == true and eval(ch[2], env) == true
      elseif op == 'or' then
         return eval(ch[1], env) == true or eval(ch[2], env) == true
      elseif op == sym.STORE then
         return eval(ch[1], env)
      end
      error('unsupported operator ' .. op)
   end
   error('unsupported node ' .. tostring(k))
end

-- Pre-process TI input so the rpnspire lexer can parse it
local function preprocess(s)
   -- '∫(' and 'd(' are plain function names for the lexer already
   return s
end

-- Evaluate a TI expression string like math.evalStr
function M.evalStr(s)
   local tokens = lexer.tokenize(preprocess(s))
   if not tokens then return nil, 910 end
   local ok, tree = pcall(expr.from_infix, tokens)
   if not ok or not tree then return nil, 910 end
   local ok2, v = pcall(eval, tree, M.env or {})
   if not ok2 then
      if v == FREE then
         -- unevaluated symbolic result: return input unchanged
         return s
      end
      return nil, 900
   end
   if type(v) == 'table' and v.system then
      local parts = {}
      for i, name in ipairs(v.system) do
         table.insert(parts, name .. '=' .. fmtnum(v.values[i]))
      end
      return table.concat(parts, ' and ')
   end
   if type(v) == 'table' and v.solved then
      if #v.roots == 0 then return 'false' end
      local parts = {}
      for _, r in ipairs(v.roots) do
         table.insert(parts, v.solved .. '=' .. fmtnum(r))
      end
      return table.concat(parts, ' or ')
   end
   return fmtval(v)
end

M.phi = phi
M.inv_phi = inv_phi
M.binom_cdf = binom_cdf

return M
