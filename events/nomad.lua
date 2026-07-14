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
local fmt = require "format"
local joyride = require "joyride"
local policy = require "nomad.fleet_policy"
local runtime = require "nomad.runtime"

local mothership_pilot
local info_button
local escort_hooks = {}
local known_owned = {}

local function is_carrier(name)
   if name == player.ship() then
      return runtime.is_carrier(player.shipvarPeek(config.carrier_shipvar))
   end
   return runtime.is_carrier(player.shipvarPeek(config.carrier_shipvar, name))
end

local function desired_bay_counts()
   local counts = {}
   for _, name in ipairs(config.installed_bays) do
      counts[name] = (counts[name] or 0) + 1
   end
   return counts
end

local function ensure_bay_outfits()
   if not is_carrier(player.ship()) then return end
   local pilot = player.pilot()
   local desired = desired_bay_counts()
   local installed = {}
   for _, outfit in ipairs(pilot:outfitsList()) do
      local name = outfit:nameRaw()
      if desired[name] then installed[name] = (installed[name] or 0) + 1 end
   end
   for name, wanted in pairs(desired) do
      local count = installed[name] or 0
      if count > wanted then
         pilot:outfitRm(name, count - wanted)
         count = wanted
      end
      for _index = count + 1, wanted do
         assert(pilot:outfitAdd(name) > 0,
            "Nomad carrier has no free slot for " .. name)
      end
   end
end

