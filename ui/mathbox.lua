-- Pretty printer for TI infix expressions (2D layout like the CAS display).
--
--   local mb = require 'ui.mathbox'
--   local box = mb.layout('3/8*x^2', 10, gc)  -- gc: TI graphics context
--   mb.draw(box, gc, x, y)                     -- top-left corner
--
-- Boxes have w (width), h (height) and a (distance from the top to the math
-- axis, where fraction bars sit). Parsing uses rpnspire's lexer/expression
-- tree; unparsable input falls back to plain text.
local expr = require 'expressiontree'
local lexer = require 'ti.lexer'
local operators = require 'ti.operators'
local sym = require 'ti.sym'

local mb = {}

-- Display name hook for identifiers (set by the app, e.g. cas.display_name)
mb.rename = function(word) return word end

mb.MIN_SIZE = 7

local floor, max, min = math.floor, math.max, math.min

-- Measurement --------------------------------------------------------------------

local height_cache = {}

-- Font sizes available on the handheld
local SIZES = { 7, 9, 10, 11, 12, 16, 24 }

-- Largest available size <= s (at least 7)
function mb.snap(s)
   local best = SIZES[1]
   for _, v in ipairs(SIZES) do
      if v <= s then best = v end
   end
   return best
end

local function set_font(gc, size, style)
   gc:setFont('sansserif', style or 'r', mb.snap(size))
end

local function text_height(gc, size)
   local h = height_cache[size]
   if not h then
      set_font(gc, size)
      h = gc:getStringHeight('A')
      height_cache[size] = h
   end
   return h
end

local function text_width(gc, s, size, style)
   set_font(gc, size, style)
   return gc:getStringWidth(s)
end

local function small(size)
   return mb.snap(max(mb.MIN_SIZE, size - 3))
end

-- Primitive boxes ------------------------------------------------------------------

local function text_box(gc, s, size, style, pad)
   pad = pad or 0
   local h = text_height(gc, size)
   local w = text_width(gc, s, size, style) + 2 * pad
   return {
      w = w, h = h, a = floor(h / 2), text = s,
      draw = function(_, g, x, y)
         set_font(g, size, style)
         g:drawString(s, x + pad, y, 'top')
      end
   }
end

local function hbox(items)
   local a, d, w = 0, 0, 0
   for _, b in ipairs(items) do
      a = max(a, b.a)
      d = max(d, b.h - b.a)
      w = w + b.w
   end
   return {
      w = w, h = a + d, a = a, items = items,
      draw = function(_, g, x, y)
         local cx = x
         for _, b in ipairs(items) do
            b:draw(g, cx, y + a - b.a)
            cx = cx + b.w
         end
      end
   }
end

local function frac_box(num, den)
   local pad, gap = 2, 1
   local w = max(num.w, den.w) + 2 * pad
   local bar = num.h + gap
   return {
      w = w, h = num.h + 2 * gap + 1 + den.h, a = bar,
      draw = function(_, g, x, y)
         num:draw(g, x + floor((w - num.w) / 2), y)
         g:drawLine(x + 1, y + bar, x + w - 2, y + bar)
         den:draw(g, x + floor((w - den.w) / 2), y + bar + 1 + gap)
      end
   }
end

local function sup_box(base, exp, ht)
   local rise = floor(ht * 0.45)
   local up = max(0, exp.h - rise)
   local ey = rise - exp.h -- exponent top relative to base top
   return {
      w = base.w + exp.w + 1, h = base.h + up, a = base.a + up,
      draw = function(_, g, x, y)
         base:draw(g, x, y + up)
         exp:draw(g, x + base.w + 1, y + up + ey)
      end
   }
end

local function sub_box(base, sub, ht)
   local drop = floor(ht * 0.5)
   local extra = max(0, drop + sub.h - base.h)
   return {
      w = base.w + sub.w + 1, h = base.h + extra, a = base.a,
      draw = function(_, g, x, y)
         base:draw(g, x, y)
         sub:draw(g, x + base.w + 1, y + drop)
      end
   }
