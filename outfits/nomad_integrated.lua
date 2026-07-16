local actions = {
   ["Nomadic Operational Core"] = "park",
   ["Shuttle Bay"] = "shuttle",
}

function init(subject, pilot_outfit)
   if subject ~= player.pilot() then return end
   pilot_outfit:state("off")
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

function ontoggle(subject, pilot_outfit, on)
   if subject ~= player.pilot() then return false end
   pilot_outfit:state("off")
   if not on then return true end
   naev.trigger("nomad_integrated_system_activated", {
      action = actions[pilot_outfit:outfit():nameRaw()],
   })
   return true
end
