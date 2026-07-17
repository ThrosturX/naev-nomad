local actions = {
   ["Nomadic Operational Core"] = "park",
   ["Shuttle Bay"] = "shuttle",
}

local core_passive_stats = {
   armour_regen = 1,
   shield_mod = 200,
   ew_hide = -60,
   ew_stealth = -60,
   ew_stealth_min = -60,
}

local function apply_state(pilot_outfit)
   local shared = naev.cache()
   local states = shared.nomad_integrated_states or {}
   local id = pilot_outfit:id()
   local state = states[id]
   if state == "arming" then
      pilot_outfit:state("on")
      states[id] = "armed"
   elseif state == "off" or not state then
      pilot_outfit:state("off")
   end
end

function init(subject, pilot_outfit)
   local action = actions[pilot_outfit:outfit():nameRaw()]
   -- Lua stats are applied independently of a toggleable modification's
   -- native on/off state. Keep all Core bonuses passive while using that
   -- native state only to represent an active parking request.
   if action == "park" then
      for stat, value in pairs(core_passive_stats) do
         pilot_outfit:set(stat, value)
      end
   end
   if subject ~= player.pilot() then return end
   if action == "park" then
      local shared = naev.cache()
      local choices = shared.nomad_parking_core_choices
      if choices then choices[pilot_outfit:id()] = nil end
   end
   apply_state(pilot_outfit)
end

function update(subject, pilot_outfit)
   if subject ~= player.pilot() then return end
   apply_state(pilot_outfit)
end

function onadd(subject, pilot_outfit)
   if subject ~= player.pilot() then return end
   naev.trigger("nomad_bay_configuration_changed", {
      id = pilot_outfit:id(),
   })
end

function onremove(subject, pilot_outfit)
   if subject ~= player.pilot() then return end
   naev.trigger("nomad_bay_configuration_changed", {
      id = pilot_outfit:id(),
   })
end

function ontoggle(subject, pilot_outfit, on, natural)
   if subject ~= player.pilot() then return false end
   local id = pilot_outfit:id()
   local action = actions[pilot_outfit:outfit():nameRaw()]
   if not action or type(on) ~= "boolean" or natural ~= true then
      return false
   end
   -- Naev passes natural=false for automatic shutdowns such as landing and
   -- hyperspace. Those are not player parking choices.
   local shared = naev.cache()
   local state = shared.nomad_integrated_states
      and shared.nomad_integrated_states[id]
   if action == "park" then
      if on == false and (state == "arming" or state == "armed") then
         local guards = shared.nomad_parking_bay_guards
         if guards and guards[id] then
            guards[id] = nil
            return false
         end
      end
      shared.nomad_parking_core_choices =
         shared.nomad_parking_core_choices or {}
      shared.nomad_parking_core_choices[id] = on
   end
   if state == "arming" or state == "armed" then
      return true
   end
   pilot_outfit:state("off")
   if not on then return true end
   naev.trigger("nomad_integrated_system_activated", {
      action = action,
      id = id,
   })
   apply_state(pilot_outfit)
   return true
end