end

local function sqrt_box(content, ht, index)
   local rw = floor(ht * 0.55) + 3
   local top = 2
   local iw = index and max(0, index.w - floor(rw / 2)) or 0
   local h = content.h + top + 1
   return {
      w = iw + rw + content.w + 2, h = h, a = content.a + top + 1,
      draw = function(_, g, x, y)
         local x0 = x + iw
         g:drawLine(x0, y + floor(h * 0.6), x0 + floor(rw * 0.3), y + floor(h * 0.5))
         g:drawLine(x0 + floor(rw * 0.3), y + floor(h * 0.5), x0 + floor(rw * 0.55), y + h - 1)
         g:drawLine(x0 + floor(rw * 0.55), y + h - 1, x0 + rw - 1, y)
         g:drawLine(x0 + rw - 1, y, x0 + rw + content.w + 1, y)
         if index then
            index:draw(g, x, y + floor(h * 0.5) - index.h)
         end
         content:draw(g, x0 + rw + 1, y + top + 1)
      end
   }
end

local function overline_box(content)
   return {
      w = content.w, h = content.h + 2, a = content.a + 2,
      draw = function(_, g, x, y)
         g:drawLine(x + 1, y, x + content.w - 1, y)
         content:draw(g, x, y + 2)
      end
   }
end

-- Circumflex accent above the content (p-hat)
local function hat_box(content)
   return {
      w = content.w, h = content.h + 3, a = content.a + 3,
      draw = function(_, g, x, y)
         local m = x + floor(content.w / 2)
         g:drawLine(m - 2, y + 3, m, y + 1)
         g:drawLine(m, y + 1, m + 2, y + 3)
         content:draw(g, x, y + 3)
      end
   }
end

-- Delimiters: '(' ')' '[' ']' '{' '}' '|'
local function delim_box(gc, kind, h, size)
   local ht = text_height(gc, size)
   if h <= floor(ht * 1.4) and kind ~= '|' then
      local b = text_box(gc, kind, size)
      return b
   end
   local w = max(4, min(8, floor(h / 6) + 2))
   if kind == '|' then w = 3 end
   return {
      w = w, h = h, a = floor(h / 2),
      draw = function(_, g, x, y)
         local x1, x2 = x + 1, x + w - 2
         if kind == '(' then
            local ok = pcall(function() g:drawArc(x1, y, 2 * (x2 - x1) + 2, h - 1, 90, 180) end)
            if not ok then
               g:drawLine(x2, y, x1, y + floor(h / 4))
               g:drawLine(x1, y + floor(h / 4), x1, y + floor(3 * h / 4))
               g:drawLine(x1, y + floor(3 * h / 4), x2, y + h - 1)
            end
         elseif kind == ')' then
            local ok = pcall(function() g:drawArc(x1 - (x2 - x1) - 2, y, 2 * (x2 - x1) + 2, h - 1, 270, 180) end)
            if not ok then
               g:drawLine(x1, y, x2, y + floor(h / 4))
               g:drawLine(x2, y + floor(h / 4), x2, y + floor(3 * h / 4))
               g:drawLine(x2, y + floor(3 * h / 4), x1, y + h - 1)
            end
         elseif kind == '[' then
            g:drawLine(x2, y, x1, y)
            g:drawLine(x1, y, x1, y + h - 1)
            g:drawLine(x1, y + h - 1, x2, y + h - 1)
         elseif kind == ']' then
            g:drawLine(x1, y, x2, y)
            g:drawLine(x2, y, x2, y + h - 1)
            g:drawLine(x2, y + h - 1, x1, y + h - 1)
         elseif kind == '{' then
            local m = floor((x1 + x2) / 2)
            local c = y + floor(h / 2)
            g:drawLine(x2, y, m, y + 2)
            g:drawLine(m, y + 2, m, c - 2)
            g:drawLine(m, c - 2, x1, c)
            g:drawLine(x1, c, m, c + 2)
            g:drawLine(m, c + 2, m, y + h - 3)
            g:drawLine(m, y + h - 3, x2, y + h - 1)
         elseif kind == '}' then
            local m = floor((x1 + x2) / 2)
            local c = y + floor(h / 2)
            g:drawLine(x1, y, m, y + 2)
            g:drawLine(m, y + 2, m, c - 2)
            g:drawLine(m, c - 2, x2, c)
            g:drawLine(x2, c, m, c + 2)
            g:drawLine(m, c + 2, m, y + h - 3)
            g:drawLine(m, y + h - 3, x1, y + h - 1)
         elseif kind == '|' then
            g:drawLine(x + 1, y, x + 1, y + h - 1)
         end
      end
   }
