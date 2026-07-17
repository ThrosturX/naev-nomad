local config = require "nomad.config"

local fuel_cost = 600
local energy_cost = 500
local cooldown = 60

local function is_carrier(subject)
   return subject and subject:shipvarPeek(config.carrier_shipvar) == true
end

function descextra(subject, _outfit, _pilot_outfit)
   local costs = string.format(_(
      "Consumes %d fuel and %d GJ of energy per activation. Cooldown: %d seconds."),
      fuel_cost, energy_cost, cooldown)
   if subject and not is_carrier(subject) then
      return _("Can only be fitted to the active Nomad carrier.")
         .. "\n" .. costs
   end
   return costs
end

function init(subject, pilot_outfit)
   if type(mem.timer) == "number" and mem.timer > 0
      and type(mem.cooldown) == "number" and mem.cooldown > 0 then
      pilot_outfit:state("cooldown")
      pilot_outfit:progress(mem.timer / mem.cooldown)
   else
      mem.timer = nil
      mem.cooldown = nil
      pilot_outfit:state("off")
   end
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

function update(_subject, pilot_outfit, dt)
   if mem.timer == nil then return end
   if type(mem.timer) ~= "number" or type(mem.cooldown) ~= "number"
      or mem.cooldown <= 0 then
      mem.timer = nil
      mem.cooldown = nil
      pilot_outfit:state("off")
      return
   end
   mem.timer = mem.timer - dt
   if mem.timer <= 0 then
      mem.timer = nil
      mem.cooldown = nil
      pilot_outfit:state("off")
      pilot_outfit:progress(0)
      return
   end
   pilot_outfit:progress(mem.timer / mem.cooldown)
end

function ontoggle(subject, pilot_outfit, on, natural)
   if not is_carrier(subject) or on ~= true or natural ~= true then
      return false
   end
   if mem.timer and mem.timer > 0 then
      pilot_outfit:state("cooldown")
      return false
   end
   if subject:fuel() < fuel_cost then
      player.msg(_("The Unstable Wormhole Generator requires 600 fuel."))
      pilot_outfit:state("off")
      return false
   end
   if subject:energy(true) < energy_cost then
      player.msg(_("The Unstable Wormhole Generator requires 500 GJ of energy."))
      pilot_outfit:state("off")
      return false
   end

   subject:setFuel(subject:fuel() - fuel_cost)
   subject:addEnergy(-energy_cost)
   mem.cooldown = cooldown * subject:shipstat("cooldown_mod", true)
   mem.timer = mem.cooldown
   pilot_outfit:state("cooldown")
   pilot_outfit:progress(1)
   naev.trigger("nomad_wormhole_generator_activated", {
      id = pilot_outfit:id(),
   })
   return true
end
