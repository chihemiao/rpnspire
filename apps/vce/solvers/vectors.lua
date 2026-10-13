-- Angle between two vectors, or angle ABC from three points. Vectors may
-- contain one letter (m): with a given angle it is found, otherwise the
-- answers are in terms of it.
local cas = require 'apps.vce.cas'
local sym = require 'ti.sym'
local U = require 'apps.vce.solvers.util'

local M = U.M
local DEG = sym.DEGREE
local THETA = sym.theta
local DOT = sym.CDOT
local MAP = U.locals_map()

-- Raw parts of a vector typed as 2i-j+3k, (2,-1,3), [2,-1,3], <2,-1,3>,
-- [2;-1;3] or [[2][-1][3]]; nil when it cannot be read
local CLOSE = { ['('] = ')', ['['] = ']', ['<'] = '>', ['{'] = '}' }

-- True when the first bracket of s closes at its last character
local function enclosed(s)
   local close = CLOSE[s:sub(1, 1)]
   if not close or s:sub(-1) ~= close then return false end
   if close == '>' then return true end
   local depth = 0
   for i = 1, #s do
      local c = s:sub(i, i)
      if c == '(' or c == '[' or c == '{' then
         depth = depth + 1
      elseif c == ')' or c == ']' or c == '}' then
         depth = depth - 1
         if depth == 0 and i < #s then return false end
      end
   end
   return true
end

-- 2i - j + 3k -> { '2', '-1', '3' } (two parts when there is no k)
local function split_ijk(s)
   local terms, depth, start = {}, 0, 1
   for i = 1, #s do
      local c = s:sub(i, i)
      if c == '(' or c == '[' or c == '{' then
         depth = depth + 1
      elseif c == ')' or c == ']' or c == '}' then
         depth = depth - 1
      elseif depth == 0 and (c == '+' or c == '-') and i > start then
         -- a sign after *, / or ^ belongs to the number that follows
         local prev = s:sub(start, i - 1):match('(%S)%s*$')
         if prev and not prev:match('[%*/%^]') then
            table.insert(terms, s:sub(start, i - 1))
            start = i
         end
      end
   end
   table.insert(terms, s:sub(start))
   local INDEX = { i = 1, j = 2, k = 3 }
   local parts, any = { '0', '0', '0' }, false
   for _, t in ipairs(terms) do
      t = t:gsub('%s+', '')
      if t ~= '' then
         local n = INDEX[t:sub(-1)]
         if not n then return nil end
         local c = t:sub(1, -2):gsub('%*$', ''):gsub('^%+', '')
         if c == '' then c = '1' elseif c == '-' then c = '-1' end
         parts[n] = parts[n] == '0' and c or (parts[n] .. '+(' .. c .. ')')
         if n == 3 then any = 3 elseif not any then any = true end
      end
   end
   if not any then return nil end
   if any ~= 3 then parts[3] = nil end
   return parts
end

local function split_vector(text)
   local s = U.trim(text):gsub(sym.NEGATE, '-')
   if s == '' then return nil end
   local inner = enclosed(s) and s:sub(2, -2) or s
   if inner:sub(1, 1) == '[' and inner:sub(-1) == ']' then
      inner = inner:gsub('%]%s*,?%s*%[', ','):sub(2, -2)
   end
   local parts = cas.split_top(inner, ',')
   if #parts == 1 then parts = cas.split_top(inner, ';') end
   if #parts >= 2 then
      if #parts > 3 then return nil end
      return parts
   end
   return split_ijk(s)
end

-- Components (CAS strings) of a typed vector; nil and a note when it
-- cannot be read
local function read_vector(R, text, name)
   local parts = split_vector(text or '')
   local out = {}
   for k, p in ipairs(parts or {}) do
      local e = cas.input(p, MAP, false, true)
      local v = e and cas.eval(e)
      if not v then parts = nil break end
      out[k] = v
   end
   if not parts then
      R:note('Write ' .. name .. ' as 2i-j+3k or (2,-1,3)', 'error')
      return nil
   end
   return out
end

-- [2,-1,3] for the working
local function vec(c)
   return M('[' .. table.concat(c, ',') .. ']')
end

-- Letters (q9m) in a list of components
local function letters(...)
   local seen, out = {}, {}
   for _, list in ipairs({ ... }) do
      for _, c in ipairs(list) do
         for _, u in ipairs(U.unknowns(c)) do
            if not seen[u] then
               seen[u] = true
               table.insert(out, u)
            end
         end
      end
   end
   return out
