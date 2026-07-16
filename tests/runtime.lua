package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path
local runtime = require "nomad.runtime"
local config = require "nomad.config"
local state = runtime.initialize()
assert(state.version == 0, "prototype state must remain at version zero")
assert(state.carrier == nil and state.stored_ships == nil,
   "runtime state must not persist bay assignments or virtual shuttles")
assert(runtime.is_carrier(true) and not runtime.is_carrier(false),
   "only the stable ship tag identifies the carrier")

local configured_bays = runtime.general_bays {
   { id = 8, outfit = "Small Ship Bay" },
   { id = 3, outfit = "Medium Ship Bay" },
   { id = 1, outfit = "Laser Cannon MK1" },
}
assert(#configured_bays == 2 and configured_bays[1].name == "M"
   and configured_bays[1].slot_id == 3 and configured_bays[2].name == "S",
   "general bays must be derived from installed controls in physical slot order")

local invalid = runtime.invalid_bay_slots {
   { id = 1, outfit = "Large Ship Bay" },
   { id = 2, outfit = "Large Ship Bay" },
   { id = 3, outfit = "XL Ship Bay" },
   { id = 4, outfit = config.operational_core },
}
assert(#invalid == 1 and invalid[1].id == 3,
   "two L bays must consume the entire large-bay budget")
invalid = runtime.invalid_bay_slots {
   { id = 1, outfit = "XL Ship Bay" },
   { id = 2, outfit = "Large Ship Bay" },
   { id = 3, outfit = config.operational_core },
}
assert(#invalid == 1 and invalid[1].id == 2,
   "one XL bay must consume the entire large-bay budget")
invalid = runtime.invalid_bay_slots {
   { id = 1, outfit = "Large Ship Bay" },
}
assert(#invalid == 1 and invalid[1].id == 1,
   "L and XL bays must require the operational core")

local assignments, violations = runtime.audit_fleet({
   { hull = "Admonisher", size = 4 }, { hull = "Shark", size = 2 },
}, configured_bays)
assert(#assignments == 2 and #violations == 0,
   "runtime auditing must use the currently installed general bays")
assignments, violations = runtime.audit_fleet({
   { hull = "Goddard", size = 6 }, { hull = "Kestrel", size = 5 },
   { hull = "Shark", size = 2 }, { hull = "Alpaca", size = 1 },
}, configured_bays)
assert(#assignments == 2 and #violations == 2,
   "uninstalled bay sizes must provide no carrier storage capacity")
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
   { name = "S", outfit = "Small Ship Bay" },
   { name = "S", outfit = "Small Ship Bay" },
}, {
   { id = 9, outfit = "Small Ship Bay" },
   { id = 3, outfit = "Small Ship Bay" },
})
assert(mapped[3].index == 1 and mapped[9].index == 2,
   "identical S controls must map to logical bays by sorted physical slot ID")
assert(runtime.bay_tooltip() == "Empty"
   and runtime.bay_tooltip({ name = "Needle", hull = "Hyena" })
      == "Assigned: Needle (Hyena)"
   and runtime.bay_tooltip({ name = "Needle", hull = "Hyena", deployed = true })
      == "Deployed: Needle (Hyena)",
   "bay tooltips must distinguish empty, assigned, and deployed states")

assert(runtime.return_cooldown(99, 100, 1000) == 10,
   "light armour damage must still require docking time")
assert(runtime.return_cooldown(50, 100, 1000) == 20,
   "repair time must use absolute armour points lost")
assert(runtime.return_cooldown(100, 89, 1000) == 15,
   "depleted shields must impose the shield turnaround floor")
assert(runtime.destroyed_cooldown(1000) == 40,
   "destroyed craft rebuilding must scale with maximum armour")
local cooling = {
   phase = "cooldown", remaining = 1, cooldown_total = 10,
   destroyed = true,
}
assert(runtime.tick_cooldown(cooling, 1)
   and cooling.phase == "ready" and cooling.zero_shields == true
   and cooling.cooldown_total == nil,
   "destroyed replacements must unlock with zero shields")

print("ok - nomad runtime state")
