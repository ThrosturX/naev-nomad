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
local unstable_wormhole = require "nomad.wormhole"

local mothership_pilot
local info_buttons = {}
local bay_pilots = {}
local bay_slots = {}
local known_owned = {}
local parking_requested
local parking_request_attempts = 0
local parking_reuse_record
local parking_sequence = 0
local wormhole_sequence = 0
local departed_cleanup_pending = false
local pending_sortie_bays
local pending_bay_transfer
local pending_return_to_fleet
local maintenance_hook
local parking_cleanup_token = 0
local initialize_attempts = 0
local parking_fleet_backup
local parking_manual_control = false
local parking_braking = false
local parking_brake_hook
local parking_pilot
local parking_outfit_id
local parking_outfit_enabled
local parking_finalizing = false
local parking_bay_guard_token = 0
local register_actions
local hooks_installed = false
local is_carrier
local sortie_bays
local pending_acquisition
local pending_carrier_replacement
local mothership_weapon_sets
local carrier_conversion = false
local carrier_landing_spobs = {}
local carrier_landing_system
local stored_carrier_bays
local remove_bay_pilot
local cancel_pending_parking
local landed_mothership_paused = false

local function forget_spob(name)
   local candidate = spob.get(name)
   if candidate then candidate:setKnown(false) end
end

local function forget_wormhole_spobs()
   for _name_index, name in ipairs({
      config.wormhole.source_spob,
      config.wormhole.target_spob,
   }) do
      forget_spob(name)
   end
end

local function close_wormhole_pair(show_message)
   local diff_name = mem.nomad.wormhole_diff
   local was_open = type(diff_name) == "string"
      and diff.isApplied(diff_name)
   if type(diff_name) == "string" and diff.isApplied(diff_name) then
      diff.remove(diff_name)
   end
   mem.nomad.wormhole_diff = nil
   forget_wormhole_spobs()
   forget_spob(config.parking.spob)
   if type(diff_name) == "string" and diff.isApplied(diff_name) then
      tk.msg(_("Wormhole Collapse"),
         _("Naev did not remove the unstable wormhole movement diff."))
      return false
   end
   if show_message and was_open then
      player.msg(_("The unstable wormhole collapses as you return aboard the carrier."))
   end
   return true
end

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
      local cooling = shared.nomad_bay_cooldowns[id] or {}
      cooling.remaining = remaining
      cooling.total = math.max(remaining, total or remaining)
      shared.nomad_bay_cooldowns[id] = cooling
   else
      shared.nomad_bay_cooldowns[id] = nil
   end
end

local function set_parking_outfit_state(on)
   if not parking_outfit_id then return end
   local shared = naev.cache()
   shared.nomad_integrated_states = shared.nomad_integrated_states or {}
   shared.nomad_integrated_states[parking_outfit_id] = on and "arming" or "off"
end

local function reset_integrated_outfit(pilot, outfit_id)
   if not pilot or not outfit_id then return end
   -- player.shipSwap runs onremove/onadd but does not rerun outfit init. Reset
   -- the native slot while this carrier is still the player ship so Joyride
   -- cannot store an enabled Core and restore it as the next toggle's input.
   pcall(pilot.outfitInitSlot, pilot, outfit_id)
end

local function restore_operational_core_state()
   if not is_carrier(player.ship()) then return end
   local shared = naev.cache()
   shared.nomad_integrated_states = shared.nomad_integrated_states or {}
   local choices = shared.nomad_parking_core_choices
   local guards = shared.nomad_parking_bay_guards
   for id, state in pairs(shared.nomad_integrated_states) do
      if state == "arming" or state == "armed" then
         shared.nomad_integrated_states[id] = "off"
      end
      if choices then choices[id] = nil end
      if guards then guards[id] = nil end
   end
   local pilot = player.pilot()
   for id, installed in pairs(pilot:outfits()) do
      if installed and installed:nameRaw() == config.operational_core then
         shared.nomad_integrated_states[id] = "off"
         if choices then choices[id] = nil end
         if guards then guards[id] = nil end
         reset_integrated_outfit(pilot, id)
      end
   end
end

local function protect_parking_core_from_bay_toggle()
   if not parking_requested or not parking_outfit_id then return end
   parking_bay_guard_token = parking_bay_guard_token + 1
   local token = parking_bay_guard_token
   local shared = naev.cache()
   shared.nomad_parking_bay_guards =
      shared.nomad_parking_bay_guards or {}
   shared.nomad_parking_bay_guards[parking_outfit_id] = token
   hook.timer(0.01, "nomad_clear_parking_bay_guard",
      parking_outfit_id, token)
end

function nomad_clear_parking_bay_guard(outfit_id, token)
   local guards = naev.cache().nomad_parking_bay_guards
   if guards and guards[outfit_id] == token then
      guards[outfit_id] = nil
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

