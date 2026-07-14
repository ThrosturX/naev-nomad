package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local policy = require "nomad.fleet_policy"
local config = require "nomad.config"
assert(config.bay_classes.S == 2 and config.bay_classes.M == 4
   and config.bay_classes.L == 5 and config.bay_classes.XL == 6,
   "S, M, L, and XL must use the specified Naev hull-size limits")
local bays = {
   { name = "XL", max_size = 6 },
   { name = "L", max_size = 5 },
   { name = "S", max_size = 2 },
   { name = "S", max_size = 2 },
}
local carrier = { id = "carrier", bays = bays }

local assignments, violations = policy.audit(carrier, {
   { name = "Light", hull = "Hyena", size = 1 },
   { name = "Super-heavy", hull = "Goddard", size = 6 },
   { name = "Heavy", hull = "Kestrel", size = 5 },
   { name = "Medium", hull = "Admonisher", size = 4 },
})
assert(#assignments == 3 and #violations == 1
   and violations[1].ship.name == "Medium",
   "mixed fleets must be matched largest-first into fixed bays")
assert(assignments[1].bay.name == "XL"
   and assignments[2].bay.name == "L"
   and assignments[3].bay.name == "S",
   "each ship must use the smallest compatible remaining bay")

assignments, violations = policy.audit(carrier, {
   { name = "S1", size = 2 }, { name = "S2", size = 1 },
   { name = "M", size = 4 }, { name = "XL", size = 6 },
})
assert(#assignments == 4 and #violations == 0,
   "the XL, L, and two S bays must accept a full compatible fleet")

local fits = policy.can_store(carrier, {
   { name = "S1", size = 2 }, { name = "L", size = 5 },
}, { name = "XL", size = 6 })
assert(fits, "a new ship must fit when a compatible bay remains")

local itself, itself_reason = policy.can_store(carrier, {}, {
   id = "carrier", hull = "Arx", size = 6,
})
assert(not itself and itself_reason:find("itself"),
   "the tagged carrier must never consume one of its own bays")

local full, full_reason = policy.can_store(carrier, {
   { name = "XL", size = 6 }, { name = "L", size = 5 },
   { name = "S1", size = 2 }, { name = "S2", size = 2 },
}, { name = "Extra", size = 1 })
assert(not full and full_reason:find("no compatible"),
   "a fifth ordinary ship must be rejected")

assert(policy.can_use_command_bay({ max_size = 2 }, { hull = "Alpaca", size = 1 }))
assert(policy.can_use_command_bay({ max_size = 2 }, { hull = "Shark", size = 2 }))
local command_ok, command_reason = policy.can_use_command_bay(
   { max_size = 2 }, { hull = "Llama", size = 3 })
assert(not command_ok and command_reason:find("too large"),
   "oversized virtual replacements must not fit the dedicated command bay")

local usage = policy.usage(bays, assignments)
assert(#usage == 4 and usage[1].ship.name == "XL"
   and usage[2].ship.name == "M",
   "bay usage must be reportable without persisting assignments")

print("ok - nomad fleet policy")
