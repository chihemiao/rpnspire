-- Linear combinations of independent random variables: aX + bY + c,
-- X1 + X2 + ... (independent copies), with normal probabilities.
local cas = require 'apps.vce.cas'
local ev = require 'apps.vce.event'
local U = require 'apps.vce.solvers.util'

local M = U.M

local S = {
   id = 'lincomb',
   title = 'Linear combinations of random variables',
   short = 'aX+bY',
   group = 'Probability',
   desc = 'E and Var of aX+bY+c, X1+X2+..., P(2X>Y+3) for normal X, Y',
   fields = {
      { id = 'mx', label = 'E(X)', hint = 'mean of X' },
      { id = 'sx', label = 'SD(X)', hint = 'or Var(X) below' },
      { id = 'vx', label = 'Var(X)', hint = '' },
      { id = 'my', label = 'E(Y)', hint = 'mean of Y (if used)' },
      { id = 'sy', label = 'SD(Y)', hint = 'or Var(Y) below' },
      { id = 'vy', label = 'Var(Y)', hint = '' },
      { id = 'comb', label = 'W =', hint = '2X-3Y+4   X1+X2+X3   3X' },
      { id = 'normal', label = 'X, Y normal', kind = 'choice',
        options = { { 'yes', 'yes (W is normal)' }, { 'no', 'no' } } },
      { id = 'event', label = 'Event', hint = 'W>0   X1+X2>2Y   W<10' },
   },
   example = { mx = '50', sx = '4', my = '30', sy = '3', comb = '2X-3Y', event = 'W>15' },
}

-- Identify random variable identifiers: X, Y, X1, Y2 ... (case-insensitive)
local function rv_base(id)
   local b = id:lower():match('^([xy])%d*$')
   return b
end

local function rv_names(expr)
   local _, list = cas.identifiers(expr)
   local out = {}
   for _, id in ipairs(list) do
      if rv_base(id) then table.insert(out, id) end
   end
   return out
end

