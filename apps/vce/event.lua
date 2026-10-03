-- Parser for probability events typed by the user, e.g.
--   45<X<55    X>=3    X≠2    k<X    X>2 | X>=1   P(X<5)
local sym = require 'ti.sym'
local cas = require 'apps.vce.cas'

local ev = {}

local LEQ, GEQ, NEQ = sym.LEQ, sym.GEQ, sym.NEQ

-- Relational operators (multi-byte first)
local OPS = { LEQ, GEQ, NEQ, '<', '>', '=' }

local function trim(s)
   return (s or ''):match('^%s*(.-)%s*$')
end

function ev.normalize(s)
   s = trim(s)
   s = s:gsub('<=', LEQ):gsub('>=', GEQ):gsub('!=', NEQ):gsub('/=', NEQ):gsub('==', '=')
   -- strip P( ... )
   local inner = s:match('^[Pp]r?%s*%((.*)%)$')
   if inner then s = trim(inner) end
   return s
end

-- Split at top-level relational operators
---@return string[] parts, string[] ops
function ev.split(s)
   local parts, ops = {}, {}
   local depth, start, i, n = 0, 1, 1, #s
   while i <= n do
      local c = s:sub(i, i)
      if c == '(' or c == '[' or c == '{' then
         depth = depth + 1
         i = i + 1
      elseif c == ')' or c == ']' or c == '}' then
         depth = depth - 1
         i = i + 1
      else
         local matched = nil
         if depth == 0 then
            for _, op in ipairs(OPS) do
               if s:sub(i, i + #op - 1) == op then
                  matched = op
                  break
               end
            end
         end
         if matched then
            table.insert(parts, trim(s:sub(start, i - 1)))
            table.insert(ops, matched)
            i = i + #matched
            start = i
         else
            i = i + 1
         end
      end
   end
   table.insert(parts, trim(s:sub(start)))
   return parts, ops
end

-- Default random variable names (case-insensitive)
ev.default_rv = { 'x', 'z', 'y', 'w', 't', 's', 'xbar', 'u', 'v' }

local function is_ident(s)
   return s:match('^%a[%w_]*$') ~= nil
end

local function find_rv(parts, rvnames)
   rvnames = rvnames or ev.default_rv
   for _, name in ipairs(rvnames) do
      for idx, p in ipairs(parts) do
         if p:lower() == name then
            return idx
         end
      end
   end
   -- Fallback: a single upper case identifier
   for idx, p in ipairs(parts) do
      if p:match('^%u[%w_]*$') then
         return idx
      end
   end
   return nil
end

-- Apply relation 'left op right' where the rv is on side `rv_side` (1 = left)
local function apply(e, op, other, rv_side)
   if op == '=' then
      e.eq = other
      return true
   elseif op == NEQ then
      e.ne = other
      return true
   end
   local less = (op == '<' or op == LEQ)
   local inc = (op == LEQ or op == GEQ)
   -- normalise to 'rv < other' (upper bound) or 'rv > other' (lower bound)
   local upper
   if rv_side == 1 then
      upper = less
   else
      upper = not less
   end
   if upper then
      e.hi, e.hi_inc = other, inc
   else
      e.lo, e.lo_inc = other, inc
   end
   return true
end

local function parse_simple(s, rvnames)
   local parts, ops = ev.split(s)
   if #ops == 0 then
      return nil, 'Event needs <, >, ' .. LEQ .. ', ' .. GEQ .. ' or ='
   end
   if #ops > 2 then
      return nil, 'Too many relations in event'
   end

   local rv_idx = find_rv(parts, rvnames)
   if not rv_idx then
      return nil, 'Cannot find the random variable (use X)'
   end

   local e = { rv = parts[rv_idx], text = s }
   if #ops == 1 then
      local other = rv_idx == 1 and parts[2] or parts[1]
      if other == '' then return nil, 'Missing value in event' end
      apply(e, ops[1], other, rv_idx == 1 and 1 or 2)
   else
      if rv_idx ~= 2 then
         return nil, 'Use the form a < X < b'
      end
      if parts[1] == '' or parts[3] == '' then return nil, 'Missing value in event' end
      apply(e, ops[1], parts[1], 2)
      apply(e, ops[2], parts[3], 1)
   end
   return e
end

-- Parse an event; returns table or nil, error message.
--   { rv, lo, lo_inc, hi, hi_inc, eq, ne, given = <event>|nil, text }
---@param s string
---@param rvnames? string[]
function ev.parse(s, rvnames)
   if not s or trim(s) == '' then return nil, 'Empty event' end
   s = ev.normalize(s)
   local parts = cas.split_top(s, '|')
   if #parts > 2 then
      return nil, 'Only one condition | allowed'
   end
   local e, err = parse_simple(parts[1], rvnames)
   if not e then return nil, err end
   if parts[2] then
      local g, gerr = parse_simple(parts[2], rvnames)
      if not g then return nil, gerr end
      e.given = g
   end
   e.text = s
   return e
end

-- Parse a probability field with optional relation prefix:
--   '0.95'  -> { rel = '=', value = '0.95' }
--   '>=0.95'-> { rel = GEQ, value = '0.95' }
function ev.parse_prob(s)
   s = trim(s)
   if s == '' then return nil end
   s = s:gsub('<=', LEQ):gsub('>=', GEQ)
   for _, op in ipairs({ LEQ, GEQ, '<', '>', '=' }) do
      if s:sub(1, #op) == op then
         return { rel = op, value = trim(s:sub(#op + 1)) }
      end
   end
   return { rel = '=', value = s }
end

-- Describe an event in text form, e.g. 'P(45 < X < 55)'
function ev.describe(e, rvname)
   local rv = rvname or e.rv or 'X'
   local function one(x)
      if x.eq then return rv .. ' = ' .. x.eq end
      if x.ne then return rv .. ' ' .. NEQ .. ' ' .. x.ne end
      if x.lo and not x.hi then
         return rv .. (x.lo_inc and (' ' .. GEQ .. ' ') or ' > ') .. x.lo
      end
      local s = ''
      if x.lo then s = x.lo .. (x.lo_inc and (' ' .. LEQ .. ' ') or ' < ') end
      s = s .. rv
      if x.hi then s = s .. (x.hi_inc and (' ' .. LEQ .. ' ') or ' < ') .. x.hi end
      return s
   end
   local s = one(e)
   if e.given then
      s = s .. ' | ' .. one(e.given)
   end
   return 'P(' .. s .. ')'
end

-- Interval of an event with numeric bounds (Lua numbers):
--   returns lo, lo_inc, hi, hi_inc (lo/hi may be +-math.huge)
-- `num` converts bound strings to numbers.
function ev.interval(e, num)
   if e.eq then
      local v = num(e.eq)
      return v, true, v, true
   end
   local lo, hi = -math.huge, math.huge
   local lo_inc, hi_inc = false, false
   if e.lo then lo, lo_inc = num(e.lo), e.lo_inc end
   if e.hi then hi, hi_inc = num(e.hi), e.hi_inc end
   return lo, lo_inc, hi, hi_inc
end

-- Intersect two numeric intervals
function ev.intersect(a, b)
   local lo, lo_inc, hi, hi_inc = a[1], a[2], a[3], a[4]
   if b[1] > lo or (b[1] == lo and not b[2]) then lo, lo_inc = b[1], b[2] end
   if b[3] < hi or (b[3] == hi and not b[4]) then hi, hi_inc = b[3], b[4] end
   return { lo, lo_inc, hi, hi_inc }
end

-- Integer range [a, b] of an interval for a discrete random variable
function ev.int_range(lo, lo_inc, hi, hi_inc)
   local a, b
   if lo == -math.huge then
      a = -math.huge
   else
      a = math.ceil(lo)
      if a == lo and not lo_inc then a = a + 1 end
   end
   if hi == math.huge then
      b = math.huge
   else
      b = math.floor(hi)
      if b == hi and not hi_inc then b = b - 1 end
   end
   return a, b
end

return ev