local function snapshot_weapon_sets(subject)
   local result = {}
   for id = 1, 10 do
      result[id] = {}
      for _, slot in ipairs(subject:weapsetList(id)) do
         result[id][#result[id] + 1] = slot
      end
   end
   return result
end

local function restore_weapon_sets(subject, saved)
   if not saved then return end
   for id = 1, 10 do
      local current = subject:weapsetList(id)
      for _, slot in ipairs(current) do
         subject:weapsetRm(id, slot)
      end
      for _, slot in ipairs(saved[id] or {}) do
         if subject:outfits()[slot] then subject:weapsetAdd(id, slot) end
      end
   end
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
   snapshot.weapon_sets = snapshot_weapon_sets(subject)
   return snapshot
end

local function pilot_transform(subject)
   local x, y = subject:pos():get()
   local vx, vy = subject:vel():get()
   return {
      x = x, y = y, direction = subject:dir(),
      vx = vx, vy = vy,
   }
end

local function apply_snapshot(subject, snapshot, serviced, zero_shields)
   for _index, fitted in ipairs(snapshot.outfits or {}) do
      if fitted.id then
         local installed = subject:outfits()[fitted.id]
         if (not installed or installed:nameRaw() ~= fitted.name)
            and not subject:outfitAddSlot(
               fitted.name, fitted.id, true, false) then
            return false, string.format(
               _("unable to restore %s in slot %s"),
               fitted.name, tostring(fitted.id))
         end
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
   return true
end

is_carrier = function(name)
   if name == player.ship() then
      return runtime.is_carrier(player.shipvarPeek(config.carrier_shipvar))
   end
   return runtime.is_carrier(player.shipvarPeek(config.carrier_shipvar, name))
end

local function physical_bay_slots(subject)
   subject = subject or player.pilot()
   local physical = {}
   for index, slot in ipairs(subject:ship():getSlots()) do
      local id = slot.id or index
      physical[id] = {
         id = id,
         type = slot.type,
         size = slot.size,
         property = slot.property,
         locked = slot.locked,
      }
   end
   for id, outfit in pairs(subject:outfits()) do
      if outfit then
         local slot = physical[id] or { id = id }
         slot.outfit = outfit:nameRaw()
         physical[id] = slot
      end
   end
   local slots = {}
   for _, slot in pairs(physical) do slots[#slots + 1] = slot end
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
   local physical = {}
   for _, entry in ipairs(player.ships()) do
      if entry.name == name then
         for index, slot in ipairs(entry.ship:getSlots()) do
            local id = slot.id or index
            physical[id] = {
               id = id,
               type = slot.type,
               size = slot.size,
               property = slot.property,
               locked = slot.locked,
            }
         end
         break
      end
   end
   for index, installed in ipairs(player.shipOutfits(name) or {}) do
      local outfit_name = type(installed) == "string"
         and installed or installed:nameRaw()
      physical[index] = physical[index] or { id = index }
      physical[index].outfit = outfit_name
   end
   local slots = {}
   for _, slot in pairs(physical) do
      slots[#slots + 1] = slot
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
   for _, id in pairs(bay_slots) do
      set_bay_control(id, false)
      set_bay_cooldown(id)
   end
   bay_slots = {}
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

local function clear_carrier_landing_rules()
   -- Spob overrides expire when landing or changing systems. In those cases,
   -- restoring the snapshot would incorrectly resurrect an expired override.
   if player.isLanded() or carrier_landing_system ~= system.cur() then
      carrier_landing_spobs = {}
      carrier_landing_system = nil
      return
   end
   for _, entry in ipairs(carrier_landing_spobs) do
      if entry.allowed then
         entry.spob:landAllow(true, entry.allow_message)
      elseif entry.denied then
         entry.spob:landDeny(true, entry.deny_message)
      else
         entry.spob:landDeny(false)
      end
   end
   carrier_landing_spobs = {}
   carrier_landing_system = nil
end

local function apply_carrier_rules()
   clear_carrier_landing_rules()
   -- Prototype saves can retain the old system-wide landing block. Remove it
   -- once, then use only the per-spob rules below.
   if mem.nomad.carrier_land_block then
      player.landAllow(true)
      mem.nomad.carrier_land_block = nil
   end
   if is_carrier(player.ship()) then
      if mem.nomad.parked and player.isLanded() then
         return
      else
         -- Wormholes are spobs, so a system-wide player.landAllow(false)
         -- prevents entering them too. Deny each ordinary spob instead and
         -- leave wormholes (and Nomad's temporary berth) accessible.
         carrier_landing_system = system.cur()
         for _index, candidate in ipairs(system.cur():spobs()) do
            local tags = candidate:tags() or {}
            if not tags.wormhole and candidate:nameRaw() ~= config.parking.spob then
               local denied, deny_message = candidate:getLandDeny()
               local allowed, allow_message = candidate:getLandAllow()
               carrier_landing_spobs[#carrier_landing_spobs + 1] = {
                  spob = candidate,
                  denied = denied,
                  deny_message = deny_message,
                  allowed = allowed,
                  allow_message = allow_message,
               }
               candidate:landDeny(true,
                  _("The carrier cannot land normally. Activate the Nomadic Operational Core to park."))
            end
         end
      end
   end
end

local function apply_rules(show_message)
   apply_carrier_rules()
   local _assignments, violations = audit_now()
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

   carrier_conversion = true
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

   local large_bay_points = runtime.large_bay_points(slots)
   local used_large_bay_points = 0
   for index, slot in ipairs(slots) do
      local bay_outfit = config.bay_outfit_by_slot_size[slot.size]
      local installed = pilot:outfits()[slot.id or index]
      if installed and config.general_bays[installed:nameRaw()] then
         used_large_bay_points = used_large_bay_points
            + (config.general_bays[installed:nameRaw()].large_bay_points or 0)
      end
      if bay_outfit == "Large Ship Bay"
         and used_large_bay_points + 1 > large_bay_points then
         bay_outfit = nil
      end
      if slot.type == "Weapon" and slot.property == "fighter_bay"
         and not slot.locked then
         local id = slot.id or index
         installed = pilot:outfits()[id]
         if installed and (not bay_outfit or installed:nameRaw() ~= bay_outfit) then
            player.outfitAdd(installed:nameRaw(), 1)
            pilot:outfitRmSlot(id)
         end
         if bay_outfit and not pilot:outfits()[id] then
            pilot:outfitAddSlot(bay_outfit, id, true, false)
         end
         if bay_outfit == "Large Ship Bay" then
            used_large_bay_points = used_large_bay_points + 1
         end
      end
   end
   carrier_conversion = false
end

local function ensure_carrier_integrated_systems()
   if not is_carrier(player.ship()) then return end
   local pilot = player.pilot()
   local slots = pilot:ship():getSlots()
   local equipped = {}
   for id, installed in pairs(pilot:outfits()) do
      if installed then equipped[id] = installed:nameRaw() end
   end
   local allocations = retrofit.allocate(
      slots, equipped, config.integrated_systems)
   carrier_conversion = true
   for _, allocation in ipairs(allocations) do
      if not allocation.installed
         and pilot:outfitAddSlot(allocation.outfit,
            allocation.id, true, false) then
         -- Older builds forced a Large Core into the Mule's Medium slot. The
         -- loader moved that invalid outfit to stock; consume that copy when
         -- repairing the now-compatible installation.
         if player.outfitNum(allocation.outfit) > 0 then
            player.outfitRm(allocation.outfit, 1)
         end
      end
   end
   carrier_conversion = false
end

local function strip_nomad_carrier_systems()
   local pilot = player.pilot()
   carrier_conversion = true
   for id, installed in pairs(pilot:outfits()) do
      local name = installed:nameRaw()
      if config.general_bays[name] then
         player.outfitAdd(name, 1)
         pilot:outfitRmSlot(id)
      elseif name == config.operational_core or name == config.shuttle_bay
         or name == config.wormhole_generator then
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

local function reconcile_returned_joyride()
   local shared = naev.cache()
   local state = shared.joyride
   if not runtime.joyride_has_returned(
         state, player.ship(), is_carrier(player.ship())) then
      return false
   end

   local profile = type(state.profile) == "table" and state.profile or {}
   local client = profile.client or config.joyride_client
   local returned_kind = state.kind or "virtual"
   local returned_name = returned_kind == "owned" and state.controlled or nil
   shared.joyride = nil
   shared.player_mothership = nil
   player.allowSave(true)
   player.landAllow(true)
   naev.trigger("joyride_ended", {
      client = client,
      returned_kind = returned_kind,
      returned_name = returned_name,
   })
   return true
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
   if entry and state.snapshot
      and state.snapshot.hull ~= entry.ship:nameRaw() then
      state.snapshot = owned_snapshot(entry, name)
      state.prelaunch = nil
      state.redeploy_transform = nil
      state.serviced = true
   end
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
   local restored, restore_reason = apply_snapshot(candidate, state.snapshot,
      state.serviced, state.zero_shields)
   if not restored then
      candidate:rm()
      return false, restore_reason
   end
   state.snapshot.armour_max = candidate:stats().armour
   state.serviced = nil
   state.zero_shields = nil
   state.prelaunch = state.snapshot
   state.phase = "deployed"
   state.remaining = nil
   state.cooldown_total = nil
   if transform then
      candidate:setDir(transform.direction)
      candidate:setVel(vec2.new(transform.vx or 0, transform.vy or 0))
   end
   state.redeploy_transform = nil
   candidate:setLeader(carrier)
   candidate:setNoClear(true)
   candidate:setFriendly(true)
   candidate:setInvincPlayer(true)
   bay_pilots[name] = candidate
   set_bay_cooldown(bay_slots[name])
   set_bay_control(bay_slots[name], true)
   hook.pilot(candidate, "hail", "nomad_hail_owned", name)
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
            state.phase = "ready"
            state.redeploy_transform = nil
            state.serviced = true
            set_bay_control(bay_slots[name], false)
            set_bay_cooldown(bay_slots[name])
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

local function ensure_maintenance()
   if maintenance_hook then return end
   for _, state in pairs(mem.nomad.crafts or {}) do
      if state.phase == "returning" or state.phase == "cooldown" then
         maintenance_hook = hook.update("nomad_update")
         return
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
   ensure_maintenance()
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
   ensure_maintenance()
end

function nomad_update(dt)
   local leader = mothership_pilot and mothership_pilot:exists()
      and mothership_pilot or (is_carrier(player.ship()) and player.pilot() or nil)
   local pending = false
   for name, state in pairs(mem.nomad.crafts or {}) do
      if state.phase == "returning" then
         local candidate = live_bay_pilot(name)
         if candidate and leader and leader:exists() then
            pending = true
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
         if not ready then pending = true end
      end
   end
   if not pending and maintenance_hook then
      hook.rm(maintenance_hook)
      maintenance_hook = nil
   end
end

function nomad_bay_activated(payload)
   if not payload or not is_carrier(player.ship()) then return end
   local mapped = runtime.map_bay_slots(current_bays(), physical_bay_slots())
   local slot = mapped[payload.id]
   if not slot or slot.bay.outfit ~= payload.outfit then return end
   protect_parking_core_from_bay_toggle()
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
   reconcile_returned_joyride()
   -- A ship swap must never carry an in-progress parking brake or an armed
   -- Core into Joyride. Cancel while the original carrier is still current.
   cancel_pending_parking()
   mothership_weapon_sets = snapshot_weapon_sets(player.pilot())
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
      mothership_weapon_sets = nil
      pending_sortie_bays = nil
      mem.nomad.active_source = previous_source
      bay_action_message(string.format(_("Command bay: %s"), tostring(reason)))
   end
end

function nomad_refresh_after_bay_action()
   apply_rules(false)
end

function nomad_refresh_bay_configuration()
   if is_carrier(player.ship()) then
      local pilot = player.pilot()
      local invalid = runtime.invalid_bay_slots(physical_bay_slots(pilot))
      if #invalid > 0 then
         carrier_conversion = true
         for _, slot in ipairs(invalid) do
            local installed = pilot:outfits()[slot.id]
            if installed and installed:nameRaw() == slot.outfit then
               player.outfitAdd(slot.outfit, 1)
               pilot:outfitRmSlot(slot.id)
            end
         end
         carrier_conversion = false
      end
   end
   apply_rules(false)
end

function nomad_integrated_system_activated(payload)
   if not payload or not is_carrier(player.ship()) then return end
   if payload.action == "park" then
      nomad_park_carrier(payload.id)
   elseif payload.action == "shuttle" then
      nomad_launch_command_shuttle()
   end
end

function nomad_invalid_wormhole_generator(payload)
   local subject = payload and payload.pilot
   local id = payload and payload.id
   if not subject or not id or not subject:exists()
      or subject:shipvarPeek(config.carrier_shipvar) == true then return end
   local installed = subject:outfits()[id]
   if not installed or installed:nameRaw() ~= config.wormhole_generator then
      return
   end
   if subject:outfitRmSlot(id) then
      player.outfitAdd(config.wormhole_generator, 1)
      if subject == player.pilot() then
         player.msg(_("The Unstable Wormhole Generator can only be fitted to the Nomad carrier."))
      end
   end
end

function nomad_wormhole_generator_activated(_payload)
   if not is_carrier(player.ship()) or player.isLanded() then return end
   mem.nomad.wormhole_follow_origin = nil
   local source_system = system.cur()
   local candidates = unstable_wormhole.destination_candidates(
      source_system, system.getAll())
   if #candidates == 0 then
      player.msg(_("The generator cannot lock onto a suitable nearby system."))
      return
   end
   local target_system = candidates[rnd.rnd(1, #candidates)]
   local carrier = player.pilot()
   local source_position = carrier:pos()
      + vec2.newP(carrier:radius() + config.wormhole.source_offset,
         carrier:dir())
   local target_position = vec2.newP(
      target_system:radius() * config.wormhole.target_radius_fraction,
      rnd.angle())
   local source_x, source_y = source_position:get()
   local target_x, target_y = target_position:get()

   if not close_wormhole_pair(false) then return end

   wormhole_sequence = wormhole_sequence + 1
   local diff_name = string.format("%s %s %d", config.wormhole.diff,
      tostring(naev.ticks()), wormhole_sequence)
   local movement = unstable_wormhole.diff_xml(diff_name,
      source_system:nameRaw(), target_system:nameRaw(),
      source_x, source_y, target_x, target_y)
   local called, applied = pcall(diff.newDynamic, movement)
   if not called or not applied or not diff.isApplied(diff_name) then
      if diff.isApplied(diff_name) then diff.remove(diff_name) end
      tk.msg(_("Wormhole Failure"), tostring(
         called and _("Naev rejected the wormhole movement diff") or applied))
      return
   end
   mem.nomad.wormhole_diff = diff_name
   forget_spob(config.parking.spob)
   for _name_index, name in ipairs({
      config.wormhole.source_spob,
      config.wormhole.target_spob,
   }) do
      local mouth = spob.get(name)
      if mouth then mouth:setKnown(true) end
   end
   player.msg(string.format(
      _("An unstable wormhole opens nearby, linked to the %s system."),
      target_system:name()))
end

function nomad_wormhole_entering(payload)
   local origin = payload and payload.origin
   if type(origin) ~= "string" or not mem.nomad.active_sortie
      or is_carrier(player.ship()) then return end
   if mem.nomad.wormhole_follow_origin then return end
   local paused, reason = joyride.follow_mothership(false)
   if not paused then
      tk.msg(_("Wormhole Failure"), tostring(reason))
      return
   end
   mem.nomad.wormhole_follow_origin = origin
   if mothership_pilot and mothership_pilot:exists() then
      crewmates.release_mothership(config.joyride_client, mothership_pilot)
   end
   mothership_pilot = nil
end

local function restore_wormhole_mothership()
   local origin = mem.nomad.wormhole_follow_origin
   local current_system = system.cur()
   if not origin or not current_system
      or current_system:nameRaw() ~= origin then return true end

   local enabled, reason = joyride.follow_mothership(true)
   if not enabled then
      tk.msg(_("Mothership Return"), tostring(reason))
      return false
   end
   local spawned = joyride.spawn_mothership()
   if not spawned then
      joyride.follow_mothership(false)
      tk.msg(_("Mothership Return"),
         _("Joyride did not restore the mothership"))
      return false
   end
   mem.nomad.wormhole_follow_origin = nil
   return true
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

function nomad_hail_owned(candidate, name)
   -- Close the stock escort comm immediately. The actual ship swap remains
   -- deferred so its pilot can be removed safely after the hail hook returns.
   player.commClose()
   hook.timer(0.1, "nomad_begin_owned_joyride", name, candidate)
end

function nomad_begin_owned_joyride(name, expected)
   if not name then return end
   -- Let Naev finish constructing the hail window before Joyride removes the
   -- deployed pilot. Invalidating it directly in the pilot hail hook makes the
   -- comm backend dereference a pilot that no longer exists.
   local template = live_bay_pilot(name)
   if not template or (expected and template ~= expected) then return end
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
      local ok, reason = joyride.end_joyride { seat_transfer = true }
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
   cancel_pending_parking()
   mothership_weapon_sets = snapshot_weapon_sets(player.pilot())
   pending_sortie_bays = current_bays()
   local state = craft_state(name)
   local previous_phase = state.phase
   local previous_craft = mem.nomad.controlled_craft
   local previous_kind = mem.nomad.active_kind
   local previous_source = mem.nomad.active_source
   state.phase = "controlled"
   mem.nomad.controlled_craft = name
   mem.nomad.active_kind = "owned"
   mem.nomad.active_source = "bay"
   local controlled, reason = joyride.begin_owned_sortie(
      name, template, profile())
   if not controlled then
      mothership_weapon_sets = nil
      pending_sortie_bays = nil
      state.phase = previous_phase
      bay_pilots[name] = nil
      mem.nomad.controlled_craft = previous_craft
      mem.nomad.active_kind = previous_kind
      mem.nomad.active_source = previous_source
      tk.msg(_("Seat Transfer"), tostring(reason))
      restore_bay_pilots()
      return
   end
   bay_pilots[name] = nil
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

local function forget_parked_spob()
   forget_spob(config.parking.spob)
end

local function parked_diff_apply(record)
   forget_parked_spob()
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
   -- A local map bought in an older build may have persisted the temporary
   -- location. The carrier berth must never remain part of map knowledge.
   forget_parked_spob()
end

local function copy_plain(value)
   if type(value) ~= "table" then return value end
   local result = {}
   for key, item in pairs(value) do result[copy_plain(key)] = copy_plain(item) end
   return result
end

local function capture_parking_fleet()
   local backup = {}
   for name, state in pairs(mem.nomad.crafts or {}) do
      backup[name] = copy_plain(state)
      local candidate = live_bay_pilot(name)
      if candidate then backup[name].snapshot = pilot_snapshot(candidate) end
   end
   return backup
end

local function restore_parking_fleet()
   if not parking_fleet_backup then return end
   mem.nomad.crafts = parking_fleet_backup
   parking_fleet_backup = nil
   restore_bay_pilots()
   ensure_maintenance()
end

local function parking_rollback(reason)
   local record = mem.nomad.parked
   mem.nomad.parked = nil
   if mem.nomad.departed_parking ~= record then
      parked_diff_remove(record)
   end
   restore_parking_fleet()
   if mem.nomad.departed_parking == record then
      nomad_apply_rules()
   else
      apply_rules(false)
   end
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

local function stop_parking_brake_hook()
   if not parking_brake_hook then return end
   hook.rm(parking_brake_hook)
   parking_brake_hook = nil
end

local function parking_release_control(pilot)
   stop_parking_brake_hook()
   pilot = parking_pilot or pilot
   local outfit_id = parking_outfit_id
   set_parking_outfit_state(false)
   reset_integrated_outfit(pilot, outfit_id)
   if outfit_id then
      local choices = naev.cache().nomad_parking_core_choices
      if choices then choices[outfit_id] = nil end
      local guards = naev.cache().nomad_parking_bay_guards
      if guards then guards[outfit_id] = nil end
   end
   parking_outfit_id = nil
   parking_outfit_enabled = nil
   parking_finalizing = false
   if parking_manual_control then
      parking_manual_control = false
      pcall(pilot.control, pilot, false)
   end
   parking_braking = false
   parking_pilot = nil
end

cancel_pending_parking = function(outfit_id)
   if outfit_id and parking_outfit_id and outfit_id ~= parking_outfit_id then
      return
   end
   local shared = naev.cache()
   local pilot = player.pilot()
   for id, state in pairs(shared.nomad_integrated_states or {}) do
      if state == "arming" or state == "armed" then
         shared.nomad_integrated_states[id] = "off"
         if shared.nomad_parking_core_choices then
            shared.nomad_parking_core_choices[id] = nil
         end
         if shared.nomad_parking_bay_guards then
            shared.nomad_parking_bay_guards[id] = nil
         end
         reset_integrated_outfit(pilot, id)
      end
   end
   if not parking_requested and not parking_outfit_id then return end
   parking_requested = nil
   parking_request_attempts = 0
   parking_reuse_record = nil
   parking_release_control(player.pilot())
end

local function parking_brake(pilot)
   local flags = pilot:flags()
   if not flags.manualcontrol then
      local ok = pcall(pilot.control, pilot, true)
      if not ok then return false end
      parking_manual_control = true
   end
   if parking_braking then return true end
   local ok = pcall(pilot.brake, pilot)
   if ok then
      parking_braking = true
      set_parking_outfit_state(true)
      parking_brake_hook = hook.update("nomad_update_parking_brake")
      return true
   end
   parking_release_control(pilot)
   return false
end

local function parking_is_stopped(pilot)
   local velocity = pilot:vel()
   local vx, vy = velocity:get()
   return parking.is_stopped(vx, vy)
end

function nomad_update_parking_brake()
   if not parking_requested then
      stop_parking_brake_hook()
      return
   end
   if tk.isOpen() then return end
   if not parking_is_stopped(player.pilot()) then return end
   -- Naev's brake task clears active outfits when it is popped on the next
   -- AI frame. Capture the Core choice now, after physics crossed the stop
   -- threshold but before that task cleanup can run.
   stop_parking_brake_hook()
   nomad_complete_parking()
end

local function parking_outfit_is_on()
   if not parking_outfit_id then return true end
   local choices = naev.cache().nomad_parking_core_choices or {}
   return choices[parking_outfit_id] == true
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
      parking_request_attempts = parking_request_attempts + 1
      if parking_request_attempts <= 120 then
         hook.timer(0.5, "nomad_complete_parking")
      else
         parking_requested = nil
         parking_reuse_record = nil
         parking_release_control(player.pilot())
         player.msg(_("Parking cancelled because the Info window remained open."))
         nomad_apply_rules()
      end
      return
   end

   local ok, reason = parking_status()
   if not ok then
      parking_requested = nil
      parking_request_attempts = 0
      parking_reuse_record = nil
      parking_release_control(player.pilot())
      tk.msg(_("Unable to Park Carrier"), tostring(reason))
      nomad_apply_rules()
      return
   end

   local pilot = player.pilot()
   if not parking_is_stopped(pilot) then
      -- Match a normal landing attempt: brake first, then complete the
      -- transition only after the carrier has safely come to a stop.
      if not parking_brake(pilot) then
         parking_requested = nil
         parking_request_attempts = 0
         parking_reuse_record = nil
         tk.msg(_("Unable to Park Carrier"),
            _("The carrier is moving too fast to park."))
         nomad_apply_rules()
         return
      end
      return
   end
   -- Naev can clear an active outfit's native state as it cleans up the brake
   -- task. Capture it on one final stopped poll, before releasing control.
   -- Info-menu parking has no active outfit, so it keeps its direct flow.
   if parking_outfit_id and not parking_finalizing then
      parking_outfit_enabled = parking_outfit_is_on()
      parking_finalizing = true
      hook.timer(0.1, "nomad_complete_parking")
      return
   end

   local outfit_enabled = parking_outfit_enabled
   parking_requested = nil
   parking_request_attempts = 0
   if parking_outfit_id and not outfit_enabled then
      parking_reuse_record = nil
      parking_release_control(pilot)
      return
   end
   parking_release_control(pilot)
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
   local record
   if reused then
      reused.system = system_name
      reused.x = x
      reused.y = y
      reused.direction = pilot:dir()
      reused.carrier = player.ship()
      record = reused
   else
      record = parking.record(system_name, x, y, pilot:dir(),
         next_parking_diff_name(), player.ship())
   end
   mem.nomad.parked = record
   local target = spob.get(config.parking.spob)
   if not target then
      parking_rollback(_("the parked-carrier landing target is unavailable"))
      return
   end
   if not reused then
      ok, reason = parked_diff_apply(record)
      if not ok then
         parking_rollback(reason)
         return
      end
   end
   parking_fleet_backup = capture_parking_fleet()
   service_bay_fleet()
   player.landAllow(true)
   ok, reason = pcall(player.land, target)
   if not ok then
      parking_rollback(reason)
   end
end

function nomad_park_carrier(outfit_id)
   local ok, reason = parking_status()
   if not ok then
      tk.msg(_("Unable to Park Carrier"), tostring(reason))
      return
   end
   parking_outfit_id = outfit_id
   parking_pilot = player.pilot()
   parking_outfit_enabled = nil
   parking_finalizing = false
   local pilot = player.pilot()
   if parking_is_stopped(pilot) then
      -- Do not create a brake task when already stopped. Popping that task
      -- clears active outfits before the first deferred Core poll.
      set_parking_outfit_state(true)
   elseif not parking_brake(pilot) then
      parking_reuse_record = nil
      tk.msg(_("Unable to Park Carrier"),
         _("The carrier is moving too fast to park."))
      nomad_apply_rules()
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
      departed_cleanup_pending = false
      parking_cleanup_token = parking_cleanup_token + 1
      parking_requested = true
      parking_request_attempts = 0
      hook.timer(0.1, "nomad_complete_parking")
      return
   end
   parking_requested = true
   parking_request_attempts = 0
   if tk.isOpen() then
      bay_action_message(_("Close the Info window to park the carrier."))
      hook.timer(0.1, "nomad_complete_parking")
      return
   end
   -- Let the Core finish its activation callback and render its native on
   -- state before the first stopped poll captures the player's choice.
   if outfit_id then
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
         hook.timer(0.2, "nomad_verify_parking_landing", mem.nomad.parked)
         return
      end
      if mem.nomad.departed_parking == mem.nomad.parked then
         mem.nomad.departed_parking = nil
         departed_cleanup_pending = false
         parking_cleanup_token = parking_cleanup_token + 1
      end
      parking_fleet_backup = nil
      forget_parked_spob()
   end
   nomad_apply_rules()
   -- Joyride's delayed system-entry callback must not recreate the carrier
   -- while the player is landed. Besides moving a ship that should remain at
   -- its saved position, that callback replaces the vector with system.cur(),
   -- which Naev later interprets as a same-system jump-in origin.
   if mem.nomad.active_sortie and naev.cache().joyride then
      local paused = joyride.follow_mothership(false)
      landed_mothership_paused = paused == true
   end
end

function nomad_verify_parking_landing(record)
   if mem.nomad.parked ~= record or not player.isLanded() then return end
   local current = spob.cur()
   if current and current:nameRaw() == config.parking.spob then
      if mem.nomad.departed_parking == record then
         mem.nomad.departed_parking = nil
         departed_cleanup_pending = false
         parking_cleanup_token = parking_cleanup_token + 1
      end
      forget_parked_spob()
      nomad_apply_rules()
      return
   end
   mem.nomad.parked = nil
   mem.nomad.departed_parking = record
   restore_parking_fleet()
   apply_rules(false)
   tk.msg(_("Unable to Park Carrier"),
      _("The carrier landed at an unexpected location; the temporary berth will be removed after takeoff."))
end

function nomad_restore_parked_diff()
   -- Also migrates saves made after a local map recorded the temporary berth.
   forget_parked_spob()
   if mem.nomad.parked then
      mem.nomad.parked.diff = mem.nomad.parked.diff
         or next_parking_diff_name()
      mem.nomad.parked.carrier = mem.nomad.parked.carrier or player.ship()
   elseif not mem.nomad.departed_parking then
      parked_diff_remove()
   end
   hook.safe("nomad_initialize")
end

local function restore_parking_transform(record)
   if not record then return false, _("the parking record is unavailable") end
   local current_system = system.cur()
   if not current_system or current_system:nameRaw() ~= record.system then
      local ok, reason = pcall(player.teleport, record.system, true, true)
      if not ok then
         return false, reason
      end
   end
   local pilot = player.pilot()
   pilot:setPos(vec2.new(record.x, record.y))
   pilot:setDir(record.direction)
   pilot:setVel(vec2.new(0, 0))
   return true
end

local function restore_carrier_after_takeoff(record)
   local ok, reason = restore_parking_transform(record)
   if not ok then
      tk.msg(_("Unable to Restore Carrier Location"), tostring(reason))
      hook.timer(0.25, "nomad_retry_carrier_restore", record, 1)
      return false
   end
   mem.nomad.parked = nil
   mem.nomad.departed_parking = record
   nomad_apply_rules()
   return true
end

function nomad_retry_carrier_restore(record, attempt)
   if mem.nomad.parked ~= record or player.isLanded()
      or not is_carrier(player.ship()) then return end
   local ok = restore_parking_transform(record)
   if ok then
      mem.nomad.parked = nil
      mem.nomad.departed_parking = record
      nomad_apply_rules()
      return
   end
   attempt = (attempt or 0) + 1
   if attempt <= 20 then
      hook.timer(0.25, "nomad_retry_carrier_restore", record, attempt)
   else
      local position = player.pilot():pos()
      record.system = system.cur():nameRaw()
      record.x, record.y = position:get()
      record.direction = player.pilot():dir()
      mem.nomad.parked = nil
      mem.nomad.departed_parking = record
      tk.msg(_("Carrier Location Changed"), _(
         "The original parking location could not be restored; departure completed at the current location."))
      nomad_apply_rules()
   end
end

local function fallback_to_carrier(record, selected, reason)
   local swapped, swap_reason = pcall(player.shipSwap,
      record.carrier, false, false)
   if not swapped then
      local target = spob.get(config.parking.spob)
      player.landAllow(true)
      if target then pcall(player.land, target) end
      tk.msg(_("Unable to Launch Ship"), string.format(
         _("%s\n\nUnable to restore the carrier: %s"),
         tostring(reason), tostring(swap_reason)))
      return
   end
   local state = craft_state(selected)
   state.phase = "ready"
   state.prelaunch = nil
   mem.nomad.controlled_craft = nil
   mem.nomad.active_kind = nil
   mem.nomad.active_source = nil
   mem.nomad.active_sortie = nil
   sortie_bays = nil
   mem.nomad.parked = nil
   mem.nomad.departed_parking = record
   tk.msg(_("Unable to Launch Ship"), string.format(
      _("%s\n\nControl was returned to the carrier."), tostring(reason)))
   nomad_apply_rules()
end

function nomad_takeoff()
   -- Joyride adopts a landed ship selection before takeoff. Reconcile the
   -- public session state here as a lifecycle boundary in case its custom
   -- controlled-ship notification was missed or came before this event was
   -- ready. An owned controlled ship is no longer the command shuttle.
   local joyride_state = naev.cache().joyride
   if mem.nomad.active_source == "command" and joyride_state
      and joyride_state.profile
      and joyride_state.profile.client == config.joyride_client
      and joyride_state.kind == "owned" then
      local controlled = joyride_state.controlled or player.ship()
      if controlled == player.ship() then
         local previous = runtime.controlled_ship_changed(mem.nomad, controlled)
         if previous and previous ~= controlled then
            runtime.service_craft(craft_state(previous))
         end
         craft_state(controlled).phase = "controlled"
      end
   end
   if landed_mothership_paused then
      local enabled, reason = joyride.follow_mothership(true)
      local spawned = enabled and joyride.spawn_mothership() or nil
      if enabled and spawned then
         landed_mothership_paused = false
      else
         joyride.follow_mothership(false)
         tk.msg(_("Mothership Return"), tostring(reason
            or _("Joyride did not restore the mothership")))
      end
   end
   if mem.nomad.parked then
      if not is_carrier(player.ship()) then
         local record = mem.nomad.parked
         local bays = stored_carrier_bays(record.carrier)
         local selected = player.ship()
         local ok, reason = restore_parking_transform(record)
         if not ok then
            tk.msg(_("Unable to Restore Carrier Location"), tostring(reason))
            nomad_apply_rules()
            return
         end
         local state = craft_state(selected)
         local previous_phase = state.phase
         local previous_craft = mem.nomad.controlled_craft
         local previous_kind = mem.nomad.active_kind
         local previous_source = mem.nomad.active_source
         state.snapshot = state.snapshot
            or owned_snapshot(find_owned(selected), selected)
         state.prelaunch = state.snapshot
         state.phase = "controlled"
         mem.nomad.controlled_craft = selected
         mem.nomad.active_kind = "owned"
         mem.nomad.active_source = "bay"
         mem.nomad.virtual_name = nil
         sortie_bays = bays
         ok, reason = joyride.begin_stored_owned_sortie(
            record.carrier, profile(), vec2.new(record.x, record.y),
            record.direction)
         if not ok then
            state.phase = previous_phase
            state.prelaunch = nil
            mem.nomad.controlled_craft = previous_craft
            mem.nomad.active_kind = previous_kind
            mem.nomad.active_source = previous_source
            sortie_bays = nil
            fallback_to_carrier(record, selected, reason)
            return
         end
         mem.nomad.parked = nil
         mem.nomad.departed_parking = record
         nomad_apply_rules()
         return
      end
      local record = mem.nomad.parked
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
   restore_wormhole_mothership()
   local departed = mem.nomad.departed_parking
   if departed and not departed_cleanup_pending and not player.isLanded() then
      departed_cleanup_pending = true
      parking_cleanup_token = parking_cleanup_token + 1
      hook.timer(0.2, "nomad_remove_departed_parking",
         parking_cleanup_token, departed)
   end
   restore_bay_pilots()
   ensure_maintenance()
   apply_rules(false)
end

function nomad_remove_departed_parking(token, record, attempt)
   if token ~= parking_cleanup_token then return end
   local departed = mem.nomad.departed_parking
   if not departed or departed ~= record or mem.nomad.parked == record
      or parking_reuse_record == record then
      departed_cleanup_pending = false
      return
   end
   if player.isLanded() then
      attempt = (attempt or 0) + 1
      if attempt <= 20 then
         hook.timer(0.25, "nomad_remove_departed_parking",
            token, record, attempt)
      else
         departed_cleanup_pending = false
      end
      return
   end
   local pilot = player.pilot()
   local flags = pilot and pilot:flags() or {}
   if flags.hyperspace or flags.jumping or flags.landing or flags.takingoff then
      attempt = (attempt or 0) + 1
      if attempt <= 20 then
         hook.timer(0.25, "nomad_remove_departed_parking",
            token, record, attempt)
      else
         departed_cleanup_pending = false
      end
      return
   end
   departed_cleanup_pending = false
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
   local ok, reason = joyride.end_joyride()
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
   if not payload or payload.client ~= config.joyride_client then return end
   local spawned = payload.pilot
   runtime.joyride_started(mem.nomad, payload)
   mem.nomad.active_kind = mem.nomad.active_kind or "virtual"
   mem.nomad.virtual_name = mem.nomad.active_kind == "virtual"
      and player.ship() or nil
   sortie_bays = sortie_bays or pending_sortie_bays or {}
   pending_sortie_bays = nil
   if spawned and spawned:exists() then
      mothership_pilot = spawned
      for _, candidate in pairs(bay_pilots) do
         if candidate:exists() then candidate:setLeader(spawned) end
      end
      crewmates.attach_mothership(config.joyride_client, spawned)
      hook.pilot(spawned, "hail", "nomad_hail_mothership")
      restore_bay_pilots()
   end
   apply_rules(false)
   if pending_carrier_replacement and mem.nomad.active_kind == "owned" then
      hook.safe("nomad_complete_carrier_replacement")
   end
end

function nomad_joyride_returning(payload)
   if not payload or payload.client ~= config.joyride_client
      or mem.nomad.active_source ~= "bay" then return end
   if payload.seat_transfer then return end
   local returned = payload.returned_name or mem.nomad.controlled_craft
   if not returned then return end
   local state = craft_state(returned)
   state.snapshot = state.prelaunch or state.snapshot
      or owned_snapshot(find_owned(returned), returned)
   if state.snapshot then
      state.snapshot.armour = payload.armour or state.snapshot.armour
      state.snapshot.shield = payload.shield or state.snapshot.shield
      state.snapshot.stress = payload.stress or state.snapshot.stress
      state.snapshot.armour_max = payload.armour_max
         or state.snapshot.armour_max
      state.snapshot.cargo = {}
   end
   state.redeploy_transform = nil
   pending_return_to_fleet = nil
end

function nomad_shuttle_returned(payload)
   if payload and payload.client == config.joyride_client then
      mem.nomad.active_kind = "owned"
      mem.nomad.virtual_name = nil
      hook.safe("nomad_delayed_audit", false)
   end
end

function nomad_joyride_controlled_changed(payload)
   if not payload or payload.client ~= config.joyride_client
      or not payload.controlled then return end
   local previous = runtime.controlled_ship_changed(
      mem.nomad, payload.controlled)
   if previous and previous ~= payload.controlled then
      runtime.service_craft(craft_state(previous))
   end
   craft_state(payload.controlled).phase = "controlled"
   apply_rules(false)
end

function nomad_mothership_restored(payload)
   if not payload or payload.client ~= config.joyride_client then return end
   player.shipvarPush(config.carrier_shipvar, true, payload.name)
end

function nomad_joyride_ended(payload)
   runtime.joyride_ended(mem.nomad, payload)
   if not payload or payload.client ~= config.joyride_client then return end
   landed_mothership_paused = false
   mem.nomad.wormhole_follow_origin = nil
   close_wormhole_pair(true)
   -- Joyride has restored the owned carrier at this point. Establish the
   -- Core's complete post-return state regardless of its pre-swap native or
   -- cached state so the next player toggle is always a fresh activation.
   cancel_pending_parking()
   restore_operational_core_state()
   restore_weapon_sets(player.pilot(), mothership_weapon_sets)
   mothership_weapon_sets = nil
   local returned = mem.nomad.controlled_craft
   returned = payload.returned_name or returned
   if returned then
      local state = craft_state(returned)
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
         ensure_maintenance()
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

function nomad_hail_mothership(carrier)
   player.commClose()
   local state = naev.cache().joyride
   if not state then return end
   local token = state.token or state
   hook.timer(0.1, "nomad_complete_mothership_hail", token)
end

function nomad_complete_mothership_hail(token)
   local state = naev.cache().joyride
   if not state or (state.token or state) ~= token then return end
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
   local ok, reason = joyride.end_joyride { seat_transfer = true }
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
   hook.custom("joyride_returning", "nomad_joyride_returning")
   hook.custom("joyride_shuttle_returned", "nomad_shuttle_returned")
   hook.custom("joyride_controlled_ship_changed",
      "nomad_joyride_controlled_changed")
   hook.custom("joyride_mothership_restored", "nomad_mothership_restored")
   hook.custom("joyride_ended", "nomad_joyride_ended")
   hook.custom("nomad_bay_activated", "nomad_bay_activated")
   hook.custom("nomad_bay_configuration_changed",
      "nomad_bay_configuration_changed")
   hook.custom("nomad_occupied_bay_removed", "nomad_occupied_bay_removed")
   hook.custom("nomad_integrated_system_activated",
      "nomad_integrated_system_activated")
   hook.custom("nomad_invalid_wormhole_generator",
      "nomad_invalid_wormhole_generator")
   hook.custom("nomad_wormhole_generator_activated",
      "nomad_wormhole_generator_activated")
   hook.custom("nomad_wormhole_entering", "nomad_wormhole_entering")
   hooks_installed = true
end

function nomad_initialize()
   -- Load events run while Naev is still restoring the landed spob. Crewmates
   -- may need that spob when it creates the required commander, so this work
   -- is deliberately deferred to a safe hook after the load transition.
   if not crewmates.is_ready() then
      initialize_attempts = initialize_attempts + 1
      if initialize_attempts <= 240 then
         hook.timer(initialize_attempts < 20 and 0.1 or 0.5,
            "nomad_initialize")
      else
         player.msg(_("Nomad initialization stopped because Crewmates did not become ready."))
      end
      return
   end
   if player.isLanded() and not spob.cur() then
      initialize_attempts = initialize_attempts + 1
      if initialize_attempts <= 240 then
         hook.timer(initialize_attempts < 20 and 0.1 or 0.5,
            "nomad_initialize")
      end
      return
   end
   initialize_attempts = 0
   reconcile_returned_joyride()
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
   forget_parked_spob()
   mem.nomad.wormhole_follow_origin = nil
   close_wormhole_pair(false)
   ensure_carrier_integrated_systems()
   if not player.isLanded() then restore_bay_pilots() end
   ensure_maintenance()
   owned_additions(true)
   register_actions()
   apply_rules(false)
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
