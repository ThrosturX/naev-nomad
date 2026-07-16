local wormhole = require "spob.lua.lib.wormhole"

wormhole.setup(function()
   local candidates = {}
   for _, candidate in ipairs(spob.getAll()) do
      if candidate ~= mem.spob and candidate:tags().wormhole then
         candidates[#candidates + 1] = candidate
      end
   end
   return candidates[rnd.rnd(1, #candidates)]
end)