function S.solve(I, R)
   local mx, my = U.read(I.mx), U.read(I.my)
   local vx, vy = U.read(I.vx), U.read(I.vy)
   local sx, sy = U.read(I.sx), U.read(I.sy)
   if sx and not vx then vx = U.read(U.par(sx.val) .. '^2') end
   if sy and not vy then vy = U.read(U.par(sy.val) .. '^2') end

   local comb = I.comb and U.trim(I.comb) ~= '' and I.comb or nil
   local event, e = I.event and U.trim(I.event) ~= '' and I.event or nil, nil

   -- Event containing X/Y defines the combination: X1+X2 > 2Y  ->  W = X1+X2-2Y > 0
   if event then
      local norm = ev.normalize(event)
      local parts, ops = ev.split(norm)
      local rv_in = {}
      for i, p in ipairs(parts) do rv_in[i] = #rv_names(p) > 0 end
      if #ops == 1 and rv_in[1] and rv_in[2] then
         comb = '(' .. parts[1] .. ')-(' .. parts[2] .. ')'
         event = 'W' .. ops[1] .. '0'
      elseif #ops == 1 and (rv_in[1] or rv_in[2]) and not (parts[1]:match('^%a$') or parts[2]:match('^%a$')) then
         local idx = rv_in[1] and 1 or 2
         comb = parts[idx]
         parts[idx] = 'W'
         event = parts[1] .. ops[1] .. parts[2]
      elseif #ops == 2 and rv_in[2] and not parts[2]:match('^%a$') then
         comb = parts[2]
         event = parts[1] .. ops[1] .. 'W' .. ops[2] .. parts[3]
      end
   end

   if not comb then
      R:note('Enter the combination W, e.g. 2X-3Y+4 or X1+X2+X3')
      return
   end

   -- Internal names for random variables
   local names = rv_names(comb)
   if #names == 0 then
      R:note('Use X and Y (X1, X2, ... for independent copies)', 'error')
      return
   end
   local map, inner = {}, {}
   for _, id in ipairs(names) do
      inner[id] = 'q7' .. id:lower()
      map[id:lower()] = inner[id]
   end
   local w = cas.input(comb, map)

   -- coefficients by substitution (W is linear)
   local zero = {}
   for _, id in ipairs(names) do table.insert(zero, { inner[id], '0' }) end
   local c = U.simp(cas.with(w, zero))
   local coef = {}
   for _, id in ipairs(names) do
      local a = {}
      for _, id2 in ipairs(names) do
         table.insert(a, { inner[id2], id2 == id and '1' or '0' })
      end
      coef[id] = U.simp(cas.with(w, a) .. '-' .. U.par(c))
   end

   local mean_terms, var_terms, mean_sym, var_sym = {}, {}, {}, {}
   local missing = nil
   local NEG = U.NEG
   -- a*S with a = 1 / -1 shortened
   local function term(a, s, sq)
      if sq then
         if a == '1' or a == NEG .. '1' then return s end
         return U.par(a) .. '^2*' .. s
      end
      if a == '1' then return s end
      if a == NEG .. '1' then return NEG .. s end
      return U.par(a) .. '*' .. s
   end
   local function join(list)
      local out = list[1] or '0'
      for i = 2, #list do
         local t = list[i]
         if t:sub(1, #NEG) == NEG then
            out = out .. '-' .. t:sub(#NEG + 1)
         else
            out = out .. '+' .. t
         end
      end
      return out
   end
   for _, id in ipairs(names) do
      local b = rv_base(id)
      local mu = b == 'x' and mx or my
      local v = b == 'x' and vx or vy
      local B = id:upper()
      local a = coef[id]
      table.insert(mean_sym, term(a, 'E(' .. B .. ')'))
      table.insert(var_sym, term(a, 'Var(' .. B .. ')', true))
      if not mu then missing = 'E(' .. b:upper() .. ')' else
         table.insert(mean_terms, term(a, U.par(mu.val)))
      end
      if not v then missing = missing or ('Var(' .. b:upper() .. ')') else
         table.insert(var_terms, term(a, U.par(v.val), true))
      end
   end
   if missing then
      R:note('Enter ' .. missing, 'error')
      return
   end
   local cn = cas.n(c)
   if cn ~= 0 then
      table.insert(mean_sym, c)
      table.insert(mean_terms, c)
   end

   local mean_expr = join(mean_terms)
   local var_expr = join(var_terms)
   local mean = U.simp(mean_expr)
   local var = U.simp(var_expr)
   local sd = U.simp(U.ROOT .. '(' .. var .. ')')

   R:step('W = ' .. M(w))
   if #names > 1 then
      R:step('Independent ' .. U.IMPL .. ' Var(W) is the sum of a' .. U.SQ .. 'Var terms')
   end
   R:step('E(W) = ' .. M(join(mean_sym)) .. ' = ' .. M(mean_expr) .. ' ' .. U.eq(mean))
   R:step('Var(W) = ' .. M(join(var_sym)) .. ' = ' .. M(var_expr) .. ' ' .. U.eq(var))
   R:step('SD(W) = ' .. M(U.ROOT .. '(' .. var .. ')') .. ' ' .. U.eq(sd))
   R:result('E(W)', mean, { key = 'mean' })
   R:result('Var(W)', var, { key = 'var' })
   R:result('SD(W)', sd, { key = 'sd' })

   if not event then return end
   if I.normal == 'no' then
      R:note('Probabilities need X and Y normal', 'warn')
      return
   end
   local err
   e, err = ev.parse(event, { 'w' })
   if not e then
      R:note(err, 'error')
      return
   end
   local lo, hi = U.bound(e.lo), U.bound(e.hi)
   R:step('W ~ N' .. M('(' .. mean .. ',' .. var .. ')'))
   local expr = string.format('normCdf(%s,%s,%s,%s)', lo or U.NEGINF, hi or U.INF, mean, sd)
   local p = U.simp(expr)
   local d = ev.describe(e, 'W')
   R:step(d .. ' = ' .. M(expr) .. ' ' .. U.eq(p))
   R:result(d, p, { key = 'prob' })
end

return S