end

-- Any letter (other than the unit vectors i, j, k) in the inputs?
local function has_letter(I)
   local keys = (I.mode == 'pts') and { 'pa', 'pb', 'pc' } or { 'a', 'b' }
   for _, key in ipairs(keys) do
      local parts = I[key] and split_vector(I[key])
      for _, p in ipairs(parts or {}) do
         local e = cas.input(p, MAP, false, true)
         if e and #U.unknowns(e) > 0 then return true end
      end
   end
   return false
end

local function vectors_shown(I) return I.mode ~= 'pts' end
local function points_shown(I) return I.mode == 'pts' end

local S = {
   id = 'vectors',
   title = 'Angle between vectors',
   short = 'Vector angle',
   group = 'Vectors',
   desc = 'Two vectors or three points (angle ABC); acute angle option; find a letter from the angle',
   fields = {
      { id = 'mode', label = 'Use', kind = 'choice', options = {
           { 'vec', 'two vectors a, b' }, { 'pts', 'three points A, B, C' } } },
      { id = 'a', label = 'a', hint = 'e.g. 2i-j+3k   (2,-1,3)', show = vectors_shown },
      { id = 'b', label = 'b', hint = 'e.g. i+mj-k   (1,m,-1)', show = vectors_shown },
      { id = 'pa', label = 'A', hint = 'point, e.g. (1,2,3)', show = points_shown },
      { id = 'pb', label = 'B', hint = 'the vertex: angle ABC is at B', show = points_shown },
      { id = 'pc', label = 'C', hint = 'point, e.g. (0,m,1)', show = points_shown },
      -- acute: the angle between lines (180 - theta when theta is obtuse)
      { id = 'range', label = 'Angle', kind = 'choice', options = {
           { 'any', '0 to 180' .. DEG .. ' (vectors)' }, { 'acute', 'acute (lines)' } } },
      { id = 'unit', label = 'Unit', kind = 'choice', options = { { 'deg', 'degrees' }, { 'rad', 'radians' } } },
      { id = 'given', label = 'given ' .. THETA, hint = 'angle, finds the letter: 60   pi/3', show = has_letter },
   },
   example = { a = 'i+2j-2k', b = '2i-j+2k' },
}

-- Angle in the chosen unit from radians (exact)
local function in_unit(rad, unit)
   if unit == 'rad' then return rad end
   return U.simp(U.par(rad) .. '*180/' .. sym.pi)
end

