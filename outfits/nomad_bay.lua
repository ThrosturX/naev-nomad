local function cache()
   local shared = naev.cache()
   shared.nomad_bay_tooltips = shared.nomad_bay_tooltips or {}
   return shared.nomad_bay_tooltips
end

function descextra(_pilot, _outfit, pilot_outfit)
   if not pilot_outfit then return nil end
   return cache()[pilot_outfit:id()]
end

function init(_pilot, pilot_outfit)
   pilot_outfit:state("off")
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
   pilot_outfit:state("off")
   if not on then return true end
   naev.trigger("nomad_bay_activated", {
      outfit = pilot_outfit:outfit():nameRaw(),
      id = pilot_outfit:id(),
   })
   pilot_outfit:state("off")
   return true
end
