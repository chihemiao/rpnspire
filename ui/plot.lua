-- 2D function plotter (drawn with the TI graphics context).
--
-- A plot spec:
--   {
--     xmin, xmax, ymin, ymax,             -- window (ymin/ymax nil: automatic)
--     curves = {                          -- what to draw
--       { fn = f },                       -- y = f(x)
--       { kind = 'x', fn = g },           -- x = g(y)
--       { kind = 'param', fx = x, fy = y, tmin = a, tmax = b },
--       { pts = { {x, y}, ... }, dots = true, line = true },
--     },                                  -- optional: color, label
--     asymptotes = { { kind = 'v', x = 1 }, { kind = 'h', y = 0 }, { kind = 'f', fn = f } },
--     breaks = { x1, x2 },                -- x values where curves must not be joined
--     points = { { x = 1, y = 2, kind = 'max'|'min'|'inflect'|'intercept'|'hole'|'jump'|'end'|'cusp'|'point', label = '...' } },
--     shade = { { kind = 'x', top = f, bottom = g|nil, a = 0, b = 1 } | { kind = 'y', right = f, left = g|nil, a, b } },
--     field = { fn = function(x, y) return slope end },
--     axis = 'x'|'y',                     -- highlighted axis (solid of revolution)
--     vlines = { { x = a } }, hlines = { { y = c } },  -- interval markers
--   }
-- Functions return a number or nil (undefined).
local mb = require 'ui.mathbox'

local P = {}

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local unpack = unpack or table.unpack

P.colors = {
   bg = 0xFFFFFF,
   grid = 0xECECEC,
   axis = 0x5A5A5A,
   tick = 0x6A6A6A,
   curve = { 0x1F5FBF, 0xD2691E, 0x2E8B57, 0x8B3FA6 },
   asym = 0xC03A3A,
   shade = 0xBFD6F2,
   shade2 = 0xF6D5B8,
   field = 0x9AA7B8,
   max = 0xD03030, min = 0xD03030, inflect = 0x1E9450, intercept = 0x202020,
   hole = 0x202020, jump = 0x202020, ['end'] = 0x202020, cusp = 0xE08A00, point = 0x1F5FBF,
   label = 0x303030,
   axis_hl = 0x8B3FA6,
   frame = 0xB8B8B8,
   cursor = 0xE00000,
}

-- Nice tick step for a range
function P.nice_step(range, target)
   target = target or 6
   if range <= 0 then return 1 end
   local raw = range / target
   local p = 10 ^ floor(math.log(raw) / math.log(10))
   local m = raw / p
   local step
   if m < 1.5 then step = 1 elseif m < 3 then step = 2 elseif m < 7 then step = 5 else step = 10 end
   return step * p
end

local function fmt_tick(v, step)
   if abs(v) < step * 1e-6 then return '0' end
   local dec = 0
   if step < 1 then dec = math.min(6, math.ceil(-math.log(step) / math.log(10) - 1e-9)) end
   local s = string.format('%.' .. dec .. 'f', v)
   if s:sub(1, 1) == '-' then s = '\226\136\146' .. s:sub(2) end
   return s
end
P.fmt_tick = fmt_tick

