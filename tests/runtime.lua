package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path
package.preload.joyride = function()
   return {
      swap_to_subship = function() end, end_joyride = function() end,
      handoff_to_owned = function() end, borrow_owned = function() end,
      launch_owned = function() end, recall_owned = function() end,
   }
end

local runtime = require "nomad.runtime"
local state = runtime.initialize()
assert(state.version == 0, "prototype state must remain at version zero")
assert(state.carrier == nil and state.stored_ships == nil,
   "runtime state must not persist bay assignments or virtual shuttles")
assert(runtime.joyride_available(), "the extended Joyride API must be detected")
assert(runtime.is_carrier(true) and not runtime.is_carrier(false),
   "only the stable ship tag identifies the carrier")

local assignments, violations = runtime.audit_fleet {
   { hull = "Goddard", size = 6 }, { hull = "Kestrel", size = 5 },
   { hull = "Shark", size = 2 }, { hull = "Alpaca", size = 1 },
}
assert(#assignments == 4 and #violations == 0,
   "runtime auditing must use the configured fixed general bays")
local command_ok = runtime.audit_command_shuttle({ hull = "Shark", size = 2 })
assert(command_ok, "a Shark must fit the S command bay")
command_ok = runtime.audit_command_shuttle({ hull = "Llama", size = 3 })
assert(not command_ok, "a size-3 shuttle must exceed the command bay")

local saved = { version = 0, marker = "unchanged" }
assert(runtime.initialize(saved) == saved,
   "version-zero saves must be returned unchanged without migration")
runtime.joyride_started(state, { client = "TXCrewmates" })
assert(not state.active_sortie, "unrelated Joyride clients must remain independent")
runtime.joyride_started(state, { client = "nomad" })
assert(state.active_sortie, "Nomad sorties must be tracked")
runtime.joyride_ended(state, { client = "nomad" })
assert(not state.active_sortie, "returning must clear the transient sortie flag")

local mapped = runtime.map_bay_slots({
   { name = "S", outfit = "Nomad S Bay" },
   { name = "S", outfit = "Nomad S Bay" },
}, {
   { id = 9, outfit = "Nomad S Bay" },
   { id = 3, outfit = "Nomad S Bay" },
})
assert(mapped[3].index == 1 and mapped[9].index == 2,
   "identical S controls must map to logical bays by sorted physical slot ID")
assert(runtime.bay_tooltip() == "Empty"
   and runtime.bay_tooltip({ name = "Needle", hull = "Hyena" })
      == "Assigned: Needle (Hyena)"
   and runtime.bay_tooltip({ name = "Needle", hull = "Hyena", deployed = true })
      == "Deployed: Needle (Hyena)",
   "bay tooltips must distinguish empty, assigned, and deployed states")

print("ok - nomad runtime state")