function S.solve(I, R)
   local unit = I.unit or 'deg'
   local acute = I.range == 'acute'
   local pts = I.mode == 'pts'
   local u, v, nu, nv
   if pts then
      if not (I.pa and I.pb and I.pc) or U.trim(I.pa) == '' or U.trim(I.pb) == '' or U.trim(I.pc) == '' then
         R:note('Enter the points A, B and C (angle ABC is at B)')
         return
      end
      local A, B, C = read_vector(R, I.pa, 'A'), read_vector(R, I.pb, 'B'), read_vector(R, I.pc, 'C')
      if not (A and B and C) then return end
      local dim = math.max(#A, #B, #C)
      for _, P in ipairs({ A, B, C }) do
         for k = #P + 1, dim do P[k] = '0' end
      end
      u, v = {}, {}
      for k = 1, dim do
         u[k] = U.simp(U.par(A[k]) .. '-' .. U.par(B[k]))
         v[k] = U.simp(U.par(C[k]) .. '-' .. U.par(B[k]))
      end
      nu, nv = 'BA', 'BC'
      R:step('Angle ABC is the angle between ' .. nu .. ' and ' .. nv)
      R:step(nu .. ' = A - B = ' .. vec(A) .. ' - ' .. vec(B) .. ' = ' .. vec(u))
      R:step(nv .. ' = C - B = ' .. vec(C) .. ' - ' .. vec(B) .. ' = ' .. vec(v))
   else
      if not (I.a and I.b) or U.trim(I.a) == '' or U.trim(I.b) == '' then
         R:note('Enter the vectors a and b')
         return
      end
      u, v = read_vector(R, I.a, 'a'), read_vector(R, I.b, 'b')
      if not (u and v) then return end
      for k = #u + 1, #v do u[k] = '0' end
      for k = #v + 1, #u do v[k] = '0' end
      nu, nv = 'a', 'b'
      R:step('a = ' .. vec(u) .. ',  b = ' .. vec(v))
   end
   local name = pts and 'angle ABC' or THETA

   -- a.b, |a|, |b|, cos(theta)
   local prods, terms, sqa, sqb = {}, {}, {}, {}
   for k = 1, #u do
      table.insert(prods, U.par(u[k]) .. '*' .. U.par(v[k]))
      table.insert(terms, '(' .. M(u[k]) .. ')(' .. M(v[k]) .. ')')
      table.insert(sqa, U.par(u[k]) .. '^2')
      table.insert(sqb, U.par(v[k]) .. '^2')
   end
   local dot = U.simp(table.concat(prods, '+'))
   R:step(nu .. DOT .. nv .. ' = ' .. table.concat(terms, ' + ') .. ' = ' .. M(dot))
   R:result(nu .. DOT .. nv, dot, { key = 'dot' })
   local a2, b2 = U.simp(table.concat(sqa, '+')), U.simp(table.concat(sqb, '+'))
   local ma, mb = U.simp(sym.ROOT .. '(' .. a2 .. ')'), U.simp(sym.ROOT .. '(' .. b2 .. ')')
   R:step('|' .. nu .. '| = ' .. M(sym.ROOT .. '(' .. table.concat(sqa, '+') .. ')') .. ' = ' .. M(ma))
   R:step('|' .. nv .. '| = ' .. M(sym.ROOT .. '(' .. table.concat(sqb, '+') .. ')') .. ' = ' .. M(mb))
   R:result('|' .. nu .. '|', ma, { key = 'mag_a' })
   R:result('|' .. nv .. '|', mb, { key = 'mag_b' })
   for _, z in ipairs({ { nu, a2 }, { nv, b2 } }) do
      if cas.n(z[2]) == 0 then
         R:note(z[1] .. ' is the zero vector: there is no angle', 'warn')
         return
      end
   end
   local cosf = U.simp(U.par(dot) .. '/(' .. U.par(ma) .. '*' .. U.par(mb) .. ')')
   R:step('cos ' .. THETA .. ' = ' .. nu .. DOT .. nv .. ' / (|' .. nu .. '| |' .. nv .. '|) = '
          .. M(U.par(dot) .. '/(' .. U.par(ma) .. '*' .. U.par(mb) .. ')') .. ' ' .. U.eq(cosf))
   R:result('cos ' .. THETA, cosf, { key = 'cos' })

   -- a letter: find it from a given angle, or answer in terms of it
   local free = letters(u, v)
   local given = I.given and U.trim(I.given) ~= '' and I.given or nil
   if #free > 0 then
      local names = {}
      for _, f in ipairs(free) do table.insert(names, cas.display_name(f)) end
      if not given then
         R:note('Answers in terms of ' .. table.concat(names, ', ') .. ': type the angle in "given ' .. THETA
                .. '" to find ' .. names[1])
      elseif #free > 1 then
         R:note('Only one letter can be found from one angle', 'warn')
         return
      else
         return S.find_letter(R, free[1], given, unit, acute, { dot = dot, a2 = a2, b2 = b2, cos = cosf,
                                                               nu = nu, nv = nv })
      end
   end

   -- the angle
   local theta = U.simp('arccos(' .. cosf .. ')')
   local c = cas.n(cosf)
   R:tag('theta')
   R:section('Angle')
   if c and math.abs(c) < 1e-9 then
      R:step(nu .. DOT .. nv .. ' = 0, so ' .. nu .. ' and ' .. nv .. ' are perpendicular')
   elseif c and math.abs(math.abs(c) - 1) < 1e-9 then
      R:step('|cos ' .. THETA .. '| = 1, so ' .. nu .. ' and ' .. nv .. ' are parallel')
   end
   R:step(THETA .. ' = ' .. M('cos' .. sym.POWN1 .. '(' .. cosf .. ')') .. ' ' .. U.eq(theta) .. ' rad'
          .. ' ' .. U.eq(in_unit(theta, 'deg')) .. DEG)
   R:result(name .. (unit == 'deg' and ' (degrees)' or ' (radians)'), in_unit(theta, unit), { key = 'theta' })
   if acute then
      if c and c < -1e-9 then
         local sharp = U.simp('arccos(' .. U.simp('abs(' .. cosf .. ')') .. ')')
         R:tag('acute', { 'theta' })
         R:step(THETA .. ' > 90' .. DEG .. ', so the acute angle (between the lines) is 180' .. DEG .. ' - ' .. THETA
                .. ' ' .. U.eq(in_unit(sharp, 'deg')) .. DEG)
         R:result('acute angle' .. (unit == 'deg' and ' (degrees)' or ' (radians)'), in_unit(sharp, unit),
                  { key = 'acute' })
      else
         R:step(THETA .. ' ' .. U.LEQ .. ' 90' .. DEG .. ': already the acute angle')
      end
   end
   R:tag(nil)
end

-- Solve for the letter m from a given angle:
--   cos(theta) = a.b/(|a||b|)  =>  (a.b)^2 = |a|^2 |b|^2 cos^2(theta)
-- then keep the values that give the angle itself (a.b has the sign of
-- cos(theta)); for the acute angle between lines both signs are fine.
function S.find_letter(R, m, given, unit, acute, V)
   local mname = cas.display_name(m)
   local g = U.trim(given):gsub(DEG, '')
   g = g:gsub('^' .. THETA .. '%s*=%s*', ''):gsub('^[tT]heta%s*=%s*', '')
   local gv = U.read(g, MAP)
   local rad = unit == 'rad' and gv.val or U.simp(U.par(gv.val) .. '*' .. sym.pi .. '/180')
   local n = cas.n(rad)
   local top = acute and math.pi / 2 or math.pi
   if not n or n < -1e-12 or n > top + 1e-12 then
      R:note('The angle must be from 0 to ' .. (acute and '90' or '180') .. DEG, 'warn')
      return
   end
   local cg = U.simp('cos(' .. rad .. ')')
   local cn = cas.n(cg)
   R:tag('param_' .. mname)
   R:section('Find ' .. mname)
   local eq
   if math.abs(cn) < 1e-9 then
      R:step(THETA .. ' = 90' .. DEG .. ', so ' .. V.nu .. DOT .. V.nv .. ' = 0')
      eq = V.dot .. '=0'
   else
      R:step('cos ' .. THETA .. ' = ' .. V.nu .. DOT .. V.nv .. ' / (|' .. V.nu .. '| |' .. V.nv .. '|), so ('
             .. V.nu .. DOT .. V.nv .. ')' .. U.SQ .. ' = |' .. V.nu .. '|' .. U.SQ .. ' |' .. V.nv .. '|' .. U.SQ
             .. ' cos' .. U.SQ .. THETA)
      eq = U.par(V.dot) .. '^2=' .. U.par(V.a2) .. '*' .. U.par(V.b2) .. '*' .. U.par(cg) .. '^2'
   end
   R:step(M(eq))
   local sols = cas.solve(eq, m)
   if not sols then
      R:note('Could not solve for ' .. mname, 'warn')
      return
   end
   local keep, shown = {}, {}
   for _, s in ipairs(sols) do
      if not s:find('@', 1, true) then
         table.insert(shown, M(m .. '=' .. s))
         local c = cas.n(cas.with(V.cos, { { m, s } }))
         local ok = c and (acute and math.abs(math.abs(c) - math.abs(cn)) < 1e-6 or math.abs(c - cn) < 1e-6)
         if ok then table.insert(keep, s) else table.insert(keep, { reject = s, c = c }) end
      end
   end
   R:step('Solve for ' .. mname .. ':  ' .. (#shown > 0 and table.concat(shown, ' or ') or 'no solution'))
   local found = 0
   for _, s in ipairs(keep) do
      if type(s) == 'table' and not s.c then
         R:step(M(m .. '=' .. s.reject) .. ' gives a zero vector: rejected')
      elseif type(s) == 'table' then
         local other = math.acos(math.max(-1, math.min(1, s.c))) * 180 / math.pi
         R:step(M(m .. '=' .. s.reject) .. ' gives ' .. THETA .. ' ' .. U.eq(cas.num(other)) .. DEG
                .. ', not ' .. M(gv.val) .. (unit == 'deg' and DEG or '') .. ': rejected')
      else
         found = found + 1
         R:result(mname, s, { key = 'param_' .. mname .. (found > 1 and tostring(found) or '') })
      end
   end
   if found == 0 then
      R:note('No value of ' .. mname .. ' gives this angle', 'warn')
   end
   R:tag(nil)
end

return S