local function physical_bay_slots()
   local slots = {}
   for id, outfit in ipairs(player.pilot():outfits()) do
      if outfit then
         slots[#slots + 1] = { id = id, outfit = outfit:nameRaw() }
      end
   end
   return slots
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
   local assignments, violations = runtime.audit_fleet(ordinary_owned_ships())
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
   if not is_carrier(player.ship()) then
      naev.cache().nomad_bay_tooltips = descriptions
      return
   end
   local assignments = audit_now()
   local mapped = runtime.map_bay_slots(config.carrier.bays, physical_bay_slots())
   for id, slot in pairs(mapped) do
      descriptions[id] = runtime.bay_tooltip(
         runtime.ship_for_bay(assignments, slot.index))
   end
   for _, slot in ipairs(physical_bay_slots()) do
      if slot.outfit == config.command_bay.outfit then
         local shuttle = crewmates.get_commander_shuttle(config.joyride_client)
         descriptions[slot.id] = shuttle
            and string.format("Assigned: Commander Shuttle (%s)", shuttle:nameRaw())
            or "Empty"
      end
   end
   naev.cache().nomad_bay_tooltips = descriptions
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
      player.landAllow(false,
         _("The carrier cannot land. Launch a carried ship to visit a spaceport."))
      mem.nomad.carrier_land_block = true
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

local function bay_summary(assignments)
   local lines = {}
   for _index, slot in ipairs(policy.usage(config.carrier.bays, assignments)) do
      lines[#lines + 1] = string.format("%s: %s", slot.bay.name,
         slot.ship and (slot.ship.name .. " (" .. slot.ship.hull .. ")") or _("empty"))
   end
   lines[#lines + 1] = string.format("%s: %s", config.command_bay.name,
      crewmates.get_commander_shuttle(config.joyride_client):nameRaw())
   return table.concat(lines, "\n")
end

function nomad_carrier_menu()
   local assignments, violations = audit_now()
   local ships = ordinary_owned_ships()
   local choices = {}
   local actions = {}
   for _index, entry in ipairs(ships) do
      if entry.name ~= player.ship() then
         local action = entry.deployed and _("Recall") or _("Launch")
         choices[#choices + 1] = string.format("%s %s (%s)", action, entry.name, entry.hull)
         actions[#actions + 1] = entry
      end
   end
   local status = bay_summary(assignments)
   if #violations > 0 then
      status = status .. "\n\n#r" .. runtime.violation_message(violations[1]) .. "#0"
   end
   if #actions == 0 then
      tk.msg(_("Nomad Carrier"), status)
      return
   end
   choices[#choices + 1] = _("Close")
   local choice = tk.choice(_("Nomad Carrier"), status, table.unpack(choices))
   local selected = actions[choice]
   if not selected then return end
   local ok, reason
   if not mem.nomad.active_sortie then
      player.shipDeploy(selected.name, not selected.deployed, not selected.deployed)
      ok = true
   elseif selected.deployed then
      ok, reason = joyride.recall_owned(selected.name)
   else
      ok, reason = joyride.launch_owned(selected.name)
   end
   if not ok then tk.msg(_("Carrier Control"), tostring(reason)) end
   hook.safe("nomad_refresh_escort_hooks")
   apply_rules(false)
end

local function bay_action_message(message)
   if type(player.msg) == "function" then player.msg(message) end
end

local function launch_command_shuttle()
   if naev.cache().joyride then
      return false, _("another auxiliary ship is already active")
   end
   if not naev.claimTest(system.cur()) then
      return false, _("it is unsafe to launch in this system")
   end
   local commander, reason = crewmates.get_commander(config.joyride_client)
   if not commander then return false, reason end
   if commander.shuttle and commander.shuttle.out then
      return false, _("the commander shuttle is already deployed")
   end
   local shuttle = crewmates.get_commander_shuttle(config.joyride_client)
   if not shuttle then return false, _("the commander shuttle is unavailable") end

   local carrier = player.pilot()
   local template = pilot.add(
      shuttle,
      commander.faction or "Trader",
      carrier:pos(),
      fmt.f(_("{name}'s Shuttle"), { name = player.ship() }),
      { ai = "dummy" }
   )
   template:setVel(carrier:vel())
   template:setDir(carrier:dir())
   local launch_profile = profile()
   launch_profile.name = fmt.f(_("{skill} {title} {name}"), {
      skill = commander.skill or "",
      title = commander.typetitle or _("Commander"),
      name = commander.name or "",
   })
   launch_profile.faction = commander.faction
   launch_profile.ai = "escort_guardian"
   joyride.swap_to_subship(
      carrier,
      template,
      fmt.f(_("The command bay of your {mothership}."), {
         mothership = player.ship(),
      }),
      launch_profile
   )
   return true
end

function nomad_bay_activated(payload)
   if not payload or not is_carrier(player.ship()) then return end
   if payload.outfit == config.command_bay.outfit then
      local ok, reason = launch_command_shuttle()
      if ok then
         bay_action_message(_("Launching the commander's shuttle."))
      else
         bay_action_message(string.format(_("Command bay: %s"), tostring(reason)))
      end
      return
   end

   local mapped = runtime.map_bay_slots(config.carrier.bays, physical_bay_slots())
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

function nomad_refresh_after_bay_action()
   nomad_refresh_escort_hooks()
   apply_rules(false)
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
   local entry = find_owned(name)
   if not entry or not entry.deployed then return end
   local ok, reason = joyride.borrow_owned(name, profile())
   if not ok then
      tk.msg(_("Seat Transfer"), tostring(reason))
      player.commClose()
      return
   end
   mem.nomad.active_kind = "owned"
   apply_rules(false)
   hook.safe("nomad_refresh_escort_hooks")
end

local function register_menu()
   if info_button then player.infoButtonUnregister(info_button) end
   info_button = player.infoButtonRegister(_("Nomad Carrier"), nomad_carrier_menu, 2, "N")
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
   local fits, violations = apply_rules(false)
   if not fits then
      tk.msg(_("Docking Refused"), runtime.violation_message(violations[1]) .. "\n\n"
         .. _("Sell or trade the incompatible hull before returning."))
      player.commClose()
      return
   end
   joyride.end_joyride()
end

function nomad_initialize()
   -- Load events run while Naev is still restoring the landed spob. Crewmates
   -- may need that spob when it creates the required commander, so this work
   -- is deliberately deferred to a safe hook after the load transition.
   if not crewmates.is_ready() then
      hook.timer(0.1, "nomad_initialize")
      return
   end
   ensure_bay_outfits()
   assert(crewmates.ensure_commander(config.joyride_client, {
      minimum = config.minimum_crew.commander,
      shuttle = config.starter_subship.hull,
      shuttle_profile = profile(),
   }), "Nomad requires an available commander")
   player.fleetCapacitySet(config.fleet_capacity)
   owned_additions(true)
   register_menu()
   apply_rules(false)
   hook.safe("nomad_refresh_escort_hooks")

   if not mem.nomad.hooks_installed then
      hook.enter("nomad_apply_rules")
      hook.land("nomad_apply_rules")
      hook.takeoff("nomad_apply_rules")
      hook.load("nomad_defer_initialize")
      hook.ship_swap("nomad_ship_changed")
      hook.ship_buy("nomad_ship_acquired")
      hook.ship_sell("nomad_ship_changed")
      hook.custom("joyride_mothership_spawned", "nomad_joyride_started")
      hook.custom("joyride_shuttle_returned", "nomad_shuttle_returned")
      hook.custom("joyride_mothership_restored", "nomad_mothership_restored")
      hook.custom("joyride_ended", "nomad_joyride_ended")
      hook.custom("nomad_bay_activated", "nomad_bay_activated")
      mem.nomad.hooks_installed = true
   end
end

function nomad_defer_initialize()
   hook.safe("nomad_initialize")
end

function create()
   mem.nomad = runtime.initialize(mem.nomad)
   assert(runtime.joyride_available(), "Nomad requires the extended Joyride API")
   evt.save(true)
   nomad_defer_initialize()
end
