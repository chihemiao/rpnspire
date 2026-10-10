-- One home entry for several solvers (e.g. all of Probability). A 'type'
-- picker chooses the solver; each member keeps its own inputs, stored as
-- '<member>.<field>' so switching type and back loses nothing.
local G = {}

-- Inputs of member m from the group's inputs
function G.sub(I, m)
   local t = {}
   local pre = m.id .. '.'
   for k, v in pairs(I) do
      if k:sub(1, #pre) == pre then t[k:sub(#pre + 1)] = v end
   end
   return t
end

-- def = { id, title, short, group, course, desc, members = { solver, ... } }
function G.new(def)
   local S = {
      id = def.id, title = def.title, short = def.short, group = def.group, course = def.course,
      desc = def.desc, blurb = def.blurb, members = def.members, is_group = true,
   }
   local options, by = {}, {}
   for _, m in ipairs(def.members) do
      table.insert(options, { m.id, m.title })
      by[m.id] = m
   end
   -- 'pick': no default; the app shows the members as a list until one is chosen
   S.by_member = by
   S.fields = { { id = 'type', label = def.pick_label or 'Type', kind = 'choice', options = options, pick = true } }
   S.view_fields = {}
   for _, m in ipairs(def.members) do
      for _, f in ipairs(m.fields) do
         local nf = {}
         for k, v in pairs(f) do nf[k] = v end
         nf.id = m.id .. '.' .. f.id
         nf.owner, nf.base = m.id, f.id
         local show, label = f.show, f.label
         nf.show = function(I)
            if I.type ~= m.id then return false end
            return not show or show(G.sub(I, m))
         end
         if type(label) == 'function' then
            nf.label = function(I) return label(G.sub(I, m)) end
         end
         table.insert(S.fields, nf)
      end
      for k, v in pairs(m.view_fields or {}) do S.view_fields[m.id .. '.' .. k] = v end
   end

   function S.member(I)
      return by[I and I.type or '']
   end

   function S.solve(I, R)
      local m = S.member(I)
      if not m then
         R:note('Choose the kind of problem')
         return
      end
      return m.solve(G.sub(I, m), R)
   end

   function S.view(I, R)
      local m = S.member(I)
      if m and m.view then m.view(G.sub(I, m), R) end
   end

   -- Example inputs for a member (prefixed), with the type set
   function S.example_for(mid)
      local m = by[mid]
      if not (m and m.example) then return nil end
      local t = { type = mid }
      for k, v in pairs(m.example) do t[mid .. '.' .. k] = v end
      return t
   end

   return S
end

return G
