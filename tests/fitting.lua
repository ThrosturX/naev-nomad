package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local config = require "nomad.config"
local fitting = require "nomad.fitting"

-- These baselines contain the current upstream hull, default outfits, Nomad
-- bays, Shuttle Bay, Operational Core, and wormhole generator. Configured
-- cores replace the named upstream core slots below.
local starters = {
   ["Mule"] = {
      mass = 1120, engine_limit = 1400, energy_regen = 23,
      energy_drain = 20,
      slots = {
         engines = { mass = 16, engine_limit = 750, energy_drain = 8 },
         engines_secondary = {
            mass = 4, engine_limit = 650, energy_drain = 12,
         },
      },
   },
   ["Soromid Arx"] = {
      mass = 5310, engine_limit = 5800, energy_regen = 140,
      energy_drain = 56,
   },
   ["Pirate Rhino"] = {
      mass = 1240, engine_limit = 570, energy_regen = 17,
      energy_drain = 15,
      slots = {
         engines = { mass = 30, engine_limit = 570, energy_drain = 15 },
         engines_secondary = {},
         systems = { mass = 100, energy_regen = 17 },
         systems_secondary = {},
      },
   },
}

local outfits = {
   ["Melendez Buffalo Engine"] = {
      primary = { mass = 24, engine_limit = 900, energy_drain = 9 },
      secondary = { mass = 6, engine_limit = 800, energy_drain = 13 },
   },
   ["Unicorp PT-200 Core System"] = {
      primary = { mass = 70, energy_regen = 23 },
      secondary = { mass = 140, energy_regen = 19 },
   },
}

local function difference(replacement, installed)
   return {
      mass = (replacement.mass or 0) - (installed.mass or 0),
      engine_limit = (replacement.engine_limit or 0)
         - (installed.engine_limit or 0),
      energy_regen = (replacement.energy_regen or 0)
         - (installed.energy_regen or 0),
      energy_drain = (replacement.energy_drain or 0)
         - (installed.energy_drain or 0),
   }
end

local function configured_outfits(starter, baseline)
   local result = {}
   for _entry_index, entry in ipairs(starter.core_outfits or {}) do
      local variants = assert(outfits[entry.name],
         "missing fitting stats for " .. entry.name)
      for _slot_index, slot in ipairs(entry.slots) do
         local variant = slot:match("_secondary$")
            and variants.secondary or variants.primary
         assert(variant, entry.name .. " cannot be fitted in " .. slot)
         result[#result + 1] = difference(
            variant, assert(baseline.slots[slot], "unknown core slot " .. slot))
         baseline.slots[slot] = variant
      end
   end
   return result
end

for _starter_index, starter in ipairs(config.starter_carriers) do
   local baseline = assert(starters[starter.hull],
      "missing starter fitting for " .. starter.hull)
   local valid, reason, totals = fitting.validate(
      baseline, configured_outfits(starter, baseline))
   assert(valid, string.format(
      "%s is invalid: %s (mass %.0f / %.0f, energy %.0f)",
      starter.hull, reason or "unknown", totals.mass,
      totals.engine_limit, totals.energy_regen))
end

local valid_mass, mass_reason = fitting.validate({
   mass = 101, engine_limit = 100, energy_regen = 1,
})
assert(not valid_mass and mass_reason == "fitted mass exceeds engine limit",
   "fitting validation must reject mass above the equipped engine limit")

local valid_energy, energy_reason = fitting.validate({
   mass = 100, engine_limit = 100, energy_regen = 5, energy_drain = 5,
})
assert(not valid_energy and energy_reason == "energy regeneration is not positive",
   "fitting validation must require positive energy regeneration after drain")

print("ok - nomad starter fittings")
