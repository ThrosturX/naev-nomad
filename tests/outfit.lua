local triggered
local triggers = {}
local states = {}
local progress = {}
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
player = { outfitNum = function() return 2 end }

local outfit = { nameRaw = function() return "Small Ship Bay" end }
local pilot_outfit = {
   id = function() return 7 end,
   outfit = function() return outfit end,
   state = function(_, value) states[#states + 1] = value end,
   progress = function(_, value) progress[#progress + 1] = value end,
}

dofile("outfits/nomad_bay.lua")
assert(descextra(nil, outfit, pilot_outfit) == "Assigned: Needle (Hyena)",
   "an installed control must expose its runtime-only assignment tooltip")
init(nil, pilot_outfit)
assert(states[#states] == "off", "bay controls must initialize off")
assert(ontoggle(nil, pilot_outfit, true), "bay activation must be handled")
assert(triggered.name == "nomad_bay_activated"
   and triggered.payload.outfit == "Small Ship Bay"
   and triggered.payload.id == 7 and triggered.payload.on == true,
   "bay activation must emit its slot and requested state")
assert(states[#states] == "on",
   "a deployed or returning bay control must stay toggled on")
update(nil, pilot_outfit)
assert(states[#states] == "on",
   "the physical control must follow its runtime desired state")

shared.nomad_bay_cooldowns = {
   [7] = { remaining = 5, total = 10 },
}
local trigger_count = #triggers
update(nil, pilot_outfit)
assert(states[#states] == "cooldown" and progress[#progress] == 0.5,
   "a repairing bay must use the native outfit cooldown display")
assert(not ontoggle(nil, pilot_outfit, true) and #triggers == trigger_count
   and states[#states] == "cooldown",
   "activating a cooling bay must not emit a launch request")
shared.nomad_bay_cooldowns[7] = nil
assert(ontoggle(nil, pilot_outfit, false)
   and triggered.payload.on == false and states[#states] == "off",
   "turning the control off must request recall")

onremove(nil, pilot_outfit)
assert(triggers[#triggers - 1].name == "nomad_occupied_bay_removed"
   and triggers[#triggers - 1].payload.id == 7
   and triggers[#triggers - 1].payload.ship.name == "Needle"
   and triggers[#triggers - 1].payload.inventory == 2
   and triggers[#triggers].name == "nomad_bay_configuration_changed",
   "removing an assigned control must request restoration and a policy refresh")

shared.nomad_bay_assignments[7] = nil
triggers = {}
onremove(nil, pilot_outfit)
assert(#triggers == 1 and triggers[1].name == "nomad_bay_configuration_changed",
   "removing an empty control must remain allowed")

local integrated_name = "Nomadic Operational Core"
outfit = { nameRaw = function() return integrated_name end }
triggers = {}
states = {}
dofile("outfits/nomad_integrated.lua")
init(nil, pilot_outfit)
assert(states[#states] == "off",
   "integrated systems must initialize in their one-shot off state")
ontoggle(nil, pilot_outfit, true)
assert(triggered.name == "nomad_integrated_system_activated"
   and triggered.payload.action == "park" and states[#states] == "off",
   "the operational core must trigger carrier parking")
integrated_name = "Shuttle Bay"
ontoggle(nil, pilot_outfit, true)
assert(triggered.name == "nomad_integrated_system_activated"
   and triggered.payload.action == "shuttle",
   "the shuttle bay must trigger command shuttle launch")

print("ok - nomad bay outfit")
