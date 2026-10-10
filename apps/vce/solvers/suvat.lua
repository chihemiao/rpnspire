-- Constant acceleration (SUVAT): enter any three of s, u, v, a, t
local cas = require 'apps.vce.cas'
local U = require 'apps.vce.solvers.util'

local M = U.M

local S = {
   id = 'suvat',
   title = 'Constant acceleration (SUVAT)',
   short = 'SUVAT',
   group = 'Mechanics',
   desc = 'Any 3 of s, u, v, a, t (values or f11(2) from other pages)',
   fields = {
      { id = 's', label = 's', hint = 'displacement' },
      { id = 'u', label = 'u', hint = 'initial velocity' },
      { id = 'v', label = 'v', hint = 'final velocity' },
      { id = 'a', label = 'a', hint = 'acceleration (e.g. -9.8)' },
      { id = 't', label = 't', hint = 'time' },
   },
   example = { u = '0', a = '9.8', t = '2' },
}

local VARS = { 's', 'u', 'v', 'a', 't' }

-- Each formula omits one variable; `lin` lists variables it is linear in
local F = {
   { lacks = 's', text = 'v=u+a*t', eq = 'q9v=q9u+q9a*q9t', lin = { v = true, u = true, a = true, t = true } },
   { lacks = 'a', text = 's=(u+v)/2*t', eq = 'q9s=(q9u+q9v)/2*q9t', lin = { s = true, u = true, v = true, t = true } },
   { lacks = 'v', text = 's=u*t+1/2*a*t^2', eq = 'q9s=q9u*q9t+1/2*q9a*q9t^2', lin = { s = true, u = true, a = true } },
   { lacks = 'u', text = 's=v*t-1/2*a*t^2', eq = 'q9s=q9v*q9t-1/2*q9a*q9t^2', lin = { s = true, v = true, a = true } },
   { lacks = 't', text = 'v^2=u^2+2*a*s', eq = 'q9v^2=q9u^2+2*q9a*q9s', lin = { a = true, s = true } },
}

local function formula_lacking(var)
   for _, f in ipairs(F) do
      if f.lacks == var then return f end
   end
end

local function contains(f, var)
   return f.lacks ~= var
end

-- Substitute known values into formula equation (display + solve form)
local function substitute(f, known)
   local map = {}
   for k, v in pairs(known) do
      map['q9' .. k] = U.par(v)
   end
   return cas.rename(f.eq, map, true)
end

-- Solve formula f for var given known values; returns list of solutions
local function solve_for(f, var, known)
   local eq = substitute(f, known)
   local sols = cas.solve(eq, 'q9' .. var)
   return sols or {}, eq
end

function S.solve(I, R)
   local known, order = {}, {}
   for _, k in ipairs(VARS) do
      local r = U.read(I[k])
      if r then
         known[k] = r.val
         table.insert(order, k)
      end
   end

   if #order < 3 then
      R:note('Enter any three of s, u, v, a, t')
      return
   end

   local unknown = {}
   for _, k in ipairs(VARS) do
      if not known[k] then table.insert(unknown, k) end
   end

   if #unknown == 0 or #order > 3 then
      -- Check consistency of all formulas
      local all = {}
      for k, v in pairs(known) do all[k] = v end
      local bad = {}
      for _, f in ipairs(F) do
         local ok = true
         for _, k in ipairs(VARS) do
            if contains(f, k) and not all[k] then ok = false end
         end
         if ok then
            local lhs, rhs = substitute(f, all):match('^(.-)=(.*)$')
            local d = cas.n(U.par(lhs) .. '-' .. U.par(rhs))
            if d and math.abs(d) > 1e-6 then table.insert(bad, f.text) end
         end
      end
      if #bad > 0 then
         R:note('Given values are inconsistent with ' .. table.concat(bad, ', '), 'warn')
      end
      if #unknown == 0 then
         if #bad == 0 then
            R:note('All five values are consistent')
         end
         for _, k in ipairs(VARS) do R:result(k, known[k], { key = k }) end
         return
      end
   end

   if #unknown > 2 then
      R:note('Enter any three of s, u, v, a, t')
      return
   end

   local gv = {}
   for _, k in ipairs(order) do table.insert(gv, k .. ' = ' .. M(known[k])) end
   R:step('Given: ' .. table.concat(gv, ',  '))

   -- Unknown pair (p, q): solve p from the formula without q
   local p, q = unknown[1], unknown[2]
   -- prefer solving first the variable that appears linearly
   if q and not formula_lacking(q).lin[p] then
      p, q = q, p
   end

   local fp = q and formula_lacking(q) or nil
   if not q then
      -- single unknown: any linear formula containing it and only knowns
      for _, f in ipairs(F) do
         local ok = contains(f, p) and f.lin[p]
         for _, k in ipairs(VARS) do
            if k ~= p and contains(f, k) and not known[k] then ok = false end
         end
         if ok then fp = f break end
      end
      fp = fp or formula_lacking(VARS[1])
   end

   local sols, eq = solve_for(fp, p, known)
   R:step(M(fp.text) .. ' ' .. U.IMPL .. ' ' .. M(eq))

   -- reject negative time
   local valid = {}
   for _, s in ipairs(sols) do
      local x = cas.n(s)
      if p == 't' and x and x < -1e-12 then
         R:step('t = ' .. M(s) .. ' rejected (t ' .. U.GEQ .. ' 0)')
      else
         table.insert(valid, s)
      end
   end
   if #valid == 0 then
      R:note('No valid solution for ' .. p, 'error')
      return
   end

   for idx, ps in ipairs(valid) do
      local suffix = #valid > 1 and tostring(idx) or ''
      R:step(p .. ' ' .. U.eq(ps))
      R:result(p .. suffix, ps, { key = p .. suffix })
      if q then
         local k2 = {}
         for k, v in pairs(known) do k2[k] = v end
         k2[p] = ps
         -- linear formula containing q with everything else known
         local fq
         for _, f in ipairs(F) do
            local ok = contains(f, q) and f.lin[q]
            for _, k in ipairs(VARS) do
               if k ~= q and contains(f, k) and not k2[k] then ok = false end
            end
            if ok then fq = f break end
         end
         fq = fq or formula_lacking(p)
         local qs, qeq = solve_for(fq, q, k2)
         local qv = qs[1]
         if qv then
            R:step(M(fq.text) .. ' ' .. U.IMPL .. ' ' .. M(qeq) .. ' ' .. U.IMPL .. ' ' .. q .. ' ' .. U.eq(qv))
            R:result(q .. suffix, qv, { key = q .. suffix })
         else
            R:note('Could not find ' .. q, 'error')
         end
      end
   end
   if #valid > 1 then
      R:note(#valid .. ' solutions: choose the one that fits the question')
   end
end

return S
