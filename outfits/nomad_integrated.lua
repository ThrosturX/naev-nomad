local actions = {
   ["Nomadic Operational Core"] = "park",
   ["Shuttle Bay"] = "shuttle",
}

function init(_pilot, pilot_outfit)
   pilot_outfit:state("off")
end

function ontoggle(_pilot, pilot_outfit, on)
   pilot_outfit:state("off")
   if not on then return true end
   naev.trigger("nomad_integrated_system_activated", {
      action = actions[pilot_outfit:outfit():nameRaw()],
   })
   return true
end
