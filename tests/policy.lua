package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local policy = require "nomad.fleet_policy"
local config = require "nomad.config"
local retrofit = require "nomad.retrofit"
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

local candidate_bays = policy.bays_from_slots({
   { id = 1, type = "Weapon", size = "Small", property = "fighter_bay" },
   { id = 2, type = "Weapon", size = "Medium", property = "fighter_bay" },
   { id = 3, type = "Weapon", size = "Large", property = "fighter_bay" },
   { id = 4, type = "Weapon", size = "Large", property = "fighter_bay",
      locked = true },
   { id = 5, type = "Weapon", size = "Large" },
})
assert(#candidate_bays == 3 and candidate_bays[1].max_size == 2
   and candidate_bays[2].max_size == 4
   and candidate_bays[3].max_size == 6,
   "candidate carrier capacity must derive from unlocked fighter-bay slots")

local incumbent = { id = "old", name = "Old Carrier", size = 3,
   bays = { { name = "S", max_size = 2 } } }
local candidate = { id = "new", name = "New Ship", size = 2 }
local decision = policy.acquisition_decision(incumbent, {}, candidate, nil)
assert(decision.action == "store",
   "a compatible purchase must remain an ordinary stored ship")

candidate.size = 6
local replacement = { id = "new", name = "New Carrier", size = 6,
   bays = {
      { name = "XL", max_size = 6 },
      { name = "M", max_size = 4 },
   } }
decision = policy.acquisition_decision(incumbent,
   { { name = "Escort", size = 2 } }, candidate, replacement)
assert(decision.action == "replace" and decision.retain_incumbent == true,
   "a larger carrier must retain the incumbent when every ship fits")

replacement.bays = { { name = "M", max_size = 4 } }
decision = policy.acquisition_decision(incumbent,
   { { name = "Escort", size = 2 } }, candidate, replacement)
assert(decision.action == "replace" and decision.retain_incumbent == false,
   "carrier replacement must refund an incumbent that cannot be retained")

replacement.bays = { { name = "S", max_size = 2 } }
decision = policy.acquisition_decision(incumbent,
   { { name = "Escort", size = 2 }, { name = "Second", size = 2 } },
   candidate, replacement)
assert(decision.action == "refund",
   "a purchase that is neither storable nor a viable carrier must be refunded")

local usage = policy.usage(bays, assignments)
assert(#usage == 4 and usage[1].ship.name == "XL"
   and usage[2].ship.name == "M",
   "bay usage must be reportable without persisting assignments")

local arx = config.starter_carriers[2]
local arx_bays = {}
for _, outfit_name in ipairs(arx.bays) do
   arx_bays[#arx_bays + 1] = {
      name = config.general_bays[outfit_name].name,
      max_size = config.general_bays[outfit_name].max_size,
   }
end
assignments, violations = policy.audit({ bays = arx_bays }, arx.roster)
assert(#assignments == #arx.roster and #violations == 0,
   "every ship granted by the Arx start must fit its installed bay controls")

local systems = retrofit.allocate({
   { id = 1, type = "Utility", size = "Medium" },
   { id = 2, type = "Utility", size = "Large" },
}, {}, config.integrated_systems)
assert(#systems == 2 and systems[1].id == 2 and systems[2].id == 1,
   "carrier conversion must reserve large and medium utility slots")

print("ok - nomad fleet policy")
