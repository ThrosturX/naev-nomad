package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local triggered
local triggers = {}
local states = {}
local progress = {}
local lua_stats = {}
local shared = {
   nomad_bay_tooltips = { [7] = "Assigned: Needle (Hyena)" },
   nomad_bay_assignments = {
      [7] = { name = "Needle", hull = "Hyena" },
   },
}
naev = {
   cache = function() return shared end,
   trigger = function(name, payload)
      triggered = { name = name, payload = payload }
      triggers[#triggers + 1] = triggered
   end,
}
_ = function(text) return text end
local player_pilot = {}
player = {
   outfitNum = function() return 2 end,
   pilot = function() return player_pilot end,
}

local outfit = { nameRaw = function() return "Small Ship Bay" end }
local pilot_outfit = {
   id = function() return 7 end,
   outfit = function() return outfit end,
   state = function(_, value) states[#states + 1] = value end,
   set = function(_, name, value) lua_stats[name] = value end,
   progress = function(_, value) progress[#progress + 1] = value end,
}

dofile("outfits/nomad_bay.lua")
assert(descextra(player_pilot, outfit, pilot_outfit) == "Assigned: Needle (Hyena)",
   "an installed control must expose its runtime-only assignment tooltip")
init(player_pilot, pilot_outfit)
assert(states[#states] == "off", "bay controls must initialize off")
onadd(player_pilot, pilot_outfit)
assert(triggered.name == "nomad_bay_configuration_changed"
   and triggered.payload.id == 7,
   "adding a bay control must request capacity validation")
assert(ontoggle(player_pilot, pilot_outfit, true, true),
   "bay activation must be handled")
assert(triggered.name == "nomad_bay_activated"
   and triggered.payload.outfit == "Small Ship Bay"
   and triggered.payload.id == 7 and triggered.payload.on == true,
   "bay activation must emit its slot and requested state")
assert(states[#states] == "on",
   "a deployed or returning bay control must stay toggled on")
update(player_pilot, pilot_outfit)
assert(states[#states] == "on",
   "the physical control must follow its runtime desired state")

shared.nomad_bay_cooldowns = {
   [7] = { remaining = 5, total = 10 },
}
local trigger_count = #triggers
update(player_pilot, pilot_outfit)
assert(states[#states] == "cooldown" and progress[#progress] == 0.5,
   "a repairing bay must use the native outfit cooldown display")
assert(not ontoggle(player_pilot, pilot_outfit, true, true)
   and #triggers == trigger_count
   and states[#states] == "cooldown",
   "activating a cooling bay must not emit a launch request")
shared.nomad_bay_cooldowns[7] = nil
assert(ontoggle(player_pilot, pilot_outfit, false, true)
   and triggered.payload.on == false and states[#states] == "off",
   "turning the control off must request recall")

onremove(player_pilot, pilot_outfit)
assert(triggers[#triggers - 1].name == "nomad_occupied_bay_removed"
   and triggers[#triggers - 1].payload.id == 7
   and triggers[#triggers - 1].payload.ship.name == "Needle"
   and triggers[#triggers - 1].payload.inventory == 2
   and triggers[#triggers].name == "nomad_bay_configuration_changed",
   "removing an assigned control must request restoration and a policy refresh")

shared.nomad_bay_assignments[7] = nil
triggers = {}
onremove(player_pilot, pilot_outfit)
assert(#triggers == 1 and triggers[1].name == "nomad_bay_configuration_changed",
   "removing an empty control must remain allowed")

local integrated_name = "Nomadic Operational Core"
outfit = { nameRaw = function() return integrated_name end }
triggers = {}
states = {}
dofile("outfits/nomad_integrated.lua")
init(player_pilot, pilot_outfit)
assert(states[#states] == "off" and lua_stats.armour_regen == 1
   and lua_stats.mass_mod == 100 and lua_stats.shield_mod == 200
   and lua_stats.ew_hide == -80 and lua_stats.ew_stealth == -80
   and lua_stats.ew_stealth_min == -80,
   "the Core must initialize off with all bonuses passive")
ontoggle(player_pilot, pilot_outfit, true, true)
assert(triggered.name == "nomad_integrated_system_activated"
   and triggered.payload.action == "park" and triggered.payload.id == 7
   and states[#states] == "off",
   "the operational core must trigger carrier parking")
shared.nomad_integrated_states = { [7] = true }
shared.nomad_integrated_states[7] = "arming"
update(player_pilot, pilot_outfit)
assert(states[#states] == "on" and shared.nomad_integrated_states[7] == "armed",
   "parking must set the operational core on once after activation")
assert(shared.nomad_parking_core_choices[7] == true,
   "arming must retain the player's enabled Core choice")
assert(not ontoggle(player_pilot, pilot_outfit, false, false),
   "automatic engine toggles must not be treated as native Core input")
assert(shared.nomad_parking_core_choices[7] == true,
   "automatic engine toggles must not cancel parking")
assert(not ontoggle(player_pilot, pilot_outfit, "off", true),
   "malformed Core toggle arguments must be rejected")
assert(ontoggle(player_pilot, pilot_outfit, false, true),
   "the operational core must allow its native state to be toggled while parking")
assert(shared.nomad_parking_core_choices[7] == false,
   "a native Core-off toggle must record the parking cancellation")
shared.nomad_integrated_states[7] = "arming"
update(player_pilot, pilot_outfit)
assert(states[#states] == "on",
   "arming updates must restore the Core's rendered native state")
shared.nomad_integrated_states[7] = "off"
onremove(player_pilot, pilot_outfit)
onadd(player_pilot, pilot_outfit)
init(player_pilot, pilot_outfit)
assert(states[#states] == "off",
   "post-return Core initialization must reset its native state")
local triggers_before_returned_core = #triggers
ontoggle(player_pilot, pilot_outfit, true, true)
assert(#triggers == triggers_before_returned_core + 1
   and triggered.payload.action == "park",
   "the restored Core must start parking on its first toggle after a shuttle swap")
shared.nomad_integrated_states[7] = "off"
integrated_name = "Shuttle Bay"
ontoggle(player_pilot, pilot_outfit, true, true)
assert(triggered.name == "nomad_integrated_system_activated"
   and triggered.payload.action == "shuttle",
   "the shuttle bay must trigger command shuttle launch")

local carrier_pilot = {
   shipvarPeek = function(_self, key)
      return key == "nomad_carrier"
   end,
}
local ordinary_pilot = {
   shipvarPeek = function() return false end,
}
outfit = { nameRaw = function() return "Unstable Wormhole Generator" end }
dofile("outfits/unstable_wormhole_generator.lua")
states = {}
init(carrier_pilot, pilot_outfit)
assert(states[#states] == "off",
   "the wormhole generator must initialize as an off one-shot control")
local wormhole_trigger_count = #triggers
assert(not ontoggle(carrier_pilot, pilot_outfit, true, true)
   and #triggers == wormhole_trigger_count + 1
   and triggered.name == "nomad_wormhole_generator_activated"
   and triggered.payload.id == 7 and states[#states] == "off",
   "a natural carrier activation must request one wormhole and remain off")
wormhole_trigger_count = #triggers
assert(not ontoggle(ordinary_pilot, pilot_outfit, true, true)
   and #triggers == wormhole_trigger_count,
   "a non-carrier pilot must not activate the generator")
onadd(ordinary_pilot, pilot_outfit)
assert(triggered.name == "nomad_invalid_wormhole_generator"
   and triggered.payload.pilot == ordinary_pilot
   and descextra(ordinary_pilot, outfit, pilot_outfit):find("only"),
   "fitting the generator to a non-carrier must request explicit rejection")

print("ok - nomad bay outfit")
