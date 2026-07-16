local function cache()
   local shared = naev.cache()
   shared.nomad_bay_tooltips = shared.nomad_bay_tooltips or {}
   return shared.nomad_bay_tooltips
end

local function desired_state(id)
   local shared = naev.cache()
   shared.nomad_bay_states = shared.nomad_bay_states or {}
   return shared.nomad_bay_states[id] == true
end

function descextra(_pilot, _outfit, pilot_outfit)
   if not pilot_outfit then return nil end
   return cache()[pilot_outfit:id()]
end

function init(_pilot, pilot_outfit)
   local shared = naev.cache()
   shared.nomad_bay_states = shared.nomad_bay_states or {}
   shared.nomad_bay_states[pilot_outfit:id()] = false
   pilot_outfit:state("off")
end

function update(_pilot, pilot_outfit)
   pilot_outfit:state(desired_state(pilot_outfit:id()) and "on" or "off")
end

function onadd(_pilot, pilot_outfit)
   naev.trigger("nomad_bay_configuration_changed", {
      id = pilot_outfit:id(),
   })
end

function onremove(_pilot, pilot_outfit)
   local assignments = naev.cache().nomad_bay_assignments or {}
   local assigned = assignments[pilot_outfit:id()]
   if assigned then
      local outfit_name = pilot_outfit:outfit():nameRaw()
      naev.trigger("nomad_occupied_bay_removed", {
         id = pilot_outfit:id(),
         outfit = outfit_name,
         ship = assigned,
         inventory = player.outfitNum(outfit_name),
      })
   end
   naev.trigger("nomad_bay_configuration_changed", {
      id = pilot_outfit:id(),
   })
end

function ontoggle(_pilot, pilot_outfit, on)
   local shared = naev.cache()
   shared.nomad_bay_states = shared.nomad_bay_states or {}
   shared.nomad_bay_states[pilot_outfit:id()] = on == true
   pilot_outfit:state(on and "on" or "off")
   naev.trigger("nomad_bay_activated", {
      outfit = pilot_outfit:outfit():nameRaw(),
      id = pilot_outfit:id(),
      on = on == true,
   })
   return true
end
