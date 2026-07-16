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
local parking = require "nomad.parking"
local retrofit = require "nomad.retrofit"
local runtime = require "nomad.runtime"

local mothership_pilot
local info_buttons = {}
local escort_hooks = {}
local bay_pilots = {}
local bay_slots = {}
local known_owned = {}
local parking_requested
local parking_reuse_record
local parking_sequence = 0
local departed_cleanup_pending = false
local pending_sortie_bays
local pending_bay_transfer
local pending_return_to_fleet
local pending_hail_name
local mothership_hail_pending = false
local register_actions
local hooks_installed = false
local is_carrier
local sortie_bays
local pending_acquisition
local pending_carrier_replacement
local carrier_conversion = false
local stored_carrier_bays
local remove_bay_pilot

local function craft_state(name)
   return runtime.craft_state(mem.nomad, name)
end

local function set_bay_control(id, on)
   if not id then return end
   local shared = naev.cache()
   shared.nomad_bay_states = shared.nomad_bay_states or {}
   shared.nomad_bay_states[id] = on == true
end

local function set_bay_cooldown(id, remaining, total)
   if not id then return end
   local shared = naev.cache()
   shared.nomad_bay_cooldowns = shared.nomad_bay_cooldowns or {}
   if remaining and remaining > 0 then
      shared.nomad_bay_cooldowns[id] = {
         remaining = remaining,
         total = math.max(remaining, total or remaining),
      }
   else
      shared.nomad_bay_cooldowns[id] = nil
   end
end

local function snapshot_outfits(subject, preserve_slots)
   local result = {}
   if not preserve_slots then
      for _, installed in ipairs(subject or {}) do
         result[#result + 1] = {
            name = type(installed) == "string"
               and installed or installed:nameRaw(),
         }
      end
      return result
   end
   for id, installed in pairs(subject or {}) do
      if installed then
         result[#result + 1] = {
            id = id,
            name = type(installed) == "string"
               and installed or installed:nameRaw(),
         }
      end
   end
   table.sort(result, function(a, b) return a.id < b.id end)
   return result
end

local function owned_snapshot(entry, name)
   if not entry and name == player.ship() then
      entry = { name = name, ship = player.pilot():ship() }
   end
   if not entry then return nil end
   return {
      hull = entry.ship:nameRaw(),
      size = entry.ship:size(),
      outfits = snapshot_outfits(player.shipOutfits(entry.name) or {}, false),
      armour = 100,
      shield = 100,
      stress = 0,
      energy = 100,
      cargo = {},
   }
end

local function pilot_snapshot(subject)
   local armour, shield, stress = subject:health()
   local snapshot = {
      hull = subject:ship():nameRaw(),
      size = subject:ship():size(),
      outfits = snapshot_outfits(subject:outfits(), true),
      armour = armour,
      shield = shield,
      stress = stress,
      energy = subject:energy(),
      fuel = subject:stats().fuel,
      cargo = {},
      weapon_sets = {},
   }
   for _, item in ipairs(subject:cargoList()) do
      if not item.m and item.q > 0 then
         snapshot.cargo[#snapshot.cargo + 1] = {
            commodity = item.c:nameRaw(), quantity = item.q,
         }
      end
   end
   for id = 1, 10 do
      snapshot.weapon_sets[id] = subject:weapsetList(id)
   end
   return snapshot
end

local function pilot_transform(subject)
   local x, y = subject:pos():get()
   return { x = x, y = y, direction = subject:dir() }
end

local function apply_snapshot(subject, snapshot, serviced, zero_shields)
   for _, fitted in ipairs(snapshot.outfits or {}) do
      if fitted.id then
         assert(subject:outfitAddSlot(
            fitted.name, fitted.id, true, false))
      else
         subject:outfitAdd(fitted.name, 1, true)
      end
   end
   if snapshot.weapon_sets then
      subject:weapsetCleanup()
      for id, slots in ipairs(snapshot.weapon_sets) do
         for _, slot in ipairs(slots) do subject:weapsetAdd(id, slot) end
      end
   end
   for _, item in ipairs(snapshot.cargo or {}) do
      subject:cargoAdd(item.commodity, item.quantity)
   end
   if serviced then
      subject:setHealth(100, 100, 0)
      subject:setEnergy(100)
      subject:setFuel(true)
      subject:fillAmmo()
   else
      subject:setHealth(snapshot.armour or 100,
         zero_shields and 0 or (snapshot.shield or 100), snapshot.stress or 0)
      subject:setEnergy(snapshot.energy or 100)
      if snapshot.fuel then subject:setFuel(snapshot.fuel) end
   end
end

is_carrier = function(name)
   if name == player.ship() then
      return runtime.is_carrier(player.shipvarPeek(config.carrier_shipvar))
   end
   return runtime.is_carrier(player.shipvarPeek(config.carrier_shipvar, name))