end

local function wrap(gc, content, l, r, size)
   local h = content.h
   local left = delim_box(gc, l, h, size)
   local right = delim_box(gc, r, h, size)
   -- glyph delimiters are text height; center them on the axis
   return hbox({ left, content, right })
end

local function integral_box(gc, integrand, var, lob, hib, size)
   local ht = text_height(gc, size)
   local h = max(integrand.h + 4, floor(ht * 1.6))
   local sw = max(6, floor(ht * 0.5))
   local lw = max(lob and lob.w or 0, hib and hib.w or 0)
   local top_extra = hib and floor(hib.h / 2) or 0
   local bottom_extra = lob and floor(lob.h / 2) or 0
   local sign = {
      w = sw + lw + 2, h = h + top_extra + bottom_extra, a = top_extra + floor(h / 2),
   }
   sign.draw = function(_, g, x, y)
      local y0 = y + top_extra
      local m = x + floor(sw / 2)
      g:drawLine(x + sw - 1, y0 + 1, m + 1, y0)
      g:drawLine(m + 1, y0, m, y0 + 2)
      g:drawLine(m, y0 + 2, m - 1, y0 + h - 3)
      g:drawLine(m - 1, y0 + h - 3, m - 2, y0 + h - 1)
      g:drawLine(m - 2, y0 + h - 1, x, y0 + h - 2)
      if hib then hib:draw(g, x + sw + 1, y) end
      if lob then lob:draw(g, x + sw - 1, y + sign.h - lob.h) end
   end
   local dvar = text_box(gc, 'd' .. var, size, nil, 2)
   return hbox({ sign, integrand, dvar })
end

local function sigma_box(gc, body, lo, hi, size)
   local big = text_box(gc, sym.SUMSEQ, min(24, size + 5))
   local w = max(big.w, lo and lo.w or 0, hi and hi.w or 0)
   local th = hi and hi.h or 0
   local col = {
      w = w + 2, h = th + big.h + (lo and lo.h or 0), a = th + floor(big.h / 2),
      draw = function(_, g, x, y)
         if hi then hi:draw(g, x + floor((w - hi.w) / 2), y) end
         big:draw(g, x + floor((w - big.w) / 2), y + th)
         if lo then lo:draw(g, x + floor((w - lo.w) / 2), y + th + big.h) end
      end
   }
   return hbox({ col, body })
end

