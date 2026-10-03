-- Discrete random variable given by a probability table
local cas = require 'apps.vce.cas'
local ev = require 'apps.vce.event'
local U = require 'apps.vce.solvers.util'

local M = U.M

local S = {
   id = 'discrete',
   title = 'Discrete random variable',
   short = 'Discrete RV',
   group = 'Probability',
   desc = 'Table x, P(X=x): unknown k, E(X), Var(X), P(event)',
   fields = {
      { id = 'x', label = 'x', hint = 'values: 0,1,2,3' },
      { id = 'px', label = 'P(X=x)', hint = 'probs: 0.1,k,2k,0.3' },
      { id = 'mean', label = 'E(X)', hint = 'if given (2nd unknown)' },
      { id = 'event', label = 'Event', hint = 'X' .. U.GEQ .. '2   X<3|X>0' },
   },
   example = { x = '0,1,2,3', px = '0.1,k,2k,0.3' },
}

local function join(items, sep)
   return table.concat(items, sep or '+')
end

function S.solve(I, R)
   if not (I.x and I.px) then
      R:note('Enter the values x and their probabilities')
      return
   end
   local map = U.locals_map()
   local xs = U.read_list(I.x)
   local ps_src = cas.input(I.px, map)
   if ps_src:sub(1, 1) ~= '{' then ps_src = '{' .. ps_src .. '}' end
   local praw = cas.list(ps_src)
   if #xs ~= #praw then
      R:note('Need the same number of x values (' .. #xs .. ') and probabilities (' .. #praw .. ')', 'error')
      return
   end

   local xnum = {}
   for i, x in ipairs(xs) do
      xnum[i] = cas.n(x)
      if not xnum[i] then
         R:note('x values must be numbers', 'error')
         return
      end
   end

   -- Unknowns --------------------------------------------------------------
   local unknowns = U.unknowns(ps_src)
   local ps = praw
   if #unknowns > 0 then
      local sum_eq = join(praw) .. '=1'
      R:step(U.SUM .. ' P(X=x) = 1: ' .. M(sum_eq))
      local assign
      if #unknowns == 1 then
         local u = unknowns[1]
         local sols = cas.solve(sum_eq, u)
         if not sols or #sols == 0 then
            local v = cas.nsolve(sum_eq, u, 0, 1)
            sols = v and { v } or {}
         end
         -- keep solutions giving valid probabilities
         local valid = {}
         for _, s in ipairs(sols) do
            local ok = true
            for _, pr in ipairs(praw) do
               local v = cas.n(cas.with(pr, { { u, s } }))
               if not v or v < -1e-12 or v > 1 + 1e-12 then ok = false end
            end
            if ok then table.insert(valid, s) end
         end
         if #valid == 0 then
            R:note('No value of ' .. cas.display_name(u) .. ' gives valid probabilities', 'error')
            return
         end
         if #valid < #sols then
            R:step('Reject values giving probabilities outside [0, 1]')
         end
         assign = { { u, valid[1] } }
         R:step(U.IMPL .. ' ' .. cas.display_name(u) .. ' ' .. U.eq(valid[1]))
         R:result(cas.display_name(u), valid[1], { key = 'k' })
      elseif #unknowns == 2 and I.mean then
         local mean = U.read(I.mean)
         local terms = {}
         for i, pr in ipairs(praw) do
            table.insert(terms, U.par(xs[i]) .. '*' .. U.par(pr))
         end
         local mean_eq = join(terms) .. '=' .. mean.val
         R:step('E(X) = ' .. U.SUM .. ' x' .. '\194\183' .. 'P(X=x): ' .. M(mean_eq))
         local u1, u2 = unknowns[1], unknowns[2]
         local res = cas.eval('solve(' .. sum_eq .. ' and ' .. mean_eq .. ',{' .. u1 .. ',' .. u2 .. '})')
         local s1 = res and cas.solutions(res, u1)
         local s2 = res and cas.solutions(res, u2)
         if not (s1 and s2 and s1[1] and s2[1]) then
            R:note('Could not solve for the two unknowns', 'error')
            return
         end
         assign = { { u1, s1[1] }, { u2, s2[1] } }
         R:step(U.IMPL .. ' ' .. cas.display_name(u1) .. ' ' .. U.eq(s1[1]) .. ',  '
                .. cas.display_name(u2) .. ' ' .. U.eq(s2[1]))
         R:result(cas.display_name(u1), s1[1], { key = 'k' })
         R:result(cas.display_name(u2), s2[1], { key = 'k2' })
      else
         R:note('Too many unknowns: give E(X) for a second unknown', 'error')
         return
      end
      ps = {}
      for i, pr in ipairs(praw) do
         ps[i] = U.simp(cas.with(pr, assign))
      end
   else
      ps = cas.list(U.simp(ps_src)) or praw
   end

   local pnum = {}
   local total = 0
   for i, pr in ipairs(ps) do
      pnum[i] = cas.n(pr)
      if not pnum[i] then
         R:note('Probabilities must be numbers', 'error')
         return
      end
      if pnum[i] < -1e-12 or pnum[i] > 1 + 1e-12 then
         R:note('P(X=' .. U.txt(xs[i]) .. ') is not in [0, 1]', 'error')
      end
      total = total + pnum[i]
   end
   if math.abs(total - 1) > 1e-9 then
      R:note('Probabilities sum to ' .. string.format('%.6g', total) .. ', not 1', 'error')
   end

   R:result('P(X=x)', cas.mklist(ps), { key = 'probs' })

   -- Mean and variance ---------------------------------------------------------
   local xl, pl = cas.mklist(xs), cas.mklist(ps)
   local terms, terms2 = {}, {}
   for i = 1, #xs do
      table.insert(terms, U.par(xs[i]) .. '*' .. U.par(ps[i]))
      table.insert(terms2, U.par(xs[i]) .. '^2*' .. U.par(ps[i]))
   end
   local ex = U.simp('sum(' .. xl .. '*' .. pl .. ')')
   local ex2 = U.simp('sum(' .. xl .. '^2*' .. pl .. ')')
   local var = U.simp(U.par(ex2) .. '-' .. U.par(ex) .. '^2')
   local sd = U.simp(U.ROOT .. '(' .. var .. ')')
   R:step('E(X) = ' .. U.SUM .. ' x' .. '\194\183' .. 'p(x) = ' .. M(join(terms)) .. ' ' .. U.eq(ex))
   R:step('E(X' .. U.SQ .. ') = ' .. M(join(terms2)) .. ' ' .. U.eq(ex2))
   R:step('Var(X) = E(X' .. U.SQ .. ') - [E(X)]' .. U.SQ .. ' = ' .. M(U.par(ex2) .. '-' .. U.par(ex) .. '^2') .. ' ' .. U.eq(var))
   R:result('E(X)', ex, { key = 'mean' })
   R:result('E(X' .. U.SQ .. ')', ex2, { key = 'ex2' })
   R:result('Var(X)', var, { key = 'var' })
   R:result('SD(X)', sd, { key = 'sd' })

   -- Median and mode (x sorted as given)
   local cum, median = 0, nil
   local order = {}
   for i = 1, #xs do order[i] = i end
   table.sort(order, function(a, b) return xnum[a] < xnum[b] end)
   for _, i in ipairs(order) do
      cum = cum + pnum[i]
      if not median and cum >= 0.5 - 1e-12 then median = xs[i] end
   end
   local mode, best = nil, -1
   for i = 1, #xs do
      if pnum[i] > best + 1e-12 then mode, best = xs[i], pnum[i] end
   end
   if median then R:result('median', median, { key = 'median' }) end
   if mode then R:result('mode', mode, { key = 'mode' }) end

   -- Event --------------------------------------------------------------------
   if not I.event or U.trim(I.event) == '' then return end
   local e, err = ev.parse(I.event)
   if not e then
      R:note(err, 'error')
      return
   end
   local rv = e.rv:upper()
   local num = function(s) return U.read(s).num end

   local function in_event(x, ee)
      if ee.eq then return math.abs(x - num(ee.eq)) < 1e-12 end
      if ee.ne then return math.abs(x - num(ee.ne)) >= 1e-12 end
      local lo, lo_inc, hi, hi_inc = ev.interval(ee, num)
      local ok_lo = x > lo or (lo_inc and x == lo)
      local ok_hi = x < hi or (hi_inc and x == hi)
      return ok_lo and ok_hi
   end

   local function prob(pred, label)
      local parts, sel = {}, {}
      for _, i in ipairs(order) do
         if pred(xnum[i]) then
            table.insert(parts, U.par(ps[i]))
            table.insert(sel, 'P(' .. rv .. '=' .. U.txt(xs[i]) .. ')')
         end
      end
      if #parts == 0 then
         R:step(label .. ' = 0')
         return '0'
      end
      local v = U.simp(join(parts))
      R:step(label .. ' = ' .. table.concat(sel, '+') .. ' = ' .. M(join(parts)) .. ' ' .. U.eq(v))
      return v
   end

   if e.given then
      local pab = prob(function(x) return in_event(x, e) and in_event(x, e.given) end, 'P(' .. e.text:gsub('|.*', '') .. ' and ' .. e.given.text .. ')')
      local pb = prob(function(x) return in_event(x, e.given) end, ev.describe(e.given, rv))
      local res = U.simp(U.par(pab) .. '/' .. U.par(pb))
      R:step(ev.describe(e, rv) .. ' = ' .. M(U.par(pab) .. '/' .. U.par(pb)) .. ' ' .. U.eq(res))
      R:result(ev.describe(e, rv), res, { key = 'prob' })
      return
   end
   local res = prob(function(x) return in_event(x, e) end, ev.describe(e, rv))
   R:result(ev.describe(e, rv), res, { key = 'prob' })
end

return S
