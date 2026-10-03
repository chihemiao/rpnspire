-- Number formatting helpers for the VCE toolkit
local sym = require 'ti.sym'

local fmt = {}

local NEG = sym.NEGATE

-- Decimal places used for approximate values (changed via settings)
fmt.dp = 4

local function trim_zeros(s)
   if s:find('%.') then
      s = s:gsub('0+$', ''):gsub('%.$', '')
   end
   return s
end

-- Round a Lua number to `dp` decimal places and return a CAS string.
-- Very large or very small values use scientific notation (a*10^b).
---@param x number
---@param dp? number
---@return string
function fmt.round(x, dp)
   dp = dp or fmt.dp
   if x ~= x then return 'undef' end
   if x == math.huge then return sym.INFTY end
   if x == -math.huge then return NEG .. sym.INFTY end

   local ax = math.abs(x)
   local s
   if ax ~= 0 and (ax >= 1e10 or ax < 0.5 * 10 ^ (-dp)) then
      local m, e = string.format('%.' .. math.max(dp - 1, 1) .. 'e', ax):match('^([%d%.]+)e([-+]%d+)$')
      local ev = tonumber(e)
      s = trim_zeros(m) .. '*10^(' .. (ev < 0 and NEG or '') .. tostring(math.abs(ev)) .. ')'
   else
      s = trim_zeros(string.format('%.' .. dp .. 'f', ax))
   end
   if x < 0 and s ~= '0' then
      s = NEG .. s
   end
   return s
end

-- Round all decimal literals in a CAS expression string to `dp` places.
-- Integers and identifiers (q9t, f11, ...) are left untouched.
---@param s string
---@param dp? number
---@return string
function fmt.round_expr(s, dp)
   if not s then return s end
   dp = dp or fmt.dp
   local out = {}
   local i, n = 1, #s
   while i <= n do
      local c = s:sub(i, i)
      local prev = i > 1 and s:sub(i - 1, i - 1) or ''
      local starts_num = c:match('%d') or (c == '.' and s:sub(i + 1, i + 1):match('%d'))
      if starts_num and not prev:match('[%w_%.]') then
         local _, j = s:find('^%d*%.?%d*', i)
         local lit = s:sub(i, j)
         local is_dec = lit:find('%.') ~= nil
         -- Optional exponent: EE [-|NEG|+] digits
         local k = j + 1
         if s:sub(k, k + #sym.EE - 1) == sym.EE then
            local p = k + #sym.EE
            local sign = ''
            if s:sub(p, p + #NEG - 1) == NEG then
               sign = '-'
               p = p + #NEG
            elseif s:sub(p, p) == '-' or s:sub(p, p) == '+' then
               sign = s:sub(p, p)
               p = p + 1
            end
            local _, q = s:find('^%d+', p)
            if q then
               lit = lit .. 'e' .. sign .. s:sub(p, q)
               j = q
               is_dec = true
            end
         end
         if is_dec and tonumber(lit) then
            local r = fmt.round(tonumber(lit), dp)
            if r:find('%*') then r = '(' .. r .. ')' end
            table.insert(out, r)
         else
            table.insert(out, s:sub(i, j))
         end
         i = j + 1
      else
         table.insert(out, c)
         i = i + 1
      end
   end
   return table.concat(out)
end

-- True if expression string contains a decimal literal (already approximate)
function fmt.has_decimal(s)
   if not s then return false end
   local i, n = 1, #s
   while i <= n do
      local c = s:sub(i, i)
      local prev = i > 1 and s:sub(i - 1, i - 1) or ''
      if c == '.' and s:sub(i + 1, i + 1):match('%d') and not prev:match('[%a_]') then
         return true
      end
      if s:sub(i, i + #sym.EE - 1) == sym.EE then
         return true
      end
      i = i + 1
   end
   return false
end

-- Plain text version of a CAS string for clipboard / summaries
function fmt.plain(s)
   if not s then return '' end
   local cas = require 'apps.vce.cas'
   local out = {}
   cas.scan(s, function(kind, text)
      if kind == 'id' then
         text = cas.display_name(text)
      end
      table.insert(out, text)
   end)
   return table.concat(out)
end

return fmt