-- Grid of boxes (rows of cells); returns box
local function grid_box(rows, colgap, rowgap)
   local ncol = 0
   for _, r in ipairs(rows) do ncol = max(ncol, #r) end
   local cw = {}
   for c = 1, ncol do
      cw[c] = 0
      for _, r in ipairs(rows) do
         if r[c] then cw[c] = max(cw[c], r[c].w) end
      end
   end
   local rh, ra = {}, {}
   local total_h = 0
   for i, r in ipairs(rows) do
      local a, d = 0, 0
      for _, b in ipairs(r) do
         a = max(a, b.a)
         d = max(d, b.h - b.a)
      end
      ra[i], rh[i] = a, a + d
      total_h = total_h + rh[i] + (i > 1 and rowgap or 0)
   end
   local total_w = 0
   for c = 1, ncol do total_w = total_w + cw[c] + (c > 1 and colgap or 0) end
   return {
      w = total_w, h = total_h, a = floor(total_h / 2), col_w = cw,
      draw = function(_, g, x, y)
         local cy = y
         for i, r in ipairs(rows) do
            local cx = x
            for c = 1, ncol do
               local b = r[c]
               if b then b:draw(g, cx, cy + ra[i] - b.a) end
               cx = cx + cw[c] + colgap
            end
            cy = cy + rh[i] + rowgap
         end
      end
   }
end

-- Expression layout -----------------------------------------------------------------

local layout_node

local REL = {
   ['='] = true, ['<'] = true, ['>'] = true, [sym.LEQ] = true, [sym.GEQ] = true,
   [sym.NEQ] = true, ['/='] = true, ['<='] = true, ['>='] = true,
}

local OP_TEXT = {
   ['-'] = sym.NEGATE, ['*'] = sym.CDOT, ['and'] = 'and', ['or'] = 'or', ['xor'] = 'xor',
   ['<='] = sym.LEQ, ['>='] = sym.GEQ, ['/='] = sym.NEQ, ['=:'] = sym.STORE,
   [sym.STORE] = sym.STORE, ['|'] = '|',
}

local function prec(node)
   if node.kind ~= expr.OPERATOR then return 100 end
   if node.text == sym.NEGATE then return 15 end
   local _, lvl = operators.query_info(node.text)
   return lvl or 0
end

local function is_negative_number(node)
   return node.kind == expr.OPERATOR and node.text == sym.NEGATE
end

local function symbol_text(s)
   if s == sym.EULER then return 'e' end
   if s == sym.IMAG then return 'i' end
   return mb.rename(s)
end

local function number_box(gc, text, size)
   local m, e = text:match('^(.-)' .. sym.EE .. '(.+)$')
   if m then
      local ht = text_height(gc, size)
      e = e:gsub('^%-', sym.NEGATE)
      local mant = text_box(gc, m .. sym.CDOT .. '10', size)
      return sup_box(mant, text_box(gc, e, small(size)), ht)
   end
   return text_box(gc, text, size)
end

local function args_box(gc, args, size)
   local items = {}
   for i, a in ipairs(args) do
      if i > 1 then table.insert(items, text_box(gc, ',', size, nil, 1)) end
      table.insert(items, layout_node(gc, a, size))
   end
   if #items == 0 then return text_box(gc, '', size) end
   return hbox(items)
end

local function paren(gc, node, size)
   return wrap(gc, layout_node(gc, node, size), '(', ')', size)
end

local function layout_function(gc, node, size)
   local name = node.text
   local lname = name:lower()
   local args = node.children
   local ht = text_height(gc, size)

   if (name == sym.ROOT or lname == 'sqrt') and #args == 1 then
      return sqrt_box(layout_node(gc, args[1], size), ht)
   elseif lname == 'root' and #args == 2 then
      return sqrt_box(layout_node(gc, args[1], size), ht, layout_node(gc, args[2], small(size)))
   elseif lname == 'abs' and #args == 1 then
      return wrap(gc, layout_node(gc, args[1], size), '|', '|', size)
   elseif lname == 'pt' then
      return wrap(gc, args_box(gc, args, size), '(', ')', size)
   elseif lname == 'bar' and #args == 1 then
      return overline_box(layout_node(gc, args[1], size))
   elseif lname == 'hat' and #args == 1 then
      return hat_box(layout_node(gc, args[1], size))
   elseif lname == 'exp' and #args == 1 then
      return sup_box(text_box(gc, 'e', size), layout_node(gc, args[1], small(size)), ht)
   elseif (lname == 'integral' or name == sym.INTEGRAL or lname == 'nint') and #args >= 2 then
      local integrand = layout_node(gc, args[1], size)
      if args[1].kind == expr.OPERATOR and prec(args[1]) <= 12 then
         integrand = paren(gc, args[1], size)
      end
      local var = args[2].kind == expr.SYMBOL and symbol_text(args[2].text) or 'x'
      local lo = args[3] and layout_node(gc, args[3], small(size))
      local hi = args[4] and layout_node(gc, args[4], small(size))
      return integral_box(gc, integrand, var, lo, hi, size)
   elseif (lname == 'derivative' or lname == 'd') and #args >= 2 then
      local var = args[2].kind == expr.SYMBOL and symbol_text(args[2].text) or 'x'
      local op = frac_box(text_box(gc, 'd', size), text_box(gc, 'd' .. var, size))
      return hbox({ op, paren(gc, args[1], size) })
   elseif (lname == 'sumseq' or name == sym.SUMSEQ) and #args >= 4 then
      local lo = hbox({ layout_node(gc, args[2], small(size)), text_box(gc, '=', small(size)), layout_node(gc, args[3], small(size)) })
      local hi = layout_node(gc, args[4], small(size))
      local body = layout_node(gc, args[1], size)
      if args[1].kind == expr.OPERATOR and prec(args[1]) <= 12 then body = paren(gc, args[1], size) end
      return sigma_box(gc, body, lo, hi, size)
   elseif lname == 'log' and #args == 2 then
      local base = sub_box(text_box(gc, 'log', size), layout_node(gc, args[2], small(size)), ht)
      return hbox({ base, paren(gc, args[1], size) })
   elseif lname == 'piecewise' then
      local rows = {}
      local i = 1
      while i <= #args do
         local e = layout_node(gc, args[i], size)
         local c
         if args[i + 1] then
            c = layout_node(gc, args[i + 1], size)
         else
            c = text_box(gc, 'elsewhere', size)
         end
         table.insert(rows, { e, text_box(gc, ',', size), c })
         i = i + 2
      end
      local g = grid_box(rows, 3, 2)
      return wrap(gc, g, '{', ' ', size)
   end

   local nb = text_box(gc, symbol_text(name), size)
   return hbox({ nb, wrap(gc, args_box(gc, args, size), '(', ')', size) })
end

layout_node = function(gc, node, size)
   local k = node.kind
   local ht = text_height(gc, size)

   if k == expr.NUMBER then
      return number_box(gc, node.text, size)
   elseif k == expr.SYMBOL then
      return text_box(gc, symbol_text(node.text), size)
   elseif k == expr.STRING then
      local s = node.text
      if s:sub(1, 1) == '"' then s = s:sub(2, -2) end
      return text_box(gc, s, size)
   elseif k == expr.UNIT then
      return text_box(gc, node.text, size)
   elseif k == expr.LIST then
      return wrap(gc, args_box(gc, node.children, size), '{', '}', size)
   elseif k == expr.MATRIX then
      local is_matrix = node.children[1] and node.children[1].kind == expr.MATRIX
      if is_matrix then
         local rows = {}
         for _, r in ipairs(node.children) do
            local row = {}
            for _, c in ipairs(r.children) do table.insert(row, layout_node(gc, c, size)) end
            table.insert(rows, row)
         end
         return wrap(gc, grid_box(rows, 6, 2), '[', ']', size)
      end
      return wrap(gc, args_box(gc, node.children, size), '[', ']', size)
   elseif k == expr.SUB then
      local base = layout_node(gc, node.children[1], size)
      local idx = {}
      for i = 2, #node.children do table.insert(idx, node.children[i]) end
      return sub_box(base, args_box(gc, idx, small(size)), ht)
   elseif k == expr.FUNCTION then
      return layout_function(gc, node, size)
   elseif k == expr.OPERATOR then
      local op = node.text
      local ch = node.children
      local p = prec(node)

      if op == '/' and #ch == 2 then
         return frac_box(layout_node(gc, ch[1], size), layout_node(gc, ch[2], size))
      elseif op == '^' and #ch == 2 then
         local base = ch[1]
         local bb
         if base.kind == expr.SYMBOL and base.text == sym.EULER then
            bb = text_box(gc, 'e', size)
         elseif base.kind == expr.OPERATOR or (base.kind == expr.FUNCTION and
                not (base.text == sym.ROOT or base.text:lower() == 'abs')) then
            bb = paren(gc, base, size)
         else
            bb = layout_node(gc, base, size)
         end
         return sup_box(bb, layout_node(gc, ch[2], small(size)), ht)
      elseif op == sym.NEGATE and #ch == 1 then
         local c = ch[1]
         local cb
         if c.kind == expr.OPERATOR and prec(c) <= 12 then
            cb = paren(gc, c, size)
         else
            cb = layout_node(gc, c, size)
         end
         return hbox({ text_box(gc, sym.NEGATE, size), cb })
      elseif op == '!' or op == '%' or op == sym.DEGREE then
         local c = ch[1]
         local cb = c.kind == expr.OPERATOR and paren(gc, c, size) or layout_node(gc, c, size)
         return hbox({ cb, text_box(gc, op, size) })
      elseif #ch == 2 or (op == '*' or op == '+') then
         local items = {}
         local pad = (REL[op] or op == 'and' or op == 'or' or op == '|' or op == sym.STORE) and 4 or 2
         if op == '*' then pad = 1 end
         local opt = OP_TEXT[op] or op
         for i, c in ipairs(ch) do
            if i > 1 then
               table.insert(items, text_box(gc, opt, size, nil, pad))
            end
            local needs = false
            if c.kind == expr.OPERATOR and c.text ~= '/' then
               local cp = prec(c)
               if cp < p then
                  needs = true
               elseif cp == p and i > 1 and (op == '-' or op == '/') then
                  needs = true
               end
               if op == '*' and is_negative_number(c) and i > 1 then
                  needs = true
               end
               if (op == '+' or op == '-') and is_negative_number(c) and i > 1 then
                  needs = true
               end
               if REL[op] and REL[c.text] then
                  needs = false
               end
            end
            table.insert(items, needs and paren(gc, c, size) or layout_node(gc, c, size))
         end
         return hbox(items)
      end
   end
   return text_box(gc, tostring(node.text), size)
end

-- Parse helper (returns tree or nil)
function mb.parse(src)
   local ok, tree = pcall(function()
      local tokens = lexer.tokenize(src)
      if not tokens or #tokens == 0 then return nil end
      return expr.from_infix(tokens)
   end)
   if ok then return tree end
   return nil
end

-- Plain text fallback with renamed identifiers
local function plain(src)
   return (src:gsub('[%a][%w_]*', function(w) return mb.rename(w) end))
end

local cache = {}
local cache_n = 0

-- Layout expression string at font size; gc optional (uses platform.withGC)
function mb.layout(src, size, gc)
   src = src or ''
   size = size or 11
   local key = size .. '\0' .. src
   local hit = cache[key]
   if hit then return hit end

   local function build(g)
      local tree = mb.parse(src)
      local box
      if tree then
         local ok, res = pcall(layout_node, g, tree, size)
         if ok then box = res end
      end
      if not box then
         box = text_box(g, plain(src), size)
      end
      return box
   end

   local box
   if gc then
      box = build(gc)
   else
      box = platform.withGC(build)
   end
   if cache_n > 400 then
      cache = {}
      cache_n = 0
   end
   cache[key] = box
   cache_n = cache_n + 1
   return box
end

-- Text box (for mixing with math in rows)
function mb.text(s, size, gc, style)
   if gc then return text_box(gc, s, size, style) end
   return platform.withGC(function(g) return text_box(g, s, size, style) end)
end

mb.hbox = hbox

function mb.draw(box, gc, x, y)
   box:draw(gc, floor(x), floor(y))
end

function mb.clear_cache()
   cache = {}
   cache_n = 0
   height_cache = {}
end

return mb
