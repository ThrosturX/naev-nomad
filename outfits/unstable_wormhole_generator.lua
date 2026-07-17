local config = require "nomad.config"

local function is_carrier(subject)
   return subject and subject:shipvarPeek(config.carrier_shipvar) == true
end

function descextra(subject, _outfit, _pilot_outfit)
   if subject and not is_carrier(subject) then
      return _("Can only be fitted to the active Nomad carrier.")
   end
end

function init(subject, pilot_outfit)
   pilot_outfit:state("off")
   if not is_carrier(subject) then
      naev.trigger("nomad_invalid_wormhole_generator", {
         pilot = subject,
         id = pilot_outfit:id(),
      })
   end
end

function onadd(subject, pilot_outfit)
   if is_carrier(subject) then return end
   naev.trigger("nomad_invalid_wormhole_generator", {
      pilot = subject,
      id = pilot_outfit:id(),
   })
end

function ontoggle(subject, pilot_outfit, on, natural)
   pilot_outfit:state("off")
   if not is_carrier(subject) or on ~= true or natural ~= true then
      return false
   end
   naev.trigger("nomad_wormhole_generator_activated", {
      id = pilot_outfit:id(),
   })
   return false
end
