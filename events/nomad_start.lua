--[[
<?xml version='1.0' encoding='utf8'?>
<event name="Nomad Start">
 <location>none</location>
</event>
--]]

local config = require "nomad.config"

local utility_size = { Small = 1, Medium = 2, Large = 3 }

local function largest_ordinary_utility(slots)
   local selected
   for index, slot in ipairs(slots or {}) do
      if slot.type == "Utility"
         and (slot.property == nil or slot.property == "")
         and not slot.required and not slot.locked then
         local candidate = {
            id = slot.id or index,
            size = utility_size[slot.size] or 0,
         }
         if not selected or candidate.size > selected.size
            or (candidate.size == selected.size
               and candidate.id < selected.id) then
            selected = candidate
         end
      end
   end
   return selected and selected.id
end

local function apply_starting_flavour(starter)
   if starter.reputation then
      local home = faction.get(starter.reputation.faction)
      home:setKnown(true)
      home:setReputationGlobal(starter.reputation.value)
      require("common.pirate").updateStandings(
         starter.reputation.pirate_value)
   end
   if starter.start_system then
      player.teleport(starter.start_system, true, true)
   end
   if starter.home_spob then spob.get(starter.home_spob):setKnown(true) end
   for _, destination in ipairs(starter.known_jumps or {}) do
      jump.get(starter.start_system, destination):setKnown(true)
   end
end

function create()
   local choice = tk.choice(
      _("Choose Your Nomad Carrier"),
      _("Choose the hull that will become your first home among the stars."),
      _(config.starter_carriers[1].choice),
      _(config.starter_carriers[2].choice),
      _(config.starter_carriers[3].choice)
   )
   local starter = config.starter_carriers[choice]
      or config.starter_carriers[1]

   -- This pilot variable is the campaign boundary. The persistent Nomad event
   -- checks it before loading, leaving pilots created by other scenarios inert.
   var.push(config.active_var, true)
   local carrier_name = player.shipAdd(
      starter.hull,
      starter.name,
      _(starter.acquired),
      true
   )
   player.shipSwap(carrier_name, true, true)
   player.shipvarPush(config.carrier_shipvar, true)
   player.pay(starter.credits - player.credits())
   for _, outfit_name in ipairs(starter.bays or config.starter_bays) do
      if player.pilot():outfitAdd(outfit_name) <= 0 then
         player.outfitAdd(outfit_name, 1)
      end
   end
   local pilot = player.pilot()
   local core_slot = largest_ordinary_utility(pilot:ship():getSlots())
   assert(core_slot, "starter carrier has no utility slot for its Core")
   assert(pilot:outfitAddSlot(config.operational_core, core_slot, true, true),
      "unable to install starter carrier Operational Core")
   for _, system in ipairs(config.integrated_systems) do
      if system.outfit ~= config.operational_core
         and pilot:outfitAdd(system.outfit) <= 0 then
         player.outfitAdd(system.outfit, 1)
      end
   end
   local roster = starter.roster or {}
   for index = 1, #roster do
      local entry = roster[index]
      player.shipAdd(entry.hull, entry.name, _(entry.acquired), true)
   end
   for outfit_name, quantity in pairs(config.spare_bays) do
      player.outfitAdd(outfit_name, quantity)
   end
   apply_starting_flavour(starter)

   -- naev.cache() is process-global. A new pilot created after abandoning a
   -- previous one must not inherit that pilot's unfinished auxiliary sortie.
   naev.cache().joyride = nil
   naev.cache().player_mothership = nil

   -- Run Nomad's replacement for the default new-pilot setup and intro.
   var.push(config.start_chapter_var, starter.chapter or "0")
   naev.eventStart("start_event")
   -- New-player creation does not start ordinary load events. Start the
   -- current pilot's Crewmates event explicitly before Nomad so the public API
   -- cannot resolve a stale provider left in naev.cache() by another pilot.
   naev.eventStart(config.crewmates_event)
   -- Establish the required commander before the first save. Waiting for the
   -- handler's load condition would leave the initial pilot without a
   -- persistent Crewmates roster until the save was loaded again.
   naev.eventStart(config.handler_event)
   evt.finish(true)
end
