local policy = {}

local function copy_bays(bays)
   local copy = {}
   for index, bay in ipairs(bays or {}) do
      copy[index] = {
         name = bay.name,
         max_size = bay.max_size,
         index = index,
      }
   end
   return copy
end

local function sorted_ships(ships)
   local sorted = {}
   for index, candidate in ipairs(ships or {}) do
      sorted[#sorted + 1] = { ship = candidate, index = index }
   end
   table.sort(sorted, function(left, right)
      local left_size = tonumber(left.ship.size) or -1
      local right_size = tonumber(right.ship.size) or -1
      if left_size ~= right_size then
         return left_size > right_size
      end
      return left.index < right.index
   end)
   return sorted
end

local function smallest_compatible(bays, size)
   local selected
   for index, bay in ipairs(bays) do
      if size <= bay.max_size and (not selected
         or bay.max_size < bays[selected].max_size
         or (bay.max_size == bays[selected].max_size
            and bay.index < bays[selected].index)) then
         selected = index
      end
   end
   return selected
end

function policy.match(bays, ships)
   local remaining = copy_bays(bays)
   local assignments = {}
   local violations = {}

   for _, item in ipairs(sorted_ships(ships)) do
      local candidate = item.ship
      local size = tonumber(candidate.size)
      local bay_index = size and smallest_compatible(remaining, size) or nil
      if bay_index then
         local bay = table.remove(remaining, bay_index)
         assignments[#assignments + 1] = { ship = candidate, bay = bay }
      else
         local reason = size and "no compatible carrier bay is free"
            or "ship size is unknown"
         violations[#violations + 1] = { ship = candidate, reason = reason }
      end
   end
   return assignments, violations, remaining
end

function policy.audit(carrier, ships)
   if not carrier or type(carrier.bays) ~= "table" then
      return {}, { { reason = "carrier bay configuration is missing" } }, {}
   end
   return policy.match(carrier.bays, ships)
end

function policy.can_store(carrier, stored_ships, candidate)
   if not carrier or not candidate then
      return false, "missing carrier or candidate"
   end
   if carrier.id and candidate.id and candidate.id == carrier.id then
      return false, "the carrier cannot be stored inside itself"
   end
   local fleet = {}
   for _, ship in ipairs(stored_ships or {}) do
      fleet[#fleet + 1] = ship
   end
   fleet[#fleet + 1] = candidate
   local assignments, violations = policy.audit(carrier, fleet)
   for _, violation in ipairs(violations) do
      if violation.ship == candidate then
         return false, violation.reason, violations
      end
   end
   return #assignments == #fleet, violations[1] and violations[1].reason, violations
end

function policy.can_use_command_bay(command_bay, candidate)
   if not candidate then
      return false, "missing command-shuttle replacement"
   end
   if type(candidate.size) ~= "number" then
      return false, "command-shuttle size is unknown"
   end
   if candidate.size > command_bay.max_size then
      return false, "the command shuttle is too large for its dedicated bay"
   end
   return true
end

function policy.usage(bays, assignments)
   local used = {}
   for _, assignment in ipairs(assignments or {}) do
      used[assignment.bay.index] = assignment.ship
   end
   local result = {}
   for index, bay in ipairs(bays or {}) do
      result[#result + 1] = { bay = bay, ship = used[index] }
   end
   return result
end

return policy
