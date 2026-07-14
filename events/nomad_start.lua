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
   player.shipvarPush(config.carrier_shipvar, true)
   player.pilot():outfitRm("all")
   for _, outfit_name in ipairs(config.installed_bays) do
      player.pilot():outfitAdd(outfit_name)
   end

   -- Preserve Naev's normal new-pilot setup, intro, and tutorial scheduling.
   naev.eventStart("start_event")
   evt.finish(true)
end
