local triggered
local triggers = {}
local states = {}
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

local outfit = { nameRaw = function() return "Nomad S Bay" end }
local pilot_outfit = {
   id = function() return 7 end,
   outfit = function() return outfit end,
   state = function(_, value) states[#states + 1] = value end,
}

dofile("outfits/nomad_bay.lua")
assert(descextra(nil, outfit, pilot_outfit) == "Assigned: Needle (Hyena)",
   "an installed control must expose its runtime-only assignment tooltip")
init(nil, pilot_outfit)
assert(states[#states] == "off", "bay controls must initialize off")
assert(ontoggle(nil, pilot_outfit, true), "bay activation must be handled")
assert(triggered.name == "nomad_bay_activated"
   and triggered.payload.outfit == "Nomad S Bay"
   and triggered.payload.id == 7,
   "bay activation must emit raw outfit name and physical slot ID")
assert(states[#states] == "off",
   "a one-shot activation must leave its outfit toggled off")

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

print("ok - nomad bay outfit")
