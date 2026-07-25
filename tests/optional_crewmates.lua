package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local attempts = 0
package.preload["crewmates.api"] = function()
   attempts = attempts + 1
   error("Crewmates is unavailable")
end

local optional = require "nomad.optional_crewmates"
assert(optional.api == nil and attempts == 1,
   "the optional loader must turn one failed cold-path require into absence")
assert(require("nomad.optional_crewmates") == optional and attempts == 1,
   "the optional loader must cache absence instead of probing hot paths")

package.loaded["nomad.optional_crewmates"] = nil
package.loaded["crewmates.api"] = nil
package.preload["crewmates.api"] = function()
   attempts = attempts + 1
   return { is_ready = function() return true end }
end
optional = require "nomad.optional_crewmates"
assert(optional.api and optional.api.is_ready() and attempts == 2,
   "the optional loader must expose the unmodified public API when present")

print("ok - optional Crewmates loader")
