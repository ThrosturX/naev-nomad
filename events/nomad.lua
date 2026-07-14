--[[
<?xml version='1.0' encoding='utf8'?>
<event name="Nomad Fleet Handler">
 <location>load</location>
 <chance>100</chance>
 <cond>var.peek("nomad_active") == true</cond>
 <unique />
</event>
--]]

local config = require "nomad.config"
local crewmates = require "crewmates.api"
local joyride = require "joyride"
local parking = require "nomad.parking"
local runtime = require "nomad.runtime"

local mothership_pilot
local info_buttons = {}
local escort_hooks = {}
local known_owned = {}
local parking_requested
local parking_sequence = 0
local register_actions
local hooks_installed = false

local function is_carrier(name)
   if name == player.ship() then
      return runtime.is_carrier(player.shipvarPeek(config.carrier_shipvar))
   end
   return runtime.is_carrier(player.shipvarPeek(config.carrier_shipvar, name))
end

local function physical_bay_slots()
   local slots = {}
   for id, outfit in pairs(player.pilot():outfits()) do
      if outfit then
         slots[#slots + 1] = { id = id, outfit = outfit:nameRaw() }
      end
   end
   return slots
end

local function current_bays()
   if not is_carrier(player.ship()) then return {} end
   return runtime.general_bays(physical_bay_slots())
end

local function ship_record(name, ship_type, deployed)
   return {
      name = name,
      hull = ship_type:nameRaw(),
      size = ship_type:size(),
      deployed = deployed == true,
   }
end

local function ordinary_owned_ships()
   local ships = {}
   local seen = {}
   for _, entry in ipairs(player.ships()) do
      seen[entry.name] = true
      if not is_carrier(entry.name) and entry.name ~= mem.nomad.virtual_name then
         ships[#ships + 1] = ship_record(entry.name, entry.ship, entry.deployed)
      end
   end
   local current = player.ship()
   if not seen[current] and not is_carrier(current)
      and current ~= mem.nomad.virtual_name then
      ships[#ships + 1] = ship_record(current, player.pilot():ship(), false)
   end
   return ships
end

local function current_command_shuttle()
   if mem.nomad.active_kind ~= "virtual" then return nil end
   return ship_record(player.ship(), player.pilot():ship(), false)
end

local function audit_now()
   local assignments, violations = runtime.audit_fleet(
      ordinary_owned_ships(), current_bays())
   local command = current_command_shuttle()
   if command then
      local allowed, reason = runtime.audit_command_shuttle(command)
      if not allowed then
         violations[#violations + 1] = { ship = command, reason = reason }
      end
   end
   return assignments, violations
end

local function refresh_bay_tooltips()
   local descriptions = {}
   local assignments_by_slot = {}
   local shared = naev.cache()
   if not is_carrier(player.ship()) then
      shared.nomad_bay_tooltips = descriptions
      shared.nomad_bay_assignments = assignments_by_slot
      return
   end
   local assignments = audit_now()
   local mapped = runtime.map_bay_slots(current_bays(), physical_bay_slots())
   for id, slot in pairs(mapped) do
      local assigned = runtime.ship_for_bay(assignments, slot.index)
      descriptions[id] = runtime.bay_tooltip(assigned)
      assignments_by_slot[id] = assigned
   end
   shared.nomad_bay_tooltips = descriptions
   shared.nomad_bay_assignments = assignments_by_slot
end

local function apply_nojump(violations)
   local pilot = player.pilot()
   if #violations > 0 then
      local flags = pilot:flags()
      if not flags.nojump then
         pilot:setNoJump(true)
         player.shipvarPush(config.nojump_shipvar, true)
      end
   elseif player.shipvarPeek(config.nojump_shipvar) then
      pilot:setNoJump(false)
      player.shipvarPop(config.nojump_shipvar)
   end
end

local function apply_mothership_access(violations)
   if mothership_pilot and mothership_pilot:exists() then
      mothership_pilot:setActiveBoard(#violations == 0)
   end
end

local function apply_carrier_rules()
   if is_carrier(player.ship()) then
      if mem.nomad.parked and player.isLanded() then
         player.landAllow(true)
         mem.nomad.carrier_land_block = nil
      else
         player.landAllow(false,
            _("The carrier cannot land normally. Use Park Carrier from the info menu."))
         mem.nomad.carrier_land_block = true
      end
   elseif mem.nomad.carrier_land_block then
      player.landAllow(true)
      mem.nomad.carrier_land_block = nil
   end
end

local function apply_rules(show_message)
   apply_carrier_rules()
   local _, violations = audit_now()
   apply_nojump(violations)
   apply_mothership_access(violations)
   if show_message and #violations > 0 then
      tk.msg(_("No Compatible Bay"), runtime.violation_message(violations[1]) .. "\n\n"
         .. _("Hyperspace and mothership docking are disabled. Land locally and sell or trade the incompatible hull."))
   end
   refresh_bay_tooltips()
   if register_actions then register_actions() end
   return #violations == 0, violations
end

local function profile()
   local result = {}
   for key, value in pairs(config.joyride_profile) do result[key] = value end
   return result
end

local function find_owned(name)
   for _, entry in ipairs(player.ships()) do
      if entry.name == name then return entry end
   end
end

local function owned_additions(update)
   local additions = {}
   local current = {}
   for _, entry in ipairs(ordinary_owned_ships()) do
      current[entry.name] = true
      if not known_owned[entry.name] then additions[#additions + 1] = entry end
   end
   if update then known_owned = current end
   return additions
end

local function bay_action_message(message)
   if type(player.msg) == "function" then player.msg(message) end
end

local function launch_command_shuttle()
   return crewmates.launch_commander_shuttle(config.joyride_client)
end

function nomad_bay_activated(payload)
   if not payload or not is_carrier(player.ship()) then return end
   local mapped = runtime.map_bay_slots(current_bays(), physical_bay_slots())
   local slot = mapped[payload.id]
   if not slot or slot.bay.outfit ~= payload.outfit then return end
   local assignments = audit_now()
   local assigned = runtime.ship_for_bay(assignments, slot.index)
   if not assigned then
      bay_action_message(string.format(_("Nomad %s Bay: Empty."), slot.bay.name))
      refresh_bay_tooltips()
      return
   end

   if assigned.deployed then
      player.shipDeploy(assigned.name, false, false)
      bay_action_message(string.format(_("Recalling %s (%s)."),
         assigned.name, assigned.hull))
   else
      player.shipDeploy(assigned.name, true, true)
      bay_action_message(string.format(_("Launching %s (%s)."),
         assigned.name, assigned.hull))
   end
   hook.safe("nomad_refresh_after_bay_action")
end

function nomad_launch_command_shuttle()
   if not is_carrier(player.ship()) or player.isLanded() then return end
   local ok, reason = launch_command_shuttle()
   if ok then
      bay_action_message(_("Launching the commander's shuttle."))
   else
      bay_action_message(string.format(_("Command bay: %s"), tostring(reason)))
   end
end

function nomad_refresh_after_bay_action()
   nomad_refresh_escort_hooks()
   apply_rules(false)
end

function nomad_refresh_bay_configuration()
   apply_rules(false)
end

function nomad_bay_configuration_changed()
   hook.safe("nomad_refresh_bay_configuration")
end

function nomad_restore_occupied_bay(payload)
   if not payload or not is_carrier(player.ship()) then return end
   local pilot = player.pilot()
   local installed = pilot:outfits()[payload.id]
   if installed then
      apply_rules(false)
      return
   end
   if not pilot:outfitAddSlot(payload.outfit, payload.id, true, false) then
      tk.msg(_("Bay In Use"), _("The occupied bay control could not be restored."))
      apply_rules(false)
      return
   end
   -- The equipment screen returns the removed control to inventory, while a
   -- direct scripted removal does not. Only balance a copy that appeared
   -- after onremove recorded the prior inventory count.
   local inventory_before = tonumber(payload.inventory)
   if inventory_before and player.outfitNum(payload.outfit) > inventory_before then
      player.outfitRm(payload.outfit, 1)
   end
   local ship = payload.ship or {}
   tk.msg(_("Bay In Use"), string.format(
      _("%s cannot be removed while %s (%s) is assigned to it."),
      payload.outfit, ship.name or _("a ship"), ship.hull or _("unknown hull")))
   apply_rules(false)
end

function nomad_occupied_bay_removed(payload)
   hook.safe("nomad_restore_occupied_bay", payload)
end

function nomad_refresh_escort_hooks()
   if not pilot or type(pilot.get) ~= "function" then return end
   local deployed = {}
   for _, entry in ipairs(ordinary_owned_ships()) do
      if entry.deployed then deployed[entry.name] = true end
   end
   for _, candidate in ipairs(pilot.get()) do
      local name = candidate:name()
      if deployed[name] and not escort_hooks[candidate] then
         escort_hooks[candidate] = hook.pilot(
            candidate, "hail", "nomad_hail_owned", name)
      end
   end
end

function nomad_hail_owned(name)
   hook.safe("nomad_begin_owned_joyride", name)
end

function nomad_begin_owned_joyride(name)
   -- Let Naev finish constructing the hail window before Joyride removes the
   -- deployed pilot. Invalidating it directly in the pilot hail hook makes the
   -- comm backend dereference a pilot that no longer exists.
   player.commClose()
   local entry = find_owned(name)
   if not entry or not entry.deployed then return end
   local ok, reason = joyride.borrow_owned(name, profile())
   if not ok then
      tk.msg(_("Seat Transfer"), tostring(reason))
      return
   end
   mem.nomad.active_kind = "owned"
   apply_rules(false)
   hook.safe("nomad_refresh_escort_hooks")
end

local function next_parking_diff_name()
   parking_sequence = parking_sequence + 1
   return string.format("%s %s %d", config.parking.diff,
      tostring(naev.ticks()), parking_sequence)
end

local function parked_diff_apply(record)
   if diff.isApplied(record.diff) then return true end
   local ok, applied = pcall(diff.newDynamic, parking.diff_xml(record))
   if not ok then return false, applied end
   if not applied then
      return false, _("Naev rejected the temporary parked-carrier location")
   end
   return true
end

local function parked_diff_remove(record)
   local diff_name = record and record.diff
   if diff_name and diff.isApplied(diff_name) then
      diff.remove(diff_name)
   end
   -- Clean up prototype saves created before parking diffs had unique names.
   if diff.isApplied(config.parking.diff) then
      diff.remove(config.parking.diff)
   end
end

local function parking_rollback(reason)
   local record = mem.nomad.parked
   mem.nomad.parked = nil
   parked_diff_remove(record)
   apply_rules(false)
   if reason then tk.msg(_("Unable to Park Carrier"), tostring(reason)) end
end

local function parking_status()
   local pilot = player.pilot()
   local _armour, shield = pilot:health()
   return parking.validate(is_carrier(player.ship()), player.isLanded(), shield)
end

function nomad_complete_parking()
   if not parking_requested then return end
   if tk.isOpen() then
      hook.timer(0.1, "nomad_complete_parking")
      return
   end
   parking_requested = nil

   local ok, reason = parking_status()
   if not ok then
      tk.msg(_("Unable to Park Carrier"), tostring(reason))
      return
   end

   local pilot = player.pilot()
   local position = pilot:pos()
   local x, y = position:get()
   local current_system = system.cur()
   local system_name = current_system:nameRaw()
   local record = parking.record(
      system_name, x, y, pilot:dir(), next_parking_diff_name())
   mem.nomad.parked = record
   ok, reason = parked_diff_apply(record)
   if not ok then
      parking_rollback(reason)
      return
   end

   local target = spob.get(config.parking.spob)
   if not target then
      parking_rollback(_("the parked-carrier landing target is unavailable"))
      return
   end
   player.landAllow(true)
   ok, reason = pcall(player.land, target)
   if not ok then
      parking_rollback(reason)
      return
   end
end

function nomad_park_carrier()
   local ok, reason = parking_status()
   if not ok then
      tk.msg(_("Unable to Park Carrier"), tostring(reason))
      return
   end
   parking_requested = true
   if tk.isOpen() then
      bay_action_message(_("Close the Info window to park the carrier."))
      hook.timer(0.1, "nomad_complete_parking")
      return
   end
   nomad_complete_parking()
end

function nomad_landed()
   -- player.land() completes asynchronously. Never remove the dynamic diff
   -- until this hook confirms that the player is actually landed; doing so
   -- leaves Naev holding an unplaced spob during land window construction.
   if mem.nomad.parked then
      if not player.isLanded() then return end
      local current = spob.cur()
      if not current or current:nameRaw() ~= config.parking.spob then
         parking_rollback(_("the carrier landed at an unexpected location"))
         return
      end
   end
   nomad_apply_rules()
end

function nomad_restore_parked_diff()
   if mem.nomad.parked then
      mem.nomad.parked.diff = mem.nomad.parked.diff
         or next_parking_diff_name()
   else
      parked_diff_remove()
   end
   hook.safe("nomad_initialize")
end

local function restore_carrier_after_takeoff(record)
   parked_diff_remove(record)
   if not record or not is_carrier(player.ship()) then
      nomad_apply_rules()
      return
   end
   local current_system = system.cur()
   if not current_system or current_system:nameRaw() ~= record.system then
      local ok, reason = pcall(player.teleport, record.system, true, true)
      if not ok then
         tk.msg(_("Unable to Restore Carrier Location"), tostring(reason))
         nomad_apply_rules()
         return
      end
   end
   local pilot = player.pilot()
   pilot:setPos(vec2.new(record.x, record.y))
   pilot:setDir(record.direction)
   pilot:setVel(vec2.new(0, 0))
   nomad_apply_rules()
end

function nomad_takeoff()
   if mem.nomad.parked then
      local record = mem.nomad.parked
      mem.nomad.parked = nil
      -- Takeoff hooks run after space has been initialized, so removing the
      -- relocation diff here immediately rebuilds the original system without
      -- leaving the parked carrier as an AI landing target.
      restore_carrier_after_takeoff(record)
      return
   end
   nomad_apply_rules()
end

register_actions = function()
   for _, button in ipairs(info_buttons) do
      player.infoButtonUnregister(button)
   end
   info_buttons = {}
   if is_carrier(player.ship()) and not player.isLanded() then
      info_buttons[#info_buttons + 1] = player.infoButtonRegister(
         _("Launch Shuttle"), nomad_launch_command_shuttle, 2, "H")
      info_buttons[#info_buttons + 1] = player.infoButtonRegister(
         _("Park Carrier"), nomad_park_carrier, 2, "P")
   end
end

function nomad_apply_rules()
   apply_rules(false)
   hook.safe("nomad_refresh_escort_hooks")
end

function nomad_delayed_audit(show_message)
   apply_rules(show_message == true)
end

function nomad_ship_changed()
   hook.safe("nomad_after_ownership_change", false)
end

function nomad_ship_acquired(ship_type, traded)
   if traded and mem.nomad.active_kind == "virtual" then
      mem.nomad.virtual_name = player.ship()
   end
   hook.safe("nomad_finish_acquisition", { ship_type = ship_type, traded = traded })
end

function nomad_after_ownership_change(show_message)
   local fits = apply_rules(show_message == true)
   local additions = owned_additions(true)
   if not fits or mem.nomad.active_kind ~= "virtual" or #additions ~= 1 then return end
   local ok, reason = joyride.handoff_to_owned(additions[1].name)
   if not ok then tk.msg(_("Shuttle Handoff"), tostring(reason)) end
end

function nomad_finish_acquisition(acquisition)
   local fits = apply_rules(true)
   local additions = owned_additions(true)
   if not fits or acquisition.traded or mem.nomad.active_kind ~= "virtual" then return end
   if #additions == 1 then
      local ok, reason = joyride.handoff_to_owned(additions[1].name)
      if not ok then tk.msg(_("Shuttle Handoff"), tostring(reason)) end
   end
end

function nomad_joyride_started(payload)
   runtime.joyride_started(mem.nomad, payload)
   if not payload or payload.client ~= config.joyride_client then return end
   mem.nomad.active_kind = mem.nomad.active_kind or "virtual"
   mem.nomad.virtual_name = player.ship()
   mothership_pilot = payload.pilot
   crewmates.attach_mothership(config.joyride_client, payload.pilot)
   hook.pilot(payload.pilot, "hail", "nomad_hail_mothership")
   hook.safe("nomad_refresh_escort_hooks")
   apply_rules(false)
end

function nomad_shuttle_returned(payload)
   if payload and payload.client == config.joyride_client then
      mem.nomad.active_kind = "owned"
      mem.nomad.virtual_name = nil
      hook.safe("nomad_delayed_audit", false)
   end
end

function nomad_joyride_ended(payload)
   runtime.joyride_ended(mem.nomad, payload)
   if not payload or payload.client ~= config.joyride_client then return end
   mem.nomad.active_kind = nil
   mem.nomad.virtual_name = nil
   mothership_pilot = nil
   crewmates.release_mothership(config.joyride_client)
   apply_rules(false)
end

function nomad_mothership_restored(payload)
   if not payload or payload.client ~= config.joyride_client then return end
   player.shipvarPush(config.carrier_shipvar, true, payload.name)
end

function nomad_hail_mothership()
   if mem.nomad.active_kind ~= "owned" then
      bay_action_message(_(
         "The command shuttle must dock with the carrier to return aboard."))
      return
   end
   local fits, violations = apply_rules(false)
   if not fits then
      tk.msg(_("Docking Refused"), runtime.violation_message(violations[1]) .. "\n\n"
         .. _("Sell or trade the incompatible hull before returning."))
      player.commClose()
      return
   end
   local ok, reason = joyride.end_joyride { redeploy_owned = true }
   if not ok then
      bay_action_message(string.format(_("Seat transfer: %s"), tostring(reason)))
   end
end

local function register_hooks()
   if hooks_installed then return end
   hook.enter("nomad_apply_rules")
   hook.land("nomad_landed")
   hook.takeoff("nomad_takeoff")
   hook.load("nomad_restore_parked_diff")
   hook.ship_swap("nomad_ship_changed")
   hook.ship_buy("nomad_ship_acquired")
   hook.ship_sell("nomad_ship_changed")
   hook.custom("joyride_mothership_spawned", "nomad_joyride_started")
   hook.custom("joyride_shuttle_returned", "nomad_shuttle_returned")
   hook.custom("joyride_mothership_restored", "nomad_mothership_restored")
   hook.custom("joyride_ended", "nomad_joyride_ended")
   hook.custom("nomad_bay_activated", "nomad_bay_activated")
   hook.custom("nomad_bay_configuration_changed",
      "nomad_bay_configuration_changed")
   hook.custom("nomad_occupied_bay_removed", "nomad_occupied_bay_removed")
   hooks_installed = true
end

function nomad_initialize()
   -- Load events run while Naev is still restoring the landed spob. Crewmates
   -- may need that spob when it creates the required commander, so this work
   -- is deliberately deferred to a safe hook after the load transition.
   if not crewmates.is_ready() then
      hook.timer(0.1, "nomad_initialize")
      return
   end
   if player.isLanded() and not spob.cur() then
      hook.timer(0.1, "nomad_initialize")
      return
   end
   assert(crewmates.ensure_commander(config.joyride_client, {
      minimum = config.minimum_crew.commander,
      shuttle = config.starter_subship.hull,
      shuttle_profile = profile(),
   }), "Nomad requires an available commander")
   player.fleetCapacitySet(config.fleet_capacity)
   owned_additions(true)
   register_actions()
   apply_rules(false)
   hook.safe("nomad_refresh_escort_hooks")
end

function nomad_defer_initialize()
   hook.safe("nomad_initialize")
end

function create()
   mem.nomad = runtime.initialize(mem.nomad)
   -- Hooks are runtime state. Install them before either dependency is called
   -- so a transient initialization failure cannot make Naev discard the event.
   register_hooks()
   assert(runtime.joyride_available(), "Nomad requires the extended Joyride API")
   evt.save(true)
   nomad_defer_initialize()
end
