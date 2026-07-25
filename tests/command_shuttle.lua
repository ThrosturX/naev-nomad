package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

package.preload["bioship.skills"] = function()
   return {
      set = {
         instinct = {
            ["hunting instinct"] = {},
            ["pack sense"] = {},
         },
      },
   }
end

local command_shuttle = require "nomad.command_shuttle"

local saved = command_shuttle.ensure(nil, "Alpaca")
assert(saved.hull == "Alpaca",
   "a fallback shuttle must begin with the carrier's configured hull")
local profile = command_shuttle.profile({
   client = "nomad",
   landable = true,
}, saved)
local shipvars = {}
for _, name in ipairs(profile.shipvars) do shipvars[name] = true end
assert(profile.client == "nomad" and profile.landable == true
   and profile.persist_virtual_state == true
   and shipvars.bioship and shipvars.bioshipexp
   and shipvars["bio_hunting instinct"] and shipvars["bio_pack sense"],
   "fallback profiles must preserve fittings and every bioship progression key")

local snapshot = {
   hull = "Pirate Hyena",
   outfits = { slots = { [1] = "Light Combat Plating" } },
   shipvars = { bioshipexp = 42 },
}
saved = command_shuttle.record(saved, {
   hull = "Pirate Hyena",
   virtual_state = snapshot,
})
assert(saved.hull == "Pirate Hyena" and saved.virtual_state == snapshot,
   "returned Joyride state must retain a legal replacement hull and fittings")
assert(command_shuttle.profile({}, saved).virtual_state == snapshot,
   "the next launch must restore the exact plain Joyride snapshot")
saved.virtual_state = { invalid = function() end }
command_shuttle.ensure(saved, "Alpaca")
assert(saved.virtual_state == nil,
   "fallback state validation must discard non-persistent runtime values")

print("ok - fallback command shuttle")