end

local function physical_bay_slots(subject)
   local slots = {}
   for id, outfit in pairs((subject or player.pilot()):outfits()) do
      if outfit then
         slots[#slots + 1] = { id = id, outfit = outfit:nameRaw() }
      end
   end
   return slots
end

local function current_bays()
   if is_carrier(player.ship()) then
      return runtime.general_bays(physical_bay_slots())
   end
   if mem.nomad.parked and mem.nomad.parked.carrier then
      return stored_carrier_bays(mem.nomad.parked.carrier)
   end
   if mem.nomad.active_sortie then return sortie_bays or {} end
   return {}
end

stored_carrier_bays = function(name)
   local slots = {}
   for index, installed in ipairs(player.shipOutfits(name) or {}) do
      local outfit_name = type(installed) == "string"
         and installed or installed:nameRaw()
      if config.general_bays[outfit_name] then
         slots[#slots + 1] = { id = index, outfit = outfit_name }
      end
   end
   return runtime.general_bays(slots)
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
         local phase = craft_state(entry.name).phase
         local record = ship_record(entry.name, entry.ship,
            phase == "deployed" or phase == "returning")
         record.native_deployed = entry.deployed == true
         ships[#ships + 1] = record
      end
   end
   local current = player.ship()
   if not seen[current] and not is_carrier(current)
      and current ~= mem.nomad.virtual_name then
      ships[#ships + 1] = ship_record(current, player.pilot():ship(), false)
      seen[current] = true
   end
   local function append_snapshot_record(name)
      if not name or seen[name] or name == current then return end
      local state = craft_state(name)
      local snapshot = state.snapshot
      if snapshot and snapshot.hull and snapshot.size then
         ships[#ships + 1] = {
            name = name,
            hull = snapshot.hull,
            size = snapshot.size,
            deployed = state.phase == "deployed"
               or state.phase == "returning",
            native_deployed = false,
         }
         seen[name] = true
      end
   end
   append_snapshot_record(mem.nomad.controlled_craft)
   for name, candidate in pairs(bay_pilots) do
      if candidate and candidate:exists() then append_snapshot_record(name) end
   end
   return ships
end

local function current_command_shuttle()
   if mem.nomad.active_source ~= "command" then return nil end
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
      descriptions[id] = runtime.bay_tooltip(assigned,
         assigned and craft_state(assigned.name) or nil)
      assignments_by_slot[id] = assigned
      if assigned then
         bay_slots[assigned.name] = id
         local state = craft_state(assigned.name)
         local phase = state.phase
         set_bay_control(id, phase == "deployed"
            or phase == "returning" or phase == "controlled")
         if phase == "cooldown" then
            set_bay_cooldown(id, state.remaining, state.cooldown_total)
         else
            set_bay_cooldown(id)
         end
      else
         set_bay_control(id, false)
         set_bay_cooldown(id)
      end
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
            _("The carrier cannot land normally. Activate the Nomadic Operational Core to park."))
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

local function incumbent_carrier()
   for _, entry in ipairs(player.ships()) do
      if is_carrier(entry.name) then
         local record = ship_record(entry.name, entry.ship, entry.deployed)
         record.id = entry.name
         record.bays = current_bays()
         return record, entry
      end
   end
   if is_carrier(player.ship()) then
      local ship_type = player.pilot():ship()
      local record = ship_record(player.ship(), ship_type, false)
      record.id = player.ship()
      record.bays = current_bays()
      return record, { name = player.ship(), ship = ship_type, deployed = false }
   end
end

local function carrier_candidate(entry)
   local slots = entry.ship:getSlots()
   local bays = runtime.carrier_bays(slots)
   if #bays == 0 then return nil end
   local systems = retrofit.allocate(slots, {}, config.integrated_systems)
   if #systems ~= #config.integrated_systems then return nil end
   local record = ship_record(entry.name, entry.ship, entry.deployed)
   record.id = entry.name
   record.bays = bays
   return record
end

local function refund_purchase(entry, reason)
   local amount = entry.ship:price()
   player.shipRm(entry.name)
   player.pay(amount)
   tk.msg(_("Purchase Refunded"), string.format(
      _("%s\n\nThe purchase price of %s has been returned."),
      tostring(reason), fmt.credits(amount)))
end

local function fit_carrier_systems()
   local pilot = player.pilot()
   local slots = pilot:ship():getSlots()

   for index, slot in ipairs(slots) do
      local bay_outfit = config.bay_outfit_by_slot_size[slot.size]
      if slot.type == "Weapon" and slot.property == "fighter_bay"
         and not slot.locked and bay_outfit then
         local id = slot.id or index
         local installed = pilot:outfits()[id]
         if installed and installed:nameRaw() ~= bay_outfit then
            player.outfitAdd(installed:nameRaw(), 1)
            pilot:outfitRmSlot(id)
         end
         if not pilot:outfits()[id] then
            pilot:outfitAddSlot(bay_outfit, id, true, false)
         end
      end
   end

   local allocations = retrofit.allocate(
      slots, {}, config.integrated_systems)
   for _, allocation in ipairs(allocations) do
      local installed = pilot:outfits()[allocation.id]
      if installed and installed:nameRaw() ~= allocation.outfit then
         player.outfitAdd(installed:nameRaw(), 1)
         pilot:outfitRmSlot(allocation.id)
      end
      if not pilot:outfits()[allocation.id] then
         pilot:outfitAddSlot(allocation.outfit, allocation.id, true, false)
      end
   end
end

local function strip_nomad_carrier_systems()
   local pilot = player.pilot()
   carrier_conversion = true
   for id, installed in pairs(pilot:outfits()) do
      local name = installed:nameRaw()
      if config.general_bays[name] then
         player.outfitAdd(name, 1)
         pilot:outfitRmSlot(id)
      elseif name == config.operational_core or name == config.shuttle_bay then
         pilot:outfitRmSlot(id)
      end
   end
   carrier_conversion = false
end

local function owned_additions(update)
   local additions = {}
   local current = {}
   for _, entry in ipairs(ordinary_owned_ships()) do
      current[entry.name] = true
      if not known_owned[entry.name] then additions[#additions + 1] = entry end
   end
   if update then
      for name in pairs(mem.nomad.crafts or {}) do
         local candidate = bay_pilots[name]
         local represented_in_space = candidate and candidate:exists()
         if not current[name] and name ~= mem.nomad.controlled_craft
            and not represented_in_space then
            remove_bay_pilot(name)
            mem.nomad.crafts[name] = nil
            bay_slots[name] = nil
         end
      end
      known_owned = current
   end
   return additions
end

local function bay_action_message(message)
   player.msg(message)
end

local function launch_command_shuttle()
   return crewmates.launch_commander_shuttle(config.joyride_client)
end

local function live_bay_pilot(name)
   local candidate = bay_pilots[name]
   if candidate and candidate:exists() then return candidate end
   bay_pilots[name] = nil
end

remove_bay_pilot = function(name)
   local candidate = bay_pilots[name]
   bay_pilots[name] = nil
   if candidate and candidate:exists() then candidate:rm() end
end

local function launch_bay_ship(entry, assigned_name)
   local name = entry and entry.name or assigned_name
   if not name then return false, _("the assigned ship name is unavailable") end
   if entry and entry.deployed then
      return false, _("undeploy this ship in Equipment before assigning it to a Nomad bay")
   end
   local state = craft_state(name)
   local ship_type = entry and entry.ship
      or (state.snapshot and state.snapshot.hull)
   if not ship_type then
      return false, _("the assigned ship hull is unavailable")
   end
   if state.phase ~= "ready" then
      return false, string.format(_("the bay is %s"), state.phase)
   end
   for _index, existing in ipairs(pilot.get()) do
      if existing:exists() and existing:name() == name then
         return false, _("a pilot with that name already exists")
      end
   end
   local carrier = player.pilot()
   local transform = state.redeploy_transform
   local spawn_position = transform
      and vec2.new(transform.x, transform.y) or carrier:pos()
   local ok, candidate = pcall(pilot.add, ship_type, carrier:faction(),
      spawn_position, name, { ai = "escort", naked = true })
   if not ok or not candidate then
      return false, ok and _("Naev did not create the carried ship") or candidate
   end
   state.snapshot = state.snapshot or owned_snapshot(entry, name)
   apply_snapshot(candidate, state.snapshot, state.serviced, state.zero_shields)
   state.snapshot.armour_max = candidate:stats().armour
   state.serviced = nil
   state.zero_shields = nil
   state.prelaunch = state.snapshot
   state.phase = "deployed"
   state.remaining = nil
   state.cooldown_total = nil
   if transform then candidate:setDir(transform.direction) end
   state.redeploy_transform = nil
   candidate:setLeader(carrier)
   candidate:setNoClear(true)
   candidate:setFriendly(true)
   candidate:setInvincPlayer(true)
   bay_pilots[name] = candidate
   set_bay_cooldown(bay_slots[name])
   set_bay_control(bay_slots[name], true)
   escort_hooks[candidate] = hook.pilot(candidate, "hail",
      "nomad_hail_owned", name)
   hook.pilot(candidate, "death", "nomad_bay_destroyed", name)
   return true
end

local function restore_bay_pilots()
   if player.isLanded() then return end
   local leader = mothership_pilot and mothership_pilot:exists()
      and mothership_pilot or (is_carrier(player.ship()) and player.pilot() or nil)
   if not leader then return end
   for name, state in pairs(mem.nomad.crafts or {}) do
      if (state.phase == "deployed" or state.phase == "returning")
         and not live_bay_pilot(name) then
         local entry = find_owned(name)
         local phase = state.phase
         state.phase = "ready"
         local ok, reason = launch_bay_ship(entry, name)
         if not ok then
            state.phase = phase
            bay_action_message(string.format(
               _("Unable to restore %s from its bay: %s"),
               name, tostring(reason)))
         else
            local candidate = live_bay_pilot(name)
            candidate:setLeader(leader)
            if phase == "returning" then
               state.phase = "returning"
               candidate:control(true)
               candidate:follow(leader, true)
            end
         end
      end
   end
end

local function begin_recall(name)
   local candidate = live_bay_pilot(name)
   local state = craft_state(name)
   if not candidate or state.phase ~= "deployed" then return false end
   state.phase = "returning"
   local leader = candidate:leader()
   if leader and leader:exists() then
      leader:msg(candidate, "e_return")
      candidate:control(true)
      candidate:follow(leader, true)
   end
   return true
end

function nomad_bay_destroyed(_pilot, _attacker, name)
   local state = craft_state(name)
   local maximum = state.snapshot and state.snapshot.armour_max or 0
   local candidate = bay_pilots[name]
   if candidate then maximum = candidate:stats().armour or maximum end
   bay_pilots[name] = nil
   state.snapshot = state.prelaunch or state.snapshot
   state.prelaunch = nil
   state.phase = "cooldown"
   state.destroyed = true
   state.remaining = runtime.destroyed_cooldown(maximum)
   state.cooldown_total = state.remaining
   set_bay_cooldown(bay_slots[name], state.remaining, state.cooldown_total)
   set_bay_control(bay_slots[name], false)
end

function nomad_update(dt)
   local leader = mothership_pilot and mothership_pilot:exists()
      and mothership_pilot or (is_carrier(player.ship()) and player.pilot() or nil)
   for name, state in pairs(mem.nomad.crafts or {}) do
      if state.phase == "returning" then
         local candidate = live_bay_pilot(name)
         if candidate and leader and leader:exists() then
            if candidate:pos():dist(leader:pos()) <= 80 then
               local snapshot = pilot_snapshot(candidate)
               local stats = candidate:stats()
               snapshot.armour_max = stats.armour
               state.snapshot = snapshot
               state.prelaunch = nil
               state.phase = "cooldown"
               state.remaining = runtime.return_cooldown(
                  snapshot.armour, snapshot.shield, stats.armour)
               state.cooldown_total = state.remaining
               -- An intact craft is serviced during turnaround. Mark it now
               -- so a rejected early activation cannot leave a stale
               -- destroyed-craft shield override behind.
               state.destroyed = nil
               state.zero_shields = nil
               state.serviced = true
               set_bay_cooldown(bay_slots[name], state.remaining,
                  state.cooldown_total)
               remove_bay_pilot(name)
               set_bay_control(bay_slots[name], false)
            end
         end
      elseif state.phase == "cooldown" then
         local ready = runtime.tick_cooldown(state, dt)
         set_bay_cooldown(bay_slots[name], state.remaining,
            state.cooldown_total)
         if ready then set_bay_control(bay_slots[name], false) end
      end
   end
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

   local state = craft_state(assigned.name)
   local ok, reason = true
   if payload.on == false then
      ok = begin_recall(assigned.name)
      if ok then
         set_bay_control(payload.id, true)
         bay_action_message(string.format(_("Recalling %s (%s)."),
            assigned.name, assigned.hull))
      else
         reason = _("the assigned craft is not deployed")
      end
   elseif state.phase == "ready" then
      local entry = find_owned(assigned.name)
      ok, reason = launch_bay_ship(entry)
      if ok then
         bay_action_message(string.format(_("Launching %s (%s)."),
            assigned.name, assigned.hull))
      else
         bay_action_message(string.format(_("Bay launch failed: %s"),
            tostring(reason)))
      end
   else
      ok = false
      reason = string.format(_("the bay is %s"), state.phase)
   end
   if not ok then set_bay_control(payload.id, state.phase == "deployed"
      or state.phase == "returning") end
   hook.safe("nomad_refresh_after_bay_action")
end

function nomad_launch_command_shuttle()
   if not is_carrier(player.ship()) or player.isLanded() then return end
   pending_sortie_bays = current_bays()
   local previous_source = mem.nomad.active_source
   -- Crewmates starts Joyride synchronously. Mark the source before launching
   -- so joyride_mothership_spawned cannot mistake this for a returning bay
   -- craft and replace Joyride Handler's command-shuttle board hook.
   mem.nomad.active_source = "command"
   local ok, reason = launch_command_shuttle()
   if ok then
      bay_action_message(_("Launching the commander's shuttle."))
   else
      pending_sortie_bays = nil
      mem.nomad.active_source = previous_source
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

function nomad_integrated_system_activated(payload)
   if not payload or not is_carrier(player.ship()) then return end
   if payload.action == "park" then
      nomad_park_carrier()
   elseif payload.action == "shuttle" then
      nomad_launch_command_shuttle()
   end
end

function nomad_bay_configuration_changed()
   if carrier_conversion then return end
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
   if carrier_conversion then return end
   hook.safe("nomad_restore_occupied_bay", payload)
end

function nomad_refresh_escort_hooks()
   for candidate in pairs(escort_hooks) do
      if not candidate:exists() then escort_hooks[candidate] = nil end
   end
   for name, candidate in pairs(bay_pilots) do
      if candidate:exists() and not escort_hooks[candidate] then
         escort_hooks[candidate] = hook.pilot(candidate, "hail",
            "nomad_hail_owned", name)
      end
   end
end

function nomad_hail_owned(_pilot, name)
   -- Close the stock escort comm immediately. The actual ship swap remains
   -- deferred so its pilot can be removed safely after the hail hook returns.
   player.commClose()
   pending_hail_name = name
   hook.timer(0.1, "nomad_begin_owned_joyride")
end

function nomad_begin_owned_joyride(name)
   name = name or pending_hail_name
   pending_hail_name = nil
   if not name then return end
   -- Let Naev finish constructing the hail window before Joyride removes the
   -- deployed pilot. Invalidating it directly in the pilot hail hook makes the
   -- comm backend dereference a pilot that no longer exists.
   local template = live_bay_pilot(name)
   if not template then return end
   if naev.cache().joyride then
      if mem.nomad.active_source ~= "bay" then
         tk.msg(_("Seat Transfer"), _(
            "Return the active auxiliary craft before taking control of this ship."))
         return
      end
      for _, item in ipairs(player.pilot():cargoList()) do
         if item.q > 0 then
            tk.msg(_("Seat Transfer"),
               _("Unload this craft before changing seats."))
            return
         end
      end
      pending_bay_transfer = name
      pending_return_to_fleet = mem.nomad.controlled_craft
      if pending_return_to_fleet then
         local returning_state = craft_state(pending_return_to_fleet)
         returning_state.snapshot = pilot_snapshot(player.pilot())
         returning_state.redeploy_transform = pilot_transform(player.pilot())
      end
      local ok, reason = joyride.end_joyride()
      if not ok then
         if pending_return_to_fleet then
            craft_state(pending_return_to_fleet).redeploy_transform = nil
         end
         pending_bay_transfer = nil
         pending_return_to_fleet = nil
         tk.msg(_("Seat Transfer"), tostring(reason))
         return
      end
      hook.timer(0.1, "nomad_complete_bay_seat_transfer")
      return
   end
   pending_sortie_bays = current_bays()
   local state = craft_state(name)
   bay_pilots[name] = nil
   state.phase = "controlled"
   local sortie_profile = profile()
   sortie_profile.nomad_owned_proxy = true
   local ok, controlled = pcall(joyride.swap_to_subship,
      player.pilot(), template,
      string.format(_("%s is carried aboard the Nomad mothership."), name),
      sortie_profile)
   if not ok or not controlled then
      pending_sortie_bays = nil
      state.phase = "deployed"
      bay_pilots[name] = template
      tk.msg(_("Seat Transfer"), tostring(controlled))
      return
   end
   mem.nomad.controlled_craft = name
   mem.nomad.active_kind = "virtual"
   mem.nomad.active_source = "bay"
   apply_rules(false)
end

function nomad_complete_bay_seat_transfer()
   local name = pending_bay_transfer
   pending_bay_transfer = nil
   if not name or naev.cache().joyride or not is_carrier(player.ship()) then return end
   local candidate = live_bay_pilot(name)
   if not candidate then return end
   candidate:setLeader(player.pilot())
   nomad_begin_owned_joyride(name)
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
   if mem.nomad.parked then
      return false, _("a parking berth is already active")
   end
   local pilot = player.pilot()
   local _armour, shield = pilot:health()
   local stats = pilot:stats()
   return parking.validate(is_carrier(player.ship()), player.isLanded(),
      shield, stats.shield)
end

local function service_bay_fleet()
   for name, state in pairs(mem.nomad.crafts or {}) do
      local candidate = live_bay_pilot(name)
      if candidate then state.snapshot = pilot_snapshot(candidate) end
      remove_bay_pilot(name)
      runtime.service_craft(state)
      set_bay_control(bay_slots[name], false)
   end
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
   service_bay_fleet()
   local position = pilot:pos()
   local x, y = position:get()
   local current_system = system.cur()
   local system_name = current_system:nameRaw()
   local reused = parking_reuse_record
   parking_reuse_record = nil
   if reused and (mem.nomad.departed_parking ~= reused
      or reused.system ~= system_name) then
      reused = nil
   end
   local record = parking.record(
      system_name, x, y, pilot:dir(),
      reused and reused.diff or next_parking_diff_name(), player.ship())
   if reused then mem.nomad.departed_parking = nil end
   mem.nomad.parked = record
   if not reused then
      ok, reason = parked_diff_apply(record)
      if not ok then
         parking_rollback(reason)
         return
      end
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
   end
end

function nomad_park_carrier()
   local ok, reason = parking_status()
   if not ok then
      tk.msg(_("Unable to Park Carrier"), tostring(reason))
      return
   end
   -- The relocated spob must not be removed while its system is active: Naev
   -- can leave null spob references behind for other events. Reuse that berth
   -- and record the carrier's new return transform instead.
   local departed = mem.nomad.departed_parking
   local current_system = system.cur()
   if departed and current_system
      and current_system:nameRaw() == departed.system then
      parking_reuse_record = departed
      parking_requested = true
      hook.timer(0.1, "nomad_complete_parking")
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
   -- The player performs the ordinary landing after Nomad selects the berth.
   -- Never remove its diff until this hook confirms the real landed state.
   if mem.nomad.parked and is_carrier(player.ship()) then
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
      mem.nomad.parked.carrier = mem.nomad.parked.carrier or player.ship()
   elseif not mem.nomad.departed_parking then
      parked_diff_remove()
   end
   hook.safe("nomad_initialize")
end

local function restore_carrier_after_takeoff(record)
   mem.nomad.departed_parking = record
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
      if not is_carrier(player.ship()) then
         local record = mem.nomad.parked
         local bays = stored_carrier_bays(record.carrier)
         local selected = player.ship()
         local ok, reason = joyride.begin_stored_owned_sortie(record.carrier,
            profile(), vec2.new(record.x, record.y), record.direction)
         if not ok then
            tk.msg(_("Unable to Launch Ship"), tostring(reason))
            nomad_apply_rules()
            return
         end
         local sortie_pilot = player.pilot()
         sortie_pilot:setPos(vec2.new(record.x, record.y))
         sortie_pilot:setDir(record.direction)
         local state = craft_state(selected)
         state.snapshot = state.snapshot
            or owned_snapshot(find_owned(selected), selected)
         state.prelaunch = state.snapshot
         state.phase = "controlled"
         mem.nomad.controlled_craft = selected
         runtime.joyride_started(mem.nomad, {
            client = config.joyride_client,
         })
         mem.nomad.active_kind = "owned"
         mem.nomad.active_source = "bay"
         mem.nomad.virtual_name = nil
         sortie_bays = bays
         hook.timer(0.1, "nomad_finish_stored_carrier_takeoff", record)
         return
      end
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

function nomad_finish_stored_carrier_takeoff(record)
   if mem.nomad.parked ~= record or player.isLanded() then return end
   mem.nomad.parked = nil
   mem.nomad.departed_parking = record
   hook.timer(0.1, "nomad_spawn_stored_carrier")
end

function nomad_spawn_stored_carrier()
   local ok, reason = joyride.takeoff()
   if not ok then
      tk.msg(_("Unable to Restore Carrier"), tostring(reason))
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
   local departed = mem.nomad.departed_parking
   local current_system = system.cur()
   if departed and current_system
      and current_system:nameRaw() ~= departed.system
      and not departed_cleanup_pending then
      -- Do not rebuild the faction-spob list between enter callbacks. A later
      -- event such as Crewmates would otherwise see the removed spob as null.
      departed_cleanup_pending = true
      hook.timer(0.1, "nomad_remove_departed_parking")
   end
   restore_bay_pilots()
   apply_rules(false)
   hook.safe("nomad_refresh_escort_hooks")
end

function nomad_remove_departed_parking()
   departed_cleanup_pending = false
   local departed = mem.nomad.departed_parking
   local current_system = system.cur()
   if not departed or not current_system
      or current_system:nameRaw() == departed.system then return end
   mem.nomad.departed_parking = nil
   parked_diff_remove(departed)
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
   pending_acquisition = { ship_type = ship_type, traded = traded }
   hook.safe("nomad_finish_acquisition", pending_acquisition)
end

function nomad_after_ownership_change(show_message)
   if pending_acquisition then
      nomad_finish_acquisition(pending_acquisition)
      return
   end
   if mem.nomad.active_kind == "virtual"
      and mem.nomad.virtual_name ~= player.ship() then
      return
   end
   apply_rules(show_message == true)
   owned_additions(true)
end

function nomad_finish_acquisition(acquisition)
   if acquisition ~= pending_acquisition then return end
   if mem.nomad.active_kind == "virtual"
      and mem.nomad.virtual_name ~= player.ship() then
      return
   end

   if acquisition.traded then
      pending_acquisition = nil
      apply_rules(true)
      owned_additions(true)
      return
   end

   local additions = owned_additions(false)
   local active_kind = mem.nomad.active_kind
   if (active_kind ~= "virtual" and active_kind ~= "owned")
      or #additions ~= 1 then
      pending_acquisition = nil
      apply_rules(true)
      owned_additions(true)
      return
   end

   local candidate = additions[1]
   local candidate_entry = find_owned(candidate.name)
   if not candidate_entry and player.ship() == candidate.name then return end
   pending_acquisition = nil
   local incumbent = incumbent_carrier()
   if not candidate_entry or not incumbent then
      refund_purchase(candidate_entry or {
         name = candidate.name, ship = acquisition.ship_type,
      }, _("Nomad could not verify the carrier configuration."))
      owned_additions(true)
      return
   end

   local others = {}
   for _, ship in ipairs(ordinary_owned_ships()) do
      if ship.name ~= candidate.name then others[#others + 1] = ship end
   end
   local replacement = carrier_candidate(candidate_entry)
   local decision = runtime.acquisition_decision(
      incumbent, others, candidate, replacement)

   if decision.action == "refund" then
      refund_purchase(candidate_entry, string.format(
         _("%s cannot fit in an available carrier bay and cannot replace the current carrier: %s."),
         candidate.hull, tostring(decision.reason)))
   elseif decision.action == "replace" then
      local confirmed = tk.yesno(_("Replace Nomad Carrier"), string.format(
         _("%s cannot be stored aboard %s, but it can carry the current Nomad fleet. Make %s the new carrier?"),
         candidate.hull, incumbent.hull, candidate.hull))
      if not confirmed then
         refund_purchase(candidate_entry,
            _("The ship was not accepted as the new Nomad carrier."))
      else
         local ok, reason = joyride.handoff_to_owned(candidate.name)
         if not ok then
            refund_purchase(candidate_entry, string.format(
               _("The command shuttle could not transfer control: %s"),
               tostring(reason)))
         else
            pending_carrier_replacement = {
               candidate = candidate.name,
               incumbent = incumbent.name,
               retain_incumbent = decision.retain_incumbent,
            }
            bay_action_message(_(
               "Carrier replacement will complete when you take off."))
         end
      end
   else
      if active_kind == "virtual" then
         local ok, reason = joyride.handoff_to_owned(candidate.name)
         if not ok then
            refund_purchase(candidate_entry, string.format(
               _("The command shuttle could not transfer control: %s"),
               tostring(reason)))
         end
      end
   end

   owned_additions(true)
   apply_rules(false)
end

function nomad_complete_carrier_replacement()
   if not pending_carrier_replacement or not mothership_pilot
      or not mothership_pilot:exists() then return end
   local ok, reason = joyride.end_joyride { redeploy_owned = false }
   if not ok then
      tk.msg(_("Carrier Replacement Delayed"), tostring(reason))
   end
end

local function finalize_carrier_replacement()
   local replacement = pending_carrier_replacement
   if not replacement then return end
   pending_carrier_replacement = nil

   if player.ship() ~= replacement.incumbent
      or not find_owned(replacement.candidate) then
      tk.msg(_("Carrier Replacement Failed"),
         _("The candidate or incumbent carrier is no longer available."))
      return
   end

   local incumbent_refund
   if not replacement.retain_incumbent then
      incumbent_refund = player.pilot():worth()
   end
   player.shipvarPop(config.carrier_shipvar)
   if replacement.retain_incumbent then strip_nomad_carrier_systems() end
   player.shipSwap(replacement.candidate, false,
      not replacement.retain_incumbent)
   fit_carrier_systems()
   player.shipvarPush(config.carrier_shipvar, true)
   if incumbent_refund then player.pay(incumbent_refund) end
   owned_additions(true)
   apply_rules(false)

   local message = _("The new carrier is operational.")
   if replacement.retain_incumbent then
      message = message .. "\n\n" .. _(
         "The former carrier fits aboard and has been retained as an ordinary ship.")
   else
      message = message .. "\n\n" .. string.format(
         _("The former carrier did not fit and was refunded for %s."),
         fmt.credits(incumbent_refund))
   end
   tk.msg(_("Nomad Carrier Replaced"), message)
end

function nomad_joyride_started(payload)
   runtime.joyride_started(mem.nomad, payload)
   if not payload or payload.client ~= config.joyride_client then return end
   mem.nomad.active_kind = mem.nomad.active_kind or "virtual"
   mem.nomad.virtual_name = mem.nomad.active_kind == "virtual"
      and player.ship() or nil
   sortie_bays = sortie_bays or pending_sortie_bays or {}
   pending_sortie_bays = nil
   local spawned = payload.pilot
   if spawned and spawned:exists() then
      mothership_pilot = spawned
      for _, candidate in pairs(bay_pilots) do
         if candidate:exists() then candidate:setLeader(spawned) end
      end
      crewmates.attach_mothership(config.joyride_client, spawned)
      local joyride_state = naev.cache().joyride
      if mem.nomad.active_source == "bay" and mem.nomad.controlled_craft
         and joyride_state
         and not joyride_state.hook then
         joyride_state.hook = hook.pilot(spawned, "board",
            "nomad_board_mothership")
      end
      hook.pilot(spawned, "hail", "nomad_hail_mothership")
      restore_bay_pilots()
   end
   hook.safe("nomad_refresh_escort_hooks")
   apply_rules(false)
   if pending_carrier_replacement and mem.nomad.active_kind == "owned" then
      hook.safe("nomad_complete_carrier_replacement")
   end
end

function nomad_board_mothership()
   player.unboard()
   local ok, reason = joyride.end_joyride {
      transfer_mission_cargo = mem.nomad.active_source == "bay",
   }
   if not ok then
      bay_action_message(string.format(_("Unable to board mothership: %s"),
         tostring(reason)))
   end
   return ok
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
   local returned = mem.nomad.controlled_craft
   if returned then
      local state = craft_state(returned)
      if payload.snapshot then
         payload.snapshot.size = payload.snapshot.size
            or (state.snapshot and state.snapshot.size)
         state.snapshot = payload.snapshot
      end
      state.prelaunch = nil
      if pending_return_to_fleet == returned then
         state.phase = "deployed"
      else
         local snapshot = state.snapshot or {}
         state.phase = "cooldown"
         state.remaining = runtime.return_cooldown(snapshot.armour,
            snapshot.shield, snapshot.armour_max)
         state.cooldown_total = state.remaining
         state.destroyed = nil
         state.zero_shields = nil
         state.serviced = true
         set_bay_cooldown(bay_slots[returned], state.remaining,
            state.cooldown_total)
         set_bay_control(bay_slots[returned], false)
      end
   end
   pending_return_to_fleet = nil
   mem.nomad.active_kind = nil
   mem.nomad.active_source = nil
   mem.nomad.virtual_name = nil
   mothership_pilot = nil
   sortie_bays = nil
   crewmates.release_mothership(config.joyride_client)
   local restore_in_space = is_carrier(player.ship()) and not player.isLanded()
   if restore_in_space then
      for _, candidate in pairs(bay_pilots) do
         if candidate:exists() then candidate:setLeader(player.pilot()) end
      end
   end
   if pending_carrier_replacement then
      finalize_carrier_replacement()
   else
      apply_rules(false)
   end
   if restore_in_space then restore_bay_pilots() end
   mem.nomad.controlled_craft = nil
end

function nomad_mothership_restored(payload)
   if not payload or payload.client ~= config.joyride_client then return end
   player.shipvarPush(config.carrier_shipvar, true, payload.name)
end

function nomad_hail_mothership()
   player.commClose()
   if mothership_hail_pending then return end
   mothership_hail_pending = true
   hook.timer(0.1, "nomad_complete_mothership_hail")
end

function nomad_complete_mothership_hail()
   mothership_hail_pending = false
   if mem.nomad.active_source == "command" then
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
   if mem.nomad.active_source == "bay" and mem.nomad.controlled_craft then
      pending_return_to_fleet = mem.nomad.controlled_craft
      local returning_state = craft_state(pending_return_to_fleet)
      returning_state.snapshot = pilot_snapshot(player.pilot())
      returning_state.redeploy_transform = pilot_transform(player.pilot())
   end
   local ok, reason = joyride.end_joyride {
      transfer_mission_cargo = mem.nomad.active_source == "bay",
   }
   if not ok then
      if pending_return_to_fleet then
         craft_state(pending_return_to_fleet).redeploy_transform = nil
      end
      pending_return_to_fleet = nil
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
   hook.custom("nomad_integrated_system_activated",
      "nomad_integrated_system_activated")
   hook.update("nomad_update")
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
   -- Saving is disabled during Joyride. If a prior broken session left only
   -- persisted flags behind, no live session can legitimately resume it.
   if mem.nomad.active_sortie and not naev.cache().joyride then
      naev.trigger("joyride_ended", {
         client = config.joyride_client,
         returned_kind = "virtual",
      })
   end
   assert(crewmates.ensure_commander(config.joyride_client, {
      minimum = config.minimum_crew.commander,
      shuttle = config.command_shuttle_for(
         player.pilot():ship():nameRaw()),
      shuttle_profile = profile(),
   }), "Nomad requires an available commander")
   player.fleetCapacitySet(config.fleet_capacity)
   if not player.isLanded() then restore_bay_pilots() end
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
   mem.nomad.crafts = mem.nomad.crafts or {}
   -- Hooks are runtime state. Install them before either dependency is called
   -- so a transient initialization failure cannot make Naev discard the event.
   register_hooks()
   evt.save(true)
   nomad_defer_initialize()
end
