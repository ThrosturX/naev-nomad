local config = require "nomad.config"
local policy = require "nomad.fleet_policy"

local runtime = {}

function runtime.initialize(saved)
   if type(saved) == "table" then
      return saved
   end
   return { version = config.state_version }
end

function runtime.craft_state(saved, name)
   saved.crafts = saved.crafts or {}
   local state = saved.crafts[name]
   if type(state) ~= "table" then
      state = { phase = "ready" }
      saved.crafts[name] = state
   end
   state.phase = state.phase or "ready"
   return state
end

function runtime.return_cooldown(armour_percent, shield_percent, armour_max)
   local lost = math.max(0, tonumber(armour_max) or 0)
      * math.max(0, 100 - (tonumber(armour_percent) or 100)) / 100
   local seconds = math.max(10, lost / 25)
   if (tonumber(shield_percent) or 100) < 90 then
      seconds = math.max(seconds, 15)
   end
   return seconds
end

function runtime.destroyed_cooldown(armour_max)
   return math.max(10, math.max(0, tonumber(armour_max) or 0) / 25)
end

function runtime.tick_cooldown(state, dt)
   if not state or state.phase ~= "cooldown" then return false end
   state.remaining = math.max(0,
      (tonumber(state.remaining) or 0) - math.max(0, tonumber(dt) or 0))
   if state.remaining > 0 then return false end
   state.remaining = nil
   state.cooldown_total = nil
   state.phase = "ready"
   if state.destroyed then
      state.zero_shields = true
      state.destroyed = nil
   else
      if state.snapshot then
         state.snapshot.armour = 100
         state.snapshot.shield = 100
         state.snapshot.stress = 0
         state.snapshot.energy = 100
      end
      state.serviced = true
   end
   return true
end

function runtime.service_craft(state)
   state.phase = "ready"
   state.remaining = nil
   state.cooldown_total = nil
   state.destroyed = nil
   state.zero_shields = nil
   if state.snapshot then
      state.snapshot.armour = 100
      state.snapshot.shield = 100
      state.snapshot.stress = 0
      state.snapshot.energy = 100
   end
   state.serviced = true
end

function runtime.is_carrier(tagged)
   return tagged == true
end

function runtime.audit_fleet(ships, bays)
   return policy.audit({ bays = bays }, ships)
end

local function sorted_bay_slots(physical_slots)
   local sorted = {}
   for _, slot in pairs(physical_slots or {}) do
      if config.general_bays[slot.outfit] then
         sorted[#sorted + 1] = { id = slot.id, outfit = slot.outfit }
      end
   end
   table.sort(sorted, function(left, right) return left.id < right.id end)
   return sorted
end

function runtime.large_bay_points(physical_slots)
   local points = 0
   for _, slot in pairs(physical_slots or {}) do
      if slot.type == "Weapon" and slot.property == "fighter_bay"
         and not slot.locked then
         points = points
            + (config.large_bay_points_by_slot_size[slot.size] or 0)
      end
   end
   return points
end

local function has_fighter_bay_slots(physical_slots)
   for _, slot in pairs(physical_slots or {}) do
      if slot.type == "Weapon" and slot.property == "fighter_bay" then
         return true
      end
   end
   return false
end

function runtime.invalid_bay_slots(physical_slots)
   local core_installed = false
   for _, slot in pairs(physical_slots or {}) do
      if slot.outfit == config.operational_core then core_installed = true end
   end

   local invalid, xl_bays = {}, 0
   local points = 0
   local available_points = runtime.large_bay_points(physical_slots)
   local capacity_known = has_fighter_bay_slots(physical_slots)
   for _, slot in ipairs(sorted_bay_slots(physical_slots)) do
      local cost = config.general_bays[slot.outfit].large_bay_points or 0
      if cost > 0 and (not core_installed
         or (capacity_known and points + cost > available_points)
         or (slot.outfit == "XL Ship Bay" and xl_bays >= 1)) then
         invalid[#invalid + 1] = slot
      else
         points = points + cost
         if slot.outfit == "XL Ship Bay" then xl_bays = xl_bays + 1 end
      end
   end
   return invalid
end

function runtime.general_bays(physical_slots)
   local invalid = {}
   for _, slot in ipairs(runtime.invalid_bay_slots(physical_slots)) do
      invalid[slot.id] = true
   end

   local bays = {}
   for _, slot in ipairs(sorted_bay_slots(physical_slots)) do
      if not invalid[slot.id] then
         local source = config.general_bays[slot.outfit]
         bays[#bays + 1] = {
            name = source.name,
            max_size = source.max_size,
            outfit = source.outfit,
            slot_id = slot.id,
         }
      end
   end
   return bays
end

function runtime.audit_command_shuttle(shuttle)
   return policy.can_use_command_bay(config.command_bay, shuttle)
end

function runtime.carrier_bays(slots)
   return policy.bays_from_slots(slots)
end

function runtime.acquisition_decision(incumbent, stored_ships, candidate,
      candidate_carrier)
   return policy.acquisition_decision(
      incumbent, stored_ships, candidate, candidate_carrier)
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

function runtime.bay_tooltip(ship, craft)
   if not ship then return "Empty" end
   local state = craft and craft.phase or (ship.deployed and "deployed" or "assigned")
   state = state:gsub("^%l", string.upper)
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