-- Sample curve values to choose a y window
function P.auto_range(spec)
   if spec.ymin and spec.ymax and spec.ymax > spec.ymin then return end
   local vals = {}
   local xmin, xmax = spec.xmin, spec.xmax
   for _, c in ipairs(spec.curves or {}) do
      if c.fn and (c.kind == nil or c.kind == 'y') then
         for i = 0, 200 do
            local x = xmin + (xmax - xmin) * i / 200
            local y = c.fn(x)
            if y and abs(y) < 1e12 then table.insert(vals, y) end
         end
      elseif c.kind == 'param' then
         for i = 0, 200 do
            local t = c.tmin + (c.tmax - c.tmin) * i / 200
            local y = c.fy(t)
            if y and abs(y) < 1e12 then table.insert(vals, y) end
         end
      elseif c.pts then
         for _, p in ipairs(c.pts) do table.insert(vals, p[2]) end
      elseif c.kind == 'x' then
         -- x = g(y): y range is the curve's own range
         if c.ymin then table.insert(vals, c.ymin) end
         if c.ymax then table.insert(vals, c.ymax) end
      end
   end
   for _, p in ipairs(spec.points or {}) do
      if p.y and abs(p.y) < 1e12 then table.insert(vals, p.y) end
   end
   for _, a in ipairs(spec.asymptotes or {}) do
      if a.kind == 'h' then table.insert(vals, a.y) end
   end
   if #vals == 0 then
      spec.ymin, spec.ymax = spec.ymin or -10, spec.ymax or 10
      return
   end
   table.sort(vals)
   local lo = vals[max(1, floor(#vals * 0.04) + 1)]
   local hi = vals[min(#vals, floor(#vals * 0.96) + 1)]
   -- feature points must stay visible
   for _, p in ipairs(spec.points or {}) do
      if p.y and abs(p.y) < 1e12 then
         lo, hi = min(lo, p.y), max(hi, p.y)
      end
   end
   if hi - lo < 1e-9 then lo, hi = lo - 1, hi + 1 end
   local pad = (hi - lo) * 0.15
   lo, hi = lo - pad, hi + pad
   -- include the x-axis when it is close
   if lo > 0 and lo < (hi - lo) * 0.6 then lo = -(hi - lo) * 0.05 end
   if hi < 0 and -hi < (hi - lo) * 0.6 then hi = (hi - lo) * 0.05 end
   spec.ymin = spec.ymin or lo
   spec.ymax = spec.ymax or hi
end

-- Coordinate mapping
local function mapper(spec, r)
   local sx = r.width / (spec.xmax - spec.xmin)
   local sy = r.height / (spec.ymax - spec.ymin)
   local function px(x) return r.x + (x - spec.xmin) * sx end
   local function py(y) return r.y + r.height - (y - spec.ymin) * sy end
   local function wx(p) return spec.xmin + (p - r.x) / sx end
   local function wy(p) return spec.ymin + (r.y + r.height - p) / sy end
   return px, py, wx, wy
end
P.mapper = mapper

local function clampy(v, r)
   return max(r.y - 2 * r.height, min(r.y + 3 * r.height, v))
end

local function line(g, x1, y1, x2, y2)
   g:drawLine(floor(x1 + 0.5), floor(y1 + 0.5), floor(x2 + 0.5), floor(y2 + 0.5))
end

local function dashed(g, x1, y1, x2, y2, on, off)
   on, off = on or 4, off or 3
   local dx, dy = x2 - x1, y2 - y1
   local len = math.sqrt(dx * dx + dy * dy)
   if len < 1 then return end
   local ux, uy = dx / len, dy / len
   local d = 0
   while d < len do
      local e = min(len, d + on)
      line(g, x1 + ux * d, y1 + uy * d, x1 + ux * e, y1 + uy * e)
      d = e + off
   end
end
P.dashed = dashed

local function thick_line(g, x1, y1, x2, y2, w)
   line(g, x1, y1, x2, y2)
   if (w or 1) >= 2 then
      if abs(x2 - x1) > abs(y2 - y1) then
         line(g, x1, y1 + 1, x2, y2 + 1)
      else
         line(g, x1 + 1, y1, x2 + 1, y2)
      end
   end
end

local function disc(g, x, y, rad, fill, stroke)
   x, y = floor(x + 0.5), floor(y + 0.5)
   local ok = pcall(function()
      if fill then
         g:setColorRGB(fill)
         g:fillArc(x - rad, y - rad, 2 * rad, 2 * rad, 0, 360)
      end
      if stroke then
         g:setColorRGB(stroke)
         g:drawArc(x - rad, y - rad, 2 * rad, 2 * rad, 0, 360)
      end
   end)
   if not ok then
      if fill then
         g:setColorRGB(fill)
         g:fillRect(x - rad, y - rad, 2 * rad, 2 * rad)
      end
      if stroke then
         g:setColorRGB(stroke)
         g:drawRect(x - rad, y - rad, 2 * rad, 2 * rad)
      end
   end
end

local function marker(g, x, y, kind)
   local C = P.colors
   local c = C[kind] or C.point
   if kind == 'hole' then
      disc(g, x, y, 3, 0xFFFFFF, c)
   elseif kind == 'inflect' then
      g:setColorRGB(c)
      local ix, iy = floor(x + 0.5), floor(y + 0.5)
      for d = 0, 3 do
         g:drawLine(ix - 3 + d, iy - d, ix + 3 - d, iy - d)
         g:drawLine(ix - 3 + d, iy + d, ix + 3 - d, iy + d)
      end
   elseif kind == 'cusp' then
      g:setColorRGB(c)
      g:fillRect(floor(x) - 3, floor(y) - 3, 6, 6)
   elseif kind == 'intercept' or kind == 'end' then
      disc(g, x, y, 2, c, nil)
   else
      disc(g, x, y, 3, c, nil)
   end
end
P.marker = marker

-- Marker drawn on top when several features share a point
local RANK = { max = 1, min = 1, cusp = 2, inflect = 3, hole = 4, jump = 4, ['end'] = 5, point = 6, intercept = 7 }

-- Merge points at the same position (e.g. a minimum that is also an
-- intercept): one entry, the most important marker, labels combined as
-- 'min, cusp (0, 0)'. Hidden kinds are dropped.
function P.merge_points(points, hide)
   hide = hide or {}
   local out = {}
   for _, p in ipairs(points or {}) do
      if p.x and p.y and not hide[p.kind] then
         local same
         for _, q in ipairs(out) do
            local tol = 1e-9 * math.max(1, abs(p.x), abs(p.y))
            if abs(q.x - p.x) <= tol and abs(q.y - p.y) <= tol then same = q break end
         end
         local name, coords = (p.label or ''):match('^(.-)%s*(%b())$')
         if not name then name, coords = p.label or '', '' end
         if same then
            if name ~= '' and not same.names[name] then
               same.names[name] = true
               table.insert(same.name_list, name)
            end
            if (RANK[p.kind] or 9) < (RANK[same.kind] or 9) then
               same.kind, same.y2 = p.kind, p.y2
            end
            if coords ~= '' and same.coords == '' then same.coords = coords end
         else
            local q = { x = p.x, y = p.y, kind = p.kind, y2 = p.y2, curve = p.curve,
                        names = {}, name_list = {}, coords = coords, has_label = p.label ~= nil }
            if name ~= '' then
               q.names[name] = true
               table.insert(q.name_list, name)
            end
            table.insert(out, q)
         end
      end
   end
   for _, q in ipairs(out) do
      if q.has_label then
         local n = table.concat(q.name_list, ', ')
         q.label = (n ~= '' and q.coords ~= '') and (n .. ' ' .. q.coords) or (n .. q.coords)
      end
      q.names, q.name_list, q.coords, q.has_label = nil, nil, nil, nil
   end
   return out
end

-- Everything except the trace cursor: sampled once, then replayed (P.draw)
local function draw_body(g, r, spec, opts, hide)
   local C = P.colors
   local px, py = mapper(spec, r)

   g:setColorRGB(C.bg)
   g:fillRect(r.x, r.y, r.width, r.height)

   -- grid and ticks
   local tick_size = 7
   g:setFont('sansserif', 'r', mb.snap(tick_size))
   local xs = P.nice_step(spec.xmax - spec.xmin, opts.small and 5 or 7)
   local ys = P.nice_step(spec.ymax - spec.ymin, opts.small and 4 or 6)
   g:setColorRGB(C.grid)
   local x0 = math.ceil(spec.xmin / xs) * xs
   for x = x0, spec.xmax, xs do line(g, px(x), r.y, px(x), r.y + r.height) end
   local y0 = math.ceil(spec.ymin / ys) * ys
   for y = y0, spec.ymax, ys do line(g, r.x, py(y), r.x + r.width, py(y)) end

   -- shading
   for si, s in ipairs(spec.shade or {}) do
      g:setColorRGB(si == 1 and (s.color or C.shade) or (s.color or C.shade2))
      if s.kind == 'y' then
         local pa, pb = py(s.a), py(s.b)
         local top, bot = min(pa, pb), max(pa, pb)
         for p = floor(top), floor(bot), 2 do
            local yy = spec.ymin + (r.y + r.height - p) / (r.height / (spec.ymax - spec.ymin))
            local x1 = s.right(yy)
            local x2 = s.left and s.left(yy) or 0
            if x1 and x2 then line(g, px(x1), p, px(x2), p) end
         end
      else
         local pa, pb = px(min(s.a, s.b)), px(max(s.a, s.b))
         for p = floor(pa), floor(pb), 2 do
            local xx = spec.xmin + (p - r.x) / (r.width / (spec.xmax - spec.xmin))
            local y1 = s.top(xx)
            local y2 = s.bottom and s.bottom(xx) or 0
            if y1 and y2 then line(g, p, clampy(py(y1), r), p, clampy(py(y2), r)) end
         end
      end
   end

   -- slope field
   if spec.field and not hide.field then
      g:setColorRGB(C.field)
      local nx, ny = opts.small and 12 or 18, opts.small and 8 or 12
      local cw, ch = r.width / nx, r.height / ny
      local seg = min(cw, ch) * 0.35
      for i = 0, nx - 1 do
         for j = 0, ny - 1 do
            local cx, cy = r.x + (i + 0.5) * cw, r.y + (j + 0.5) * ch
            local wx = spec.xmin + (cx - r.x) / r.width * (spec.xmax - spec.xmin)
            local wy = spec.ymax - (cy - r.y) / r.height * (spec.ymax - spec.ymin)
            local m = spec.field.fn(wx, wy)
            if m then
               -- slope in pixel space
               local pm = -m * (r.height / (spec.ymax - spec.ymin)) / (r.width / (spec.xmax - spec.xmin))
               local ang = math.atan(pm)
               local dx, dy = math.cos(ang) * seg, math.sin(ang) * seg
               line(g, cx - dx, cy - dy, cx + dx, cy + dy)
            end
         end
      end
   end

   -- axes
   local ax_y = (spec.ymin <= 0 and spec.ymax >= 0) and py(0) or nil
   local ax_x = (spec.xmin <= 0 and spec.xmax >= 0) and px(0) or nil
   g:setColorRGB(C.axis)
   if ax_y then line(g, r.x, ax_y, r.x + r.width, ax_y) end
   if ax_x then line(g, ax_x, r.y, ax_x, r.y + r.height) end
   if spec.axis == 'x' and ax_y then
      g:setColorRGB(C.axis_hl)
      line(g, r.x, ax_y - 1, r.x + r.width, ax_y - 1)
      line(g, r.x, ax_y + 1, r.x + r.width, ax_y + 1)
   elseif spec.axis == 'y' and ax_x then
      g:setColorRGB(C.axis_hl)
      line(g, ax_x - 1, r.y, ax_x - 1, r.y + r.height)
      line(g, ax_x + 1, r.y, ax_x + 1, r.y + r.height)
   end

   -- tick labels
   g:setColorRGB(C.tick)
   local th = g:getStringHeight('0')
   local label_y = ax_y and min(r.y + r.height - th, ax_y + 1) or (r.y + r.height - th)
   local last_right = -1e9
   for x = x0, spec.xmax, xs do
      if abs(x) > xs * 1e-6 or not ax_x then
         local s = fmt_tick(x, xs)
         local w = g:getStringWidth(s)
         local lx = px(x) - w / 2
         if lx > last_right + 2 and lx > r.x and lx + w < r.x + r.width then
            g:drawString(s, floor(lx), floor(label_y), 'top')
            last_right = lx + w
         end
      end
   end
   local label_x = ax_x and ax_x + 2 or r.x + 2
   for y = y0, spec.ymax, ys do
      if abs(y) > ys * 1e-6 or not ax_y then
         local s = fmt_tick(y, ys)
         local w = g:getStringWidth(s)
         local lx = label_x
         if lx + w > r.x + r.width then lx = r.x + r.width - w - 1 end
         local ly = py(y) - th / 2
         if ly > r.y and ly + th < r.y + r.height then
            g:drawString(s, floor(lx), floor(ly), 'top')
         end
      end
   end

   -- interval markers
   for _, v in ipairs(spec.vlines or {}) do
      g:setColorRGB(v.color or C.frame)
      dashed(g, px(v.x), r.y, px(v.x), r.y + r.height, 2, 2)
   end
   for _, h in ipairs(spec.hlines or {}) do
      g:setColorRGB(h.color or C.frame)
      dashed(g, r.x, py(h.y), r.x + r.width, py(h.y), 2, 2)
   end

   -- asymptotes. One that lies on an axis (x = 0, y = 0) is drawn as two
   -- dashed lines either side of it, so the axis does not hide it.
   if not hide.asym then
      g:setColorRGB(C.asym)
      local function vdash(p)
         if ax_x and abs(p - ax_x) < 2 then
            local off = spec.axis == 'y' and 3 or 2
            dashed(g, ax_x - off, r.y, ax_x - off, r.y + r.height)
            dashed(g, ax_x + off, r.y, ax_x + off, r.y + r.height)
         else
            dashed(g, p, r.y, p, r.y + r.height)
         end
      end
      local function hdash(p)
         if ax_y and abs(p - ax_y) < 2 then
            local off = spec.axis == 'x' and 3 or 2
            dashed(g, r.x, ax_y - off, r.x + r.width, ax_y - off)
            dashed(g, r.x, ax_y + off, r.x + r.width, ax_y + off)
         else
            dashed(g, r.x, p, r.x + r.width, p)
         end
      end
      for _, a in ipairs(spec.asymptotes or {}) do
         if a.kind == 'v' then
            vdash(px(a.x))
         elseif a.kind == 'h' then
            hdash(py(a.y))
         elseif a.kind == 'f' and a.fn then
            local prev
            for p = r.x, r.x + r.width, 3 do
               local xx = spec.xmin + (p - r.x) / r.width * (spec.xmax - spec.xmin)
               local yy = a.fn(xx)
               if yy then
                  local q = clampy(py(yy), r)
                  if prev then line(g, prev[1], prev[2], p, q) end
                  prev = { p, q }
               else
                  prev = nil
               end
               -- gap every other step for a dashed look
               if floor((p - r.x) / 3) % 2 == 1 then prev = nil end
            end
         end
      end
   end

   -- curves
   local breaks = spec.breaks or {}
   local function crosses_break(xa, xb)
      for _, b in ipairs(breaks) do
         if (b - xa) * (b - xb) <= 0 then return true end
      end
      return false
   end
   local pix = {} -- curve samples, so labels can avoid the curves
   for ci, c in ipairs(spec.curves or {}) do
      g:setColorRGB(c.color or C.curve[(ci - 1) % #C.curve + 1])
      local w = c.width or 2
      if c.pts then
         local prev
         for _, p in ipairs(c.pts) do
            local qx, qy = px(p[1]), clampy(py(p[2]), r)
            table.insert(pix, { qx, qy })
            if c.line ~= false and prev then thick_line(g, prev[1], prev[2], qx, qy, 1) end
            if c.dots then g:fillRect(floor(qx) - 2, floor(qy) - 2, 4, 4) end
            prev = { qx, qy }
         end
      else
         local n = floor(r.width * 1.5)
         local prev
         for i = 0, n do
            local qx, qy, key
            if c.kind == 'param' then
               local t = c.tmin + (c.tmax - c.tmin) * i / n
               local xv, yv = c.fx(t), c.fy(t)
               if xv and yv then qx, qy, key = px(xv), py(yv), t end
            elseif c.kind == 'x' then
               local yv = (c.ymin or spec.ymin) + ((c.ymax or spec.ymax) - (c.ymin or spec.ymin)) * i / n
               local xv = c.fn(yv)
               if xv then qx, qy, key = px(xv), py(yv), yv end
            else
               local xv = spec.xmin + (spec.xmax - spec.xmin) * i / n
               local yv = c.fn(xv)
               if yv then qx, qy, key = px(xv), py(yv), xv end
            end
            if qx then
               local cy = clampy(qy, r)
               if i % 2 == 0 then table.insert(pix, { qx, cy }) end
               if prev then
                  local jump = abs(qy - prev[2]) > r.height * 1.2 and
                     ((qy < r.y and prev[2] > r.y + r.height) or (qy > r.y + r.height and prev[2] < r.y))
                  local brk = (c.kind == nil or c.kind == 'y') and crosses_break(prev[3], key)
                  if not jump and not brk then
                     thick_line(g, prev[1], prev[2], qx, cy, w)
                  end
               end
               prev = { qx, cy, key }
            else
               prev = nil
            end
         end
      end
   end

   -- points: markers first, then labels placed where they cover the least
   local pts = {}
   for _, p in ipairs(P.merge_points(spec.points, hide)) do
      local qx, qy = px(p.x), py(p.y)
      if qx >= r.x - 3 and qx <= r.x + r.width + 3 and qy >= r.y - 3 and qy <= r.y + r.height + 3 then
         marker(g, qx, qy, p.kind)
         if p.kind == 'jump' and p.y2 then marker(g, qx, py(p.y2), 'hole') end
         table.insert(pts, { p = p, qx = qx, qy = qy })
      end
   end
   if opts.labels and not hide.labels then
      g:setFont('sansserif', 'r', mb.snap(7))
      local placed = {}
      local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
         return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
      end
      for _, e in ipairs(pts) do
         local label = e.p.label
         if label and label ~= '' then
            local w = g:getStringWidth(label)
            local qx, qy = e.qx, e.qy
            local cands = {
               { qx + 4, qy - th - 2 }, { qx - w - 4, qy - th - 2 }, { qx + 4, qy + 3 }, { qx - w - 4, qy + 3 },
               { qx + 6, qy - th / 2 }, { qx - w - 6, qy - th / 2 }, { qx - w / 2, qy - th - 4 }, { qx - w / 2, qy + 5 },
            }
            local best, best_score
            for k, c in ipairs(cands) do
               local lx, ly = c[1], c[2]
               local score = k * 0.01
               if lx < r.x or lx + w > r.x + r.width or ly < r.y or ly + th > r.y + r.height then
                  score = score + 1000
               end
               for _, q in ipairs(placed) do
                  if overlap(lx - 2, ly - 1, w + 4, th + 2, q[1], q[2], q[3], th) then score = score + 500 end
               end
               for _, o in ipairs(pts) do
                  if o ~= e and overlap(lx, ly, w, th, o.qx - 3, o.qy - 3, 6, 6) then score = score + 100 end
               end
               for _, q in ipairs(pix) do
                  if q[1] >= lx - 1 and q[1] <= lx + w + 1 and q[2] >= ly - 1 and q[2] <= ly + th + 1 then
                     score = score + 1
                  end
               end
               if not best_score or score < best_score then best, best_score = c, score end
            end
            -- in the small graph a label that would cover another is left out
            -- (the marker stays; the full screen view has room for it)
            if not (opts.small and best_score >= 500) then
               local lx, ly = floor(best[1]), floor(best[2])
               g:setColorRGB(C.bg)
               g:fillRect(lx - 1, ly, w + 2, th)
               g:setColorRGB(C.label)
               g:drawString(label, lx, ly, 'top')
               table.insert(placed, { lx, ly, w })
            end
         end
      end
   end

   g:setColorRGB(C.frame)
   g:drawRect(r.x, r.y, r.width, r.height)
end

-- Recording graphics context: forwards every call to the real one and keeps
-- the drawing calls (coordinates relative to the plot origin) for replay.
-- For each drawing method: positions of its x and y arguments.
local COORDS = {
   drawLine = { 1, 2, 3, 4 }, fillRect = { 1, 2 }, drawRect = { 1, 2 },
   fillArc = { 1, 2 }, drawArc = { 1, 2 }, drawString = { 2, 3 },
   setColorRGB = {}, setFont = {}, setPen = {},
}

local function recorder(g, ops, ox, oy)
   return setmetatable({}, { __index = function(_, m)
      local pos = COORDS[m]
      if not pos then
         return function(_, ...) return g[m](g, ...) end
      end
      return function(_, ...)
         local res = g[m](g, ...)
         local op = { m, ... }
         op.n = select('#', ...)
         for k, i in ipairs(pos) do
            if type(op[i + 1]) == 'number' then
               op[i + 1] = op[i + 1] - ((k % 2 == 1) and ox or oy)
            end
         end
         ops[#ops + 1] = op
         return res
      end
   end })
end

local function replay(g, ops, ox, oy)
   local args = {}
   for _, op in ipairs(ops) do
      local m = op[1]
      local pos = COORDS[m]
      for i = 1, op.n do args[i] = op[i + 1] end
      for k, i in ipairs(pos) do
         if type(args[i]) == 'number' then
            args[i] = args[i] + ((k % 2 == 1) and ox or oy)
         end
      end
      g[m](g, unpack(args, 1, op.n))
   end
end

local function hide_key(hide)
   local keys = {}
   for k, v in pairs(hide) do
      if v then table.insert(keys, tostring(k)) end
   end
   table.sort(keys)
   return table.concat(keys, '+')
end

-- Draw the plot in rect r (ui.rect-like {x, y, width, height})
--   opts: labels (bool), small (bool, mini graph), cursor = {x, y},
--         hide = {asym=true,...}, clip = rect to stay inside (e.g. a scrolled sheet)
-- The plot (curve samples, label placement, ...) is computed once per window
-- and size and kept in the spec; later paints replay it, so moving the trace
-- cursor or scrolling does not evaluate the functions again.
function P.draw(g, r, spec, opts)
   opts = opts or {}
   P.auto_range(spec)
   local hide = opts.hide or spec.hide or {}

   local cx, cy, cw, ch = r.x, r.y, r.width + 1, r.height + 1
   if opts.clip then
      local c = opts.clip
      local x2, y2 = min(cx + cw, c.x + c.width), min(cy + ch, c.y + c.height)
      cx, cy = max(cx, c.x), max(cy, c.y)
      cw, ch = max(0, x2 - cx), max(0, y2 - cy)
   end
   g:clipRect('set', cx, cy, cw, ch)

   local key = table.concat({ r.width, r.height, spec.xmin, spec.xmax, spec.ymin, spec.ymax,
                              opts.labels and 1 or 0, opts.small and 1 or 0, hide_key(hide) }, ',')
   local cache = spec._plot_cache
   if not cache or (cache.n or 0) >= 3 and not cache[key] then
      cache = { n = 0 }
      spec._plot_cache = cache
   end
   local ops = cache[key]
   if ops then
      replay(g, ops, r.x, r.y)
   else
      ops = {}
      draw_body(recorder(g, ops, r.x, r.y), r, spec, opts, hide)
      cache[key] = ops
      cache.n = cache.n + 1
   end

   -- trace cursor
   if opts.cursor and opts.cursor.x and opts.cursor.y then
      local px, py = mapper(spec, r)
      local qx, qy = px(opts.cursor.x), py(opts.cursor.y)
      g:setColorRGB(P.colors.cursor)
      dashed(g, qx, r.y, qx, r.y + r.height, 1, 3)
      dashed(g, r.x, qy, r.x + r.width, qy, 1, 3)
      disc(g, qx, qy, 3, nil, P.colors.cursor)
   end
   g:clipRect('reset')
end

return P
