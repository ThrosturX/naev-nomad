local wormhole = require "spob.lua.lib.wormhole"
local config = require "nomad.config"

wormhole.setup(spob.get(config.wormhole.source_spob))
local wormhole_land = land

function land(target_spob, subject)
   if subject == player.pilot()
      and subject:shipvarPeek(config.carrier_shipvar) ~= true then
      pcall(naev.trigger, "nomad_wormhole_entering", {
         origin = system.cur():nameRaw(),
      })
   end
   wormhole_land(target_spob, subject)
end
