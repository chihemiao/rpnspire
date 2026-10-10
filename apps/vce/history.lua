-- Problem history for the VCE toolkit (persisted with on.save/on.restore)
local H = {}
H.__index = H

H.MAX = 60

function H.new()
   return setmetatable({ items = {}, current = nil, next_id = 1 }, H)
end

-- Create a problem for solver `sid`; returns problem and its index
function H:add(sid, inputs, tag)
   local p = { id = self.next_id, solver = sid, inputs = inputs or {}, tag = tag or '' }
   self.next_id = self.next_id + 1
   table.insert(self.items, p)
   while #self.items > H.MAX do
      table.remove(self.items, 1)
   end
   self.current = #self.items
   return p, self.current
end

function H:get(i)
   return self.items[i or self.current]
end

function H:index_of(p)
   for i, q in ipairs(self.items) do
      if q == p then return i end
   end
end

function H:remove(i)
   table.remove(self.items, i)
   if self.current and self.current > #self.items then
      self.current = #self.items > 0 and #self.items or nil
   end
end

-- True if problem has no inputs and no tag
function H.is_empty(p)
   if p.tag and p.tag ~= '' then return false end
   for _, v in pairs(p.inputs) do
      if v and v ~= '' then return false end
   end
   return true
end

-- Serialize to a plain table (strings/numbers only)
function H:save()
   local items = {}
   for _, p in ipairs(self.items) do
      local inputs = {}
      for k, v in pairs(p.inputs) do
         if type(v) == 'string' and v ~= '' then inputs[k] = v end
      end
      table.insert(items, { id = p.id, solver = p.solver, inputs = inputs, tag = p.tag or '' })
   end
   return { items = items, current = self.current or 0, next_id = self.next_id }
end

function H.load(state)
   local h = H.new()
   if type(state) ~= 'table' or type(state.items) ~= 'table' then return h end
   for _, p in ipairs(state.items) do
      if type(p) == 'table' and type(p.solver) == 'string' then
         local inputs = {}
         if type(p.inputs) == 'table' then
            for k, v in pairs(p.inputs) do
               if type(k) == 'string' and type(v) == 'string' then inputs[k] = v end
            end
         end
         table.insert(h.items, { id = tonumber(p.id) or h.next_id, solver = p.solver, inputs = inputs,
                                 tag = type(p.tag) == 'string' and p.tag or '' })
         h.next_id = math.max(h.next_id, (tonumber(p.id) or 0) + 1)
      end
   end
   h.next_id = math.max(h.next_id, tonumber(state.next_id) or 1)
   local c = tonumber(state.current)
   if c and c >= 1 and c <= #h.items then h.current = c end
   return h
end

return H
