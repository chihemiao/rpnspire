-- Simultaneous linear equations with a parameter (2 or 3 unknowns):
-- unique solution when det ≠ 0; for det = 0 check each value of the
-- parameter for no solution or infinitely many solutions.
local cas = require 'apps.vce.cas'
local U = require 'apps.vce.solvers.util'

local M = U.M
local MAP = U.locals_map()
local abs, max = math.abs, math.max
local LAMBDA, MU = 'q8l', 'q8m'

local S = {
   id = 'simul',
   title = 'Simultaneous equations with a parameter',
   short = 'Simultaneous eqs',
   group = 'Functions',
   course = 'MM',
   desc = 'Unique / no / infinitely many solutions: det = 0, then check each value',
   fields = {
      { id = 'e1', label = 'Equation 1', hint = 'kx+2y=3', implicit = true },
      { id = 'e2', label = 'Equation 2', hint = '2x+(k-3)y=k', implicit = true },
      { id = 'e3', label = 'Equation 3', hint = 'optional: 3 unknowns x, y, z', implicit = true },
   },
   example = { e1 = 'kx+2y=k', e2 = '2x+(k-3)y=k-2' },
}

local function at(e, assigns)
   local map = {}
   for k, v in pairs(assigns) do map[k] = '(' .. v .. ')' end
   return '(' .. cas.rename(e, map, true) .. ')'
end

-- Determinant text of a square matrix of strings (cofactor expansion)
local function det_text(A)
   local n = #A
   if n == 1 then return U.par(A[1][1]) end
   if n == 2 then
      return U.par(A[1][1]) .. '*' .. U.par(A[2][2]) .. '-' .. U.par(A[1][2]) .. '*' .. U.par(A[2][1])
   end
   local parts = {}
   for j = 1, n do
      local minor = {}
      for i = 2, n do
         local row = {}
         for k = 1, n do if k ~= j then table.insert(row, A[i][k]) end end
         table.insert(minor, row)
      end
      local sign = (j % 2 == 1) and '+' or '-'
      table.insert(parts, sign .. U.par(A[1][j]) .. '*(' .. det_text(minor) .. ')')
   end
   return (table.concat(parts):gsub('^%+', ''))
end

-- Numeric rank (partial pivoting)
local function rank(rows, ncols)
   local A = {}
   for i, r in ipairs(rows) do
      A[i] = {}
      for j = 1, ncols do A[i][j] = r[j] end
   end
   local scale = 1e-300
   for _, r in ipairs(A) do for _, v in ipairs(r) do scale = max(scale, abs(v)) end end
   local tol = 1e-9 * scale
   local rk, row = 0, 1
   for col = 1, ncols do
      local piv, best = nil, tol
      for i = row, #A do
         if abs(A[i][col]) > best then piv, best = i, abs(A[i][col]) end
      end
      if piv then
         A[row], A[piv] = A[piv], A[row]
         for i = row + 1, #A do
            local f = A[i][col] / A[row][col]
            for j = col, ncols do A[i][j] = A[i][j] - f * A[row][j] end
         end
         rk = rk + 1
         row = row + 1
         if row > #A then break end
      end
   end
   return rk
end

-- Matrix as TI text [[a,b][c,d]] for display
local function mat_text(A)
   local rows = {}
   for _, r in ipairs(A) do table.insert(rows, '[' .. table.concat(r, ',') .. ']') end
   return '[' .. table.concat(rows) .. ']'
end

local function col_text(v)
   local rows = {}
   for _, x in ipairs(v) do table.insert(rows, '[' .. x .. ']') end
   return '[' .. table.concat(rows) .. ']'
end

-- Solve the square system Ax = d (strings) by Cramer's rule
local function cramer(A, d)
   local D = det_text(A)
   local out = {}
   for j = 1, #A do
      local Aj = {}
      for i = 1, #A do
         Aj[i] = {}
         for k = 1, #A do Aj[i][k] = (k == j) and d[i] or A[i][k] end
      end
      out[j] = U.simp('(' .. det_text(Aj) .. ')/(' .. D .. ')')
   end
   return out
end

