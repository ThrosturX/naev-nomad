local retrofit = {}

local size_rank = { Small = 1, Medium = 2, Large = 3 }

local function compatible(slot, module)
   if not slot or slot.type ~= "Utility" then return false end
   if slot.property ~= nil and slot.property ~= "" then return false end
   if slot.required or slot.locked then return false end
   return (size_rank[slot.size] or 0)
      >= (size_rank[module.minimum_size] or 0)
end

local function better(slot, candidate, preference)
   if not candidate then return true end
   local left = size_rank[slot.size] or 0
   local right = size_rank[candidate.size] or 0
   if left == right then return slot.id < candidate.id end
   if preference == "largest" then return left > right end
   return left < right
end

function retrofit.allocate(slots, equipped, modules)
   local normalized = {}
   for index, slot in ipairs(slots or {}) do
      local copy = {}
      for key, value in pairs(slot) do copy[key] = value end
      copy.id = copy.id or index
      normalized[#normalized + 1] = copy
   end

   local occupied = {}
   for id, name in pairs(equipped or {}) do
      if name then occupied[id] = name end
   end

   local allocations = {}
   for _, module in ipairs(modules or {}) do
      local existing
      for _, slot in ipairs(normalized) do
         if occupied[slot.id] == module.outfit and compatible(slot, module) then
            existing = slot
            break
         end
      end

      local selected = existing
      if not selected then
         for _, slot in ipairs(normalized) do
            if not occupied[slot.id] and compatible(slot, module)
               and better(slot, selected, module.preference) then
               selected = slot
            end
         end
      end

      if selected then
         occupied[selected.id] = module.outfit
         allocations[#allocations + 1] = {
            id = selected.id,
            outfit = module.outfit,
            installed = existing ~= nil,
         }
      end
   end
   return allocations
end

return retrofit
