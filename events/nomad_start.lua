--[[
<?xml version='1.0' encoding='utf8'?>
<event name="Nomad Start">
 <location>none</location>
</event>
--]]

local config = require "nomad.config"

function create()
   -- This pilot variable is the campaign boundary. The persistent Nomad event
   -- checks it before loading, leaving pilots created by other scenarios inert.
   var.push(config.active_var, true)
   local carrier_name = player.shipAdd(
      config.carrier.hull,
      config.carrier.name,
      _(config.carrier.acquired),
      true
   )
   player.shipSwap(carrier_name, true, true)
   player.shipvarPush(config.carrier_shipvar, true)
   for _, outfit_name in ipairs(config.starter_bays) do
      if player.pilot():outfitAdd(outfit_name) <= 0 then
         player.outfitAdd(outfit_name, 1)
      end
   end
   for outfit_name, quantity in pairs(config.spare_bays) do
      player.outfitAdd(outfit_name, quantity)
   end

   -- Preserve Naev's normal new-pilot setup, intro, and tutorial scheduling.
   naev.eventStart("start_event")
   -- The vanilla start event equips a tutorial laser on the current pilot.
   -- Nomad has already replaced the bootstrap ship at this point, so remove
   -- bootstrap-only equipment after that event has finished initializing.
   for _, outfit_name in ipairs(config.bootstrap.cleanup_outfits) do
      player.pilot():outfitRm(outfit_name, 1)
   end
   -- New-player creation does not start ordinary load events. Start the
   -- current pilot's Crewmates event explicitly before Nomad so the public API
   -- cannot resolve a stale provider left in naev.cache() by another pilot.
   naev.eventStart(config.crewmates_event)
   -- Establish the required commander before the first save. Waiting for the
   -- handler's load condition would leave the initial pilot without a
   -- persistent Crewmates roster until the save was loaded again.
   naev.eventStart(config.handler_event)
   evt.finish(true)
end