function S.solve(I, R)
   local raw = {}
   for _, id in ipairs({ 'e1', 'e2', 'e3' }) do
      if I[id] then table.insert(raw, I[id]) end
   end
   if #raw < 2 then
      R:note('Type two equations (three for x, y, z)')
      return
   end

   -- Read the equations as a x + b y (+ c z) = d ------------------------------------
   local eqs = {}
   local uses_z = false
   for i, text in ipairs(raw) do
      local e = cas.input(text, MAP, false, true)
      local sides = cas.split_top(e, '=')
      if #sides ~= 2 then
         R:note('Equation ' .. i .. ' needs one =', 'error')
         return
      end
      eqs[i] = '(' .. sides[1] .. ')-(' .. sides[2] .. ')'
      if cas.uses(e, { 'q9z' }) then uses_z = true end
   end
   local vars = uses_z and { 'q9x', 'q9y', 'q9z' } or { 'q9x', 'q9y' }
   local nv = #vars
   if #eqs ~= nv then
      R:note(nv .. ' unknowns need ' .. nv .. ' equations', 'error')
      return
   end
   local zero = {}
   for _, v in ipairs(vars) do zero[v] = '0' end
   local A, d = {}, {}
   for i, e in ipairs(eqs) do
      local e0 = U.simp(at(e, zero))
      d[i] = U.simp(U.NEG .. U.par(e0))
      A[i] = {}
      for j = 1, nv do
         local one = {}
         for k, w in ipairs(vars) do one[w] = (k == j) and '1' or '0' end
         A[i][j] = U.simp(at(e, one) .. '-' .. U.par(e0))
      end
   end

   -- Parameter: any other letter
   local set, params = {}, {}
   for i = 1, nv do
      local items = { d[i] }
      for j = 1, nv do table.insert(items, A[i][j]) end
      for _, s in ipairs(items) do
         for _, u in ipairs(U.unknowns(s)) do
            if not set[u] then set[u] = true table.insert(params, u) end
         end
      end
   end
   table.sort(params)
   if #params > 1 then
      R:note('Use one parameter only (found ' .. #params .. ')', 'error')
      return
   end
   local K = params[1]
   local kname = K and cas.display_name(K)

   -- linear check: a x + b y (+ c z) - d must reproduce each equation
   local test = K and { [K] = '1.37' } or {}
   local coef = { 0.7, -1.3, 2.1 }
   for i, e in ipairs(eqs) do
      local env = { q9x = '0.7', q9y = U.NEG .. '1.3', q9z = '2.1' }
      for k, v in pairs(test) do env[k] = v end
      local lhs = cas.n(at(e, env))
      local dn = cas.n(at(d[i], test))
      local sum = dn and -dn
      for j = 1, nv do
         local a = cas.n(at(A[i][j], test))
         if not (sum and a) then sum = nil break end
         sum = sum + coef[j] * a
      end
      if lhs and sum and abs(lhs - sum) > 1e-7 * max(1, abs(lhs)) then
         R:note('Equation ' .. i .. ' is not linear in ' .. (uses_z and 'x, y, z' or 'x, y'), 'error')
         return
      end
   end

   local xs = uses_z and 'x, y, z' or 'x, y'
   R:step('Matrix form ' .. M(mat_text(A) .. '*' .. col_text(uses_z and { 'x', 'y', 'z' } or { 'x', 'y' }) .. '=' .. col_text(d)))
   local D = U.simp(det_text(A))
   R:step('det = ' .. M(det_text(A)) .. ' = ' .. M(D))

   if not K then
      -- No parameter: solve directly ----------------------------------------------------
      local Dn = cas.n(D)
      if Dn and abs(Dn) > 1e-12 then
         local sol = cramer(A, d)
         R:step('det ' .. U.NEQ .. ' 0 ' .. U.IMPL .. ' unique solution')
         for j, v in ipairs(vars) do R:result(cas.display_name(v), sol[j], { key = cas.display_name(v) }) end
         return
      end
   end

   -- det = 0 values ---------------------------------------------------------------------
   local roots
   if K then
      R:section('Unique solution')
      local fac = cas.eval('factor(' .. D .. ')')
      if fac and fac ~= D and not fac:find('factor', 1, true) then R:step('det = ' .. M(fac)) end
      local sols = cas.solve(D .. '=0', K)
      roots = sols or {}
      if #roots == 0 then
         R:step('det ' .. U.NEQ .. ' 0 for every ' .. kname .. ' ' .. U.IMPL .. ' always a unique solution')
         R:result('unique solution', '"every ' .. kname .. '"', { key = 'unique' })
      else
         local conds = {}
         for _, r in ipairs(roots) do table.insert(conds, K .. U.NEQ .. r) end
         R:step('det = 0 ' .. U.IMPL .. ' ' .. M(table.concat((function()
            local t = {}
            for _, r in ipairs(roots) do table.insert(t, K .. '=' .. r) end
            return t
         end)(), ' or ')))
         R:step('Unique solution when det ' .. U.NEQ .. ' 0: ' .. M(table.concat(conds, ' and ')))
         R:result('unique solution', table.concat(conds, ' and '), { key = 'unique' })
         local sol = cramer(A, d)
         for j, v in ipairs(vars) do
            R:result(cas.display_name(v) .. ' (unique)', sol[j], { key = 'sol_' .. cas.display_name(v) })
         end
         R:step('Then ' .. table.concat((function()
            local t = {}
            for j, v in ipairs(vars) do table.insert(t, M(v .. '=' .. sol[j])) end
            return t
         end)(), ', '))
      end
   else
      roots = { false }
   end

   -- Check each value -----------------------------------------------------------------------
   local none, many = {}, {}
   for _, r in ipairs(roots) do
      local assign = K and { [K] = r } or {}
      local An, dn = {}, {}
      local Ae, de = {}, {}
      for i = 1, nv do
         An[i], Ae[i] = {}, {}
         for j = 1, nv do
            Ae[i][j] = K and U.simp(at(A[i][j], assign)) or A[i][j]
            An[i][j] = cas.n(Ae[i][j]) or 0
         end
         de[i] = K and U.simp(at(d[i], assign)) or d[i]
         dn[i] = cas.n(de[i]) or 0
      end
      local aug = {}
      for i = 1, nv do
         aug[i] = {}
         for j = 1, nv do aug[i][j] = An[i][j] end
         aug[i][nv + 1] = dn[i]
      end
      local rA, rAug = rank(An, nv), rank(aug, nv + 1)
      local lines = {}
      for i = 1, nv do
         local lhs = {}
         for j, v in ipairs(vars) do table.insert(lhs, U.par(Ae[i][j]) .. '*' .. v) end
         table.insert(lines, M(U.simp(table.concat(lhs, '+')) .. '=' .. de[i]))
      end
      if K then
         R:section('When ' .. kname .. ' = ' .. U.txt(r))
      else
         R:section('det = 0')
      end
      R:step('The equations become ' .. table.concat(lines, ',  '))
      if rA < rAug then
         if nv == 2 then
            R:step('Same left side ratio but different right side ' .. U.IMPL .. ' parallel lines ' .. U.IMPL .. ' no solution')
         else
            R:step('The equations are inconsistent ' .. U.IMPL .. ' no solution')
         end
         table.insert(none, r)
      else
         -- infinitely many: free variables become λ (and μ)
         local free = nv - rA
         if nv == 2 then
            R:step('The equations are multiples of each other (same line) ' .. U.IMPL .. ' infinitely many solutions')
         else
            R:step('Rank ' .. rA .. ' < ' .. nv .. ' and consistent ' .. U.IMPL .. ' infinitely many solutions')
         end
         -- choose independent equations and pivot variables
         local rows, pivots = {}, {}
         for i = 1, nv do
            local trial = {}
            for _, k in ipairs(rows) do table.insert(trial, An[k]) end
            table.insert(trial, An[i])
            if rank(trial, nv) > #rows then table.insert(rows, i) end
            if #rows == rA then break end
         end
         for j = 1, nv do
            local trial = {}
            for _, i in ipairs(rows) do
               local row = {}
               for _, pj in ipairs(pivots) do table.insert(row, An[i][pj]) end
               table.insert(row, An[i][j])
               table.insert(trial, row)
            end
            if rank(trial, #pivots + 1) > #pivots then table.insert(pivots, j) end
            if #pivots == rA then break end
         end
         local is_pivot, frees = {}, {}
         for _, j in ipairs(pivots) do is_pivot[j] = true end
         for j = 1, nv do if not is_pivot[j] then table.insert(frees, j) end end
         local fv = { LAMBDA, MU }
         local val = {}
         for k, j in ipairs(frees) do val[j] = fv[k] end
         -- solve the pivot variables from the chosen rows
         local Asub, dsub = {}, {}
         for a, i in ipairs(rows) do
            Asub[a] = {}
            for b, j in ipairs(pivots) do Asub[a][b] = Ae[i][j] end
            local rhs = de[i]
            for _, j in ipairs(frees) do rhs = rhs .. '-' .. U.par(Ae[i][j]) .. '*' .. val[j] end
            dsub[a] = rhs
         end
         local sol = #pivots > 0 and cramer(Asub, dsub) or {}
         for b, j in ipairs(pivots) do val[j] = sol[b] end
         local parts = {}
         for j, v in ipairs(vars) do table.insert(parts, M(v .. '=' .. val[j])) end
         R:step('Let ' .. table.concat((function()
            local t = {}
            for k = 1, free do table.insert(t, M(vars[frees[k]] .. '=' .. fv[k])) end
            return t
         end)(), ', ') .. ':  ' .. table.concat(parts, ', ') .. ' (' .. (free == 1 and 'λ' or 'λ, μ') .. ' any real)')
         table.insert(many, { r = r, val = val })
      end
   end

   local function point(val)
      local t = {}
      for j = 1, nv do table.insert(t, val[j]) end
      return 'pt(' .. table.concat(t, ',') .. ')'
   end
   if K then
      local function list(t)
         local out = {}
         for _, x in ipairs(t) do table.insert(out, K .. '=' .. (type(x) == 'table' and x.r or x)) end
         return table.concat(out, ' or ')
      end
      R:result('no solution', #none > 0 and list(none) or '"no value"', { key = 'none' })
      R:result('infinitely many', #many > 0 and list(many) or '"no value"', { key = 'many' })
      for k, mm in ipairs(many) do
         R:result('(' .. xs .. ') when ' .. kname .. ' = ' .. U.txt(mm.r), point(mm.val),
                  { key = 'general' .. (k > 1 and k or '') })
      end
   else
      R:result('solutions', #none > 0 and '"none"' or '"infinitely many"', { key = 'kind' })
      if #many > 0 then
         R:result('(' .. xs .. ')', point(many[1].val), { key = 'general' })
      end
   end
end

return S
