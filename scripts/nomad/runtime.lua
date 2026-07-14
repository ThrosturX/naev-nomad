local config = require "nomad.config"
local policy = require "nomad.fleet_policy"
local joyride = require "joyride"

local runtime = {}

function runtime.initialize(saved)
   if type(saved) == "table" then
      return saved
   end
   return { version = config.state_version }
end

function runtime.joyride_available()
   return type(joyride.swap_to_subship) == "function"
      and type(joyride.end_joyride) == "function"
      and type(joyride.handoff_to_owned) == "function"
      and type(joyride.borrow_owned) == "function"
      and type(joyride.launch_owned) == "function"
      and type(joyride.recall_owned) == "function"
end

function runtime.is_carrier(tagged)
   return tagged == true
end

function runtime.audit_fleet(ships, bays)
   return policy.audit({ bays = bays }, ships)
end

function runtime.general_bays(physical_slots)
   local sorted = {}
   for _, slot in pairs(physical_slots or {}) do
      if config.general_bays[slot.outfit] then
         sorted[#sorted + 1] = { id = slot.id, outfit = slot.outfit }
      end
   end
   table.sort(sorted, function(left, right) return left.id < right.id end)

   local bays = {}
   for _, slot in ipairs(sorted) do
      local source = config.general_bays[slot.outfit]
      bays[#bays + 1] = {
         name = source.name,
         max_size = source.max_size,
         outfit = source.outfit,
         slot_id = slot.id,
      }
   end
   return bays
end

function runtime.audit_command_shuttle(shuttle)
   return policy.can_use_command_bay(config.command_bay, shuttle)
end

function runtime.violation_message(violation)
   local candidate = violation and violation.ship or {}
   local hull = candidate.hull or candidate.name or "Unknown hull"
   return string.format("%s has %s.", hull, violation.reason or "no compatible bay")
end

function runtime.map_bay_slots(bays, physical_slots)
   local available = {}
   for _, slot in ipairs(physical_slots or {}) do
      if slot.outfit then
         available[slot.outfit] = available[slot.outfit] or {}
         available[slot.outfit][#available[slot.outfit] + 1] = slot.id
      end
   end
   for _, ids in pairs(available) do table.sort(ids) end

   local used = {}
   local mapped = {}
   for index, bay in ipairs(bays or {}) do
      local offset = (used[bay.outfit] or 0) + 1
      used[bay.outfit] = offset
      local id = available[bay.outfit] and available[bay.outfit][offset]
      if id then
         mapped[id] = { bay = bay, index = index, id = id }
      end
   end
   return mapped
end

function runtime.bay_tooltip(ship)
   if not ship then return "Empty" end
   local state = ship.deployed and "Deployed" or "Assigned"
   return string.format("%s: %s (%s)", state, ship.name, ship.hull)
end

function runtime.ship_for_bay(assignments, bay_index)
   for _, assignment in ipairs(assignments or {}) do
      if assignment.bay.index == bay_index then return assignment.ship end
   end
end

function runtime.joyride_started(state, payload)
   if payload and payload.client == config.joyride_client then
      state.active_sortie = true
   end
   return state
end

function runtime.joyride_ended(state, payload)
   if payload and payload.client == config.joyride_client then
      state.active_sortie = nil
   end
   return state
end

return runtime
