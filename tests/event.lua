package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path
local swap_call
local handoff_call
local borrow_call
local comm_close_calls = 0
local end_joyride_call
local command_launch_call
local command_launch_failure
local player_weapon_sets = {}
local live_pilots = {}
local applied_health = {}
package.preload.joyride = function()
   return {
      begin_owned_sortie = function(name, template, profile)
         swap_call = {
            name = name, template = template, profile = profile,
         }
         if template and template.rm then template:rm() end
         naev.cache().joyride = {
            profile = profile, mothership = player.ship(),
            controlled = name, kind = "owned",
         }
         return player.pilot()
      end,
      end_joyride = function(options)
         end_joyride_call = options or {}
         local state = naev.cache().joyride
         if state and _G.nomad_joyride_returning then
            nomad_joyride_returning {
               client = state.profile and state.profile.client or "nomad",
               returned_kind = state.kind,
               returned_name = state.controlled,
               seat_transfer = end_joyride_call.seat_transfer == true,
            }
         end
         naev.cache().joyride = nil
         return true
      end,
      handoff_to_owned = function(name)
         handoff_call = name
         return true
      end,
      begin_stored_owned_sortie = function(mothership, profile, position, direction)
         borrow_call = {
            name = player.ship(), profile = profile,
            mothership = mothership,
            transform = { pos = position, dir = direction },
         }
         naev.cache().joyride = {
            profile = profile, mothership = mothership,
            controlled = player.ship(), kind = "owned",
            pilot = {
               exists = function() return true end,
               outfits = function() return {} end,
               setActiveBoard = function() end,
            },
         }
         if nomad_joyride_started then
            nomad_joyride_started {
               client = profile.client,
               pilot = naev.cache().joyride.pilot,
            }
         end
         return true
      end,
      takeoff = function()
         local state = naev.cache().joyride
         if state and state.follow_mothership ~= false and not state.pilot then
            state.pilot = {
               exists = function() return true end,
               outfits = function() return {} end,
               setActiveBoard = function() end,
            }
         end
         return true
      end,
      follow_mothership = function(enabled)
         local state = naev.cache().joyride
         if not state then return false, "no Joyride session is active" end
         state.follow_mothership = enabled ~= false
         return true
      end,
      mothership_follows = function()
         local state = naev.cache().joyride
         return state ~= nil and state.follow_mothership ~= false
      end,
      spawn_mothership = function()
         local state = naev.cache().joyride
         if not state or state.follow_mothership == false then return nil end
         if state.pilot and state.pilot:exists() then return state.pilot end
         state.pilot = {
            exists = function() return true end,
            outfits = function() return {} end,
            setActiveBoard = function() end,
         }
         if nomad_joyride_started then
            nomad_joyride_started {
               client = state.profile and state.profile.client or "nomad",
               pilot = state.pilot,
            }
         end
         return state.pilot
      end,
   }
end
package.preload.format = function()
   return {
      credits = function(amount) return tostring(amount) .. " credits" end,
      f = function(text, values)
         return (text:gsub("{([%w_]+)}", function(key)
            return tostring(values[key])
         end))
      end,
   }
end
local toolkit_open = false
local starting_choice = 1
local starting_menu
tk = {
   msg = function() end,
   choice = function(...)
      starting_menu = { ... }
      return starting_choice
   end,
   yesno = function() return true end,
   isOpen = function() return toolkit_open end,
}
_ = function(message) return message end

local ensured_commander
local ensure_commander_calls = 0
local attached_mothership
local released_mothership
local mothership_boardable
local commander = {
   name = "Nomad Commander",
   faction = "Independent",
   shuttle = { out = nil },
}
package.preload["crewmates.api"] = function()
   return {
      is_ready = function() return true end,
      ensure_commander = function(client, options)
         ensure_commander_calls = ensure_commander_calls + 1
         ensured_commander = { client = client, options = options }
         return { name = "Nomad Commander" }
      end,
      attach_mothership = function(client, mothership)
         attached_mothership = { client = client, mothership = mothership }
      end,
      release_mothership = function(client)
         released_mothership = client
      end,
      get_commander_shuttle = function()
         return { nameRaw = function() return "Alpaca" end }
      end,
      get_commander = function() return commander end,
      launch_commander_shuttle = function(client)
         command_launch_call = client
         if command_launch_failure then return false, command_launch_failure end
         return true
      end,
   }
end

local config = require "nomad.config"
local configured_core_outfits = {}
for _starter_index, starter in ipairs(config.starter_carriers) do
   for _core_index, core in ipairs(starter.core_outfits or {}) do
      configured_core_outfits[core.name] = true
   end
end

-- Starter flavour is configuration, not part of the Core-installation
-- contract exercised below. Accept any configured faction, spob, jump, or
-- pirate-standing setup without making the test depend on its particulars.
local faction_standings = {}
local function known_target(name)
   return {
      setKnown = function() end,
      setReputationGlobal = function(_, value)
         faction_standings[name] = value
      end,
   }
end
local faction_targets = {}
local function faction_target(name)
   faction_targets[name] = faction_targets[name] or known_target(name)
   return faction_targets[name]
end
faction = {
   get = faction_target,
}
spob = { get = function() return known_target() end }
jump = { get = function() return known_target() end }
local pirate_standing_update
package.preload["common.pirate"] = function()
   return {
      factions = {
         faction_target("Pirate"), faction_target("Marauder"),
         faction_target("Raven Clan"), faction_target("Wild Ones"),
         faction_target("Dreamer Clan"), faction_target("Black Lotus"),
      },
      updateStandings = function(value) pirate_standing_update = value end,
   }
end

local start_vars = {}
local carrier_tag
local starting_bays = {}
local starting_install_attempts = {}
local starting_generator_fits = true
local starting_integrated = {}
local starting_slot_outfits = {}
local starting_slots = {
   { id = 3, type = "Utility", size = "Medium", property = "systems" },
   { id = 4, type = "Utility", size = "Medium", property = "accessory" },
   { id = 5, type = "Utility", size = "Medium" },
   { id = 6, type = "Utility", size = "Medium" },
   { id = 10, type = "Utility", size = "Medium" },
   { id = 7, type = "Structure", size = "Large", property = "engines" },
   { id = 8, type = "Structure", size = "Large",
      property = "engines_secondary" },
   { id = 9, type = "Structure", size = "Large" },
   { id = 11, type = "Structure", size = "Large" },
}
local starting_inventory = {}
local starting_ship_add
local starting_ship_swap
local starting_credits = 30000
local starting_payment
local chained_events = {}
local start_finished
var = {
   push = function(key, value)
      start_vars[key] = value
   end,
}
naev = {
   cache = function() return {} end,
   eventStart = function(name)
      chained_events[#chained_events + 1] = name
   end,
}
evt = {
   finish = function(success)
      start_finished = success
   end,
}
player = {
   credits = function() return starting_credits end,
   pay = function(amount)
      starting_payment = amount
      starting_credits = starting_credits + amount
   end,
   shipAdd = function(hull, name, acquired, noname)
      starting_slot_outfits = {}
      for _slot_index, slot in ipairs(starting_slots) do
         if slot.property and (slot.property:match("^systems")
            or slot.property:match("^engines")) then
            starting_slot_outfits[slot.id] = {
               nameRaw = function() return "Default Core" end,
            }
         end
      end
      starting_ship_add = {
         hull = hull, name = name, acquired = acquired, noname = noname,
      }
      return name
   end,
   shipSwap = function(name, ignore_cargo, remove)
      starting_ship_swap = {
         name = name, ignore_cargo = ignore_cargo, remove = remove,
      }
   end,
   shipvarPush = function(key, value)
      carrier_tag = { key = key, value = value }
   end,
   teleport = function() end,
   outfitAdd = function(name, quantity)
      starting_inventory[name] = (starting_inventory[name] or 0) + (quantity or 1)
   end,
   pilot = function()
      local function slot_id(id)
         if type(id) ~= "string" then return id end
         for _slot_index, slot in ipairs(starting_slots) do
            if slot.property == id then return slot.id end
         end
         return id
      end
      return {
         outfitAdd = function(_, what, quantity)
            starting_install_attempts[#starting_install_attempts + 1] = what
            if what == "Small Ship Bay" then return 0 end
            if what == config.wormhole_generator
               and not starting_generator_fits then return 0 end
            starting_bays[#starting_bays + 1] = what
            return quantity or 1
         end,
         ship = function()
            return {
               getSlots = function() return starting_slots end,
            }
         end,
         outfits = function() return starting_slot_outfits end,
         outfitAddSlot = function(_, what, id, bypass_cpu, bypass_slot)
            id = slot_id(id)
            if configured_core_outfits[what] then
               starting_slot_outfits[id] = {
                  nameRaw = function() return what end,
               }
               return true
            end
            if what == config.shuttle_bay or what == config.wormhole_generator then
               if what == config.wormhole_generator
                  and not starting_generator_fits then return false end
               starting_bays[#starting_bays + 1] = what
               starting_slot_outfits[id] = {
                  nameRaw = function() return what end,
               }
               return true
            end
            starting_integrated[#starting_integrated + 1] = {
               outfit = what, id = id, bypass_cpu = bypass_cpu,
               bypass_slot = bypass_slot,
            }
            starting_slot_outfits[id] = {
               nameRaw = function() return what end,
            }
            return true
         end,
         outfitRmSlot = function(_, id)
            id = slot_id(id)
            starting_slot_outfits[id] = nil
         end,
      }
   end,
}

dofile("events/nomad_start.lua")
create()
assert(#starting_menu == #config.starter_carriers + 2,
   "the carrier selector must list every configured start")
assert(start_vars[config.active_var] == true
   and start_vars[config.start_chapter_var] == "0"
   and start_vars.tut_disable == true,
   "Nomad start must mark new pilots and suppress vanilla tutorial hints")
assert(#chained_events == 3 and chained_events[1] == "start_event"
   and chained_events[2] == config.crewmates_event
   and chained_events[3] == config.handler_event,
   "Nomad start must initialize Crewmates before its persistent handler")
assert(start_finished == true, "Nomad start marker event must finish successfully")
assert(carrier_tag.key == config.carrier_shipvar and carrier_tag.value == true,
   "Nomad start must tag the actual owned carrier")
local selected_starter = config.starter_carriers[1]
assert(starting_ship_add.hull == selected_starter.hull
   and starting_ship_add.name == selected_starter.name
   and starting_ship_add.noname == true,
   "Nomad start must create the configured carrier after player initialization")
assert(starting_ship_swap.name == selected_starter.name
   and starting_ship_swap.ignore_cargo == true
   and starting_ship_swap.remove == true,
   "Nomad start must atomically replace the temporary bootstrap hull")
assert(starting_credits == selected_starter.credits and starting_payment == 0,
   "Nomad start must apply the selected carrier's exact starting funds")
assert(#starting_install_attempts == 2 and #starting_bays == 3
   and starting_bays[1] == "Medium Ship Bay"
   and starting_bays[2] == config.shuttle_bay
   and starting_bays[3] == config.wormhole_generator
   and #starting_integrated == 1
   and starting_integrated[1].outfit == config.operational_core
   and starting_integrated[1].id == 5
   and starting_integrated[1].bypass_cpu == true
   and starting_integrated[1].bypass_slot == true,
   "Nomad start must force the Core into the first largest utility slot")
assert(starting_slot_outfits[3]:nameRaw() == "Default Core"
   and starting_slot_outfits[7]:nameRaw() == "Melendez Buffalo Engine"
   and starting_slot_outfits[8]:nameRaw() == "Melendez Buffalo Engine",
   "starter engine replacements must stay in the named engine slots")
assert(starting_slot_outfits[4] == nil
   and starting_slot_outfits[6]:nameRaw() == config.shuttle_bay,
   "the starter Shuttle Bay must use an ordinary utility slot")
for name, quantity in pairs(config.spare_bays) do
   local failed_starter = name == "Small Ship Bay" and 1 or 0
   assert(starting_inventory[name] == quantity + failed_starter,
      "new Nomad pilots must receive every configured spare bay control")
end
assert(starting_inventory[config.wormhole_generator] == nil,
   "new Nomad pilots must try to fit the optional wormhole generator")
starting_generator_fits = false
starting_inventory[config.wormhole_generator] = nil
create()
assert(starting_inventory[config.wormhole_generator] == 1,
   "a starter carrier without a free slot must retain the generator in stock")
starting_generator_fits = true
starting_inventory[config.wormhole_generator] = nil

starting_slots = {
   { id = 6, type = "Utility", size = "Large",
      property = "bio_systems" },
   { id = 9, type = "Utility", size = "Large",
      property = "systems_secondary" },
   { id = 10, type = "Utility", size = "Large",
      property = "accessory" },
   { id = 11, type = "Utility", size = "Large" },
   { id = 12, type = "Utility", size = "Large" },
   { id = 13, type = "Utility", size = "Medium" },
   { id = 17, type = "Utility", size = "Medium" },
   { id = 14, type = "Structure", size = "Large", property = "engines" },
   { id = 15, type = "Structure", size = "Large",
      property = "engines_secondary" },
   { id = 16, type = "Structure", size = "Large" },
   { id = 18, type = "Structure", size = "Large" },
}
local every_starter_installs_core = true
for choice = 1, #config.starter_carriers do
   starting_choice = choice
   starting_integrated = {}
   starting_slot_outfits = {}
   create()
   every_starter_installs_core = every_starter_installs_core
      and #starting_integrated == 1
      and starting_integrated[1].outfit == config.operational_core
      and starting_integrated[1].id == 11
      and starting_integrated[1].bypass_cpu == true
      and starting_integrated[1].bypass_slot == true
end
assert(every_starter_installs_core,
   "every Nomad carrier start must install the Operational Core")
faction_standings = {}
pirate_standing_update = nil
starting_choice = 3
create()
assert(faction_standings.Empire == -10 and faction_standings.Dvaered == -10
   and faction_standings.Sirius == -10 and faction_standings.Soromid == -10
   and faction_standings["Za'lek"] == -10
   and faction_standings.Independent == -10 and faction_standings.Frontier == -10
   and faction_standings["Traders Society"] == -10
   and faction_standings.Pirate == 20 and faction_standings.Marauder == 20
   and faction_standings["Raven Clan"] == 20
   and faction_standings["Wild Ones"] == 20
   and faction_standings["Dreamer Clan"] == 20
   and faction_standings["Black Lotus"] == 20
   and faction_standings.Proteron == nil and faction_standings.Thurion == nil
   and faction_standings.Lost == nil
   and pirate_standing_update == 20,
   "the Raven Rhino start must apply its configured pirate standings")
starting_choice = 1
local current_hull = selected_starter.hull
local carrier_tags = { [selected_starter.hull] = true }
local landing_allowed
local landing_reason
local registered = {}
local current_size = 6
local nojump_marker
local nojump_value
local explicit_current_shipvar_lookup
local restored_carrier_name
local installed_outfits = { "Medium Ship Bay", "Small Ship Bay" }
local carrier_status
local owned_ships = {}
local shared_cache = {}
local deploy_call
local fleet_capacity
local landed = false
local forced_land_calls = 0
local normal_land_calls = 0
local brake_calls = 0
local control_calls = 0
local manual_control = false
local shield = 100
local shield_capacity = 100
local info_actions = {}
local info_handles = {}
local next_info_handle = 0
local diff_applied = false
local dynamic_diff
local current_diff_name
local dynamic_names = {}
local reject_next_diff = false
local current_spob
local restored_position
local restored_direction
local restored_velocity
local inventory_removals = {}
local initialized_outfit_slots = {}
local inventory_counts = {
   ["Small Ship Bay"] = 3,
   [config.operational_core] = 1,
}
local refunded_credits = 0
local removed_ship
local last_player_message
local scheduled_timers = {}
local pilot_hook_callbacks = {}
local next_hook_id = 0
local active_update_hooks = {}
local teleport_call
local current_system_name = "Test & System"
local player_x, player_y = 321.25, -654.5
local player_vx, player_vy = 0, 0
mem = {}
local current_pilot = {
   ship = function()
      return {
         nameRaw = function() return current_hull end,
         size = function() return current_size end,
         getSlots = function()
            return {
               { id = 1, type = "Weapon", size = "Large",
                  property = "fighter_bay" },
               { id = 2, type = "Weapon", size = "Large",
                  property = "fighter_bay" },
               { id = 3, type = "Utility", size = "Medium" },
               { id = 4, type = "Utility", size = "Large" },
            }
         end,
      }
   end,
   flags = function() return {
      nojump = nojump_value == true,
      manualcontrol = manual_control,
   } end,
   setNoJump = function(_, value) nojump_value = value end,
   outfitsList = function()
      local result = {}
      for _, name in ipairs(installed_outfits) do
         result[#result + 1] = { nameRaw = function() return name end }
      end
      return result
   end,
   outfits = function()
      local result = {}
      for index, name in ipairs(installed_outfits) do
         result[index] = { nameRaw = function() return name end }
      end
      return result
   end,
   outfitAdd = function(_, name)
      installed_outfits[#installed_outfits + 1] = name
      return 1
   end,
   outfitRm = function(_, name, quantity)
      local removed = 0
      for index = #installed_outfits, 1, -1 do
         if installed_outfits[index] == name and removed < (quantity or 1) then
            table.remove(installed_outfits, index)
            removed = removed + 1
         end
      end
      return removed
   end,
   outfitAddSlot = function(_, name, id)
      if installed_outfits[id] then return false end
      installed_outfits[id] = name
      return true
   end,
   outfitRmSlot = function(_, id)
      if not installed_outfits[id] then return false end
      installed_outfits[id] = nil
      return true
   end,
   outfitInitSlot = function(_, id)
      initialized_outfit_slots[#initialized_outfit_slots + 1] = id
   end,
   pos = function()
      return vec2.new(player_x, player_y)
   end,
   exists = function() return true end,
   msg = function() end,
   vel = function()
      return {
         get = function() return player_vx, player_vy end,
      }
   end,
   brake = function() brake_calls = brake_calls + 1 end,
   control = function(_, enabled)
      control_calls = control_calls + 1
      manual_control = enabled ~= false
   end,
   dir = function() return 0 end,
   radius = function() return 100 end,
   health = function() return 100, shield end,
   energy = function() return 100 end,
   cargoList = function() return {} end,
   weapsetList = function(_, id)
      local result = {}
      for _, slot in ipairs(player_weapon_sets[id] or {}) do
         result[#result + 1] = slot
      end
      return result
   end,
   weapsetRm = function(_, id, slot)
      for index, current in ipairs(player_weapon_sets[id] or {}) do
         if current == slot then
            table.remove(player_weapon_sets[id], index)
            return
         end
      end
   end,
   weapsetAdd = function(_, id, slot)
      player_weapon_sets[id] = player_weapon_sets[id] or {}
      for _, current in ipairs(player_weapon_sets[id]) do
         if current == slot then return end
      end
      player_weapon_sets[id][#player_weapon_sets[id] + 1] = slot
   end,
   stats = function() return {
      shield = shield_capacity, armour = 100, fuel = 100,
   } end,
   faction = function() return "Player" end,
   worth = function() return 5000000 end,
   setPos = function(_, value) restored_position = value end,
   setDir = function(_, value) restored_direction = value end,
   setVel = function(_, value) restored_velocity = value end,
   setHealth = function() end,
   setEnergy = function() end,
   setFuel = function() end,
   navSpobSet = function(_, target) current_spob = target end,
}
player = {
   pilot = function() return current_pilot end,
   ship = function() return current_hull end,
   ships = function() return owned_ships end,
   isLanded = function() return landed end,
   land = function(target)
      forced_land_calls = forced_land_calls + 1
      landed = true
      current_spob = target
   end,
   tryLand = function()
      normal_land_calls = normal_land_calls + 1
      return "ok"
   end,
   landAllow = function(allowed, reason)
      landing_allowed = allowed
      landing_reason = reason
   end,
   shipvarPeek = function(key, name)
      if name == current_hull then explicit_current_shipvar_lookup = true end
      if key == config.carrier_shipvar then
         return carrier_tags[name or current_hull] == true
      end
      if key == config.nojump_shipvar then return nojump_marker end
      return false
   end,
   shipvarPush = function(key, value, name)
      if key == config.nojump_shipvar then nojump_marker = value end
      if key == config.carrier_shipvar then
         restored_carrier_name = name
         carrier_tags[name or current_hull] = value
      end
   end,
   shipvarPop = function(key)
      if key == config.nojump_shipvar then nojump_marker = nil end
      if key == config.carrier_shipvar then carrier_tags[current_hull] = nil end
   end,
   shipSwap = function(name, _ignore_cargo, remove)
      for _, entry in ipairs(owned_ships) do
         if entry.name == name and entry.deployed then
            error("cannot swap into deployed owned ship: " .. name)
         end
      end
      local previous = current_hull
      for index, entry in ipairs(owned_ships) do
         if entry.name == name then
            table.remove(owned_ships, index)
            break
         end
      end
      if not remove then
         local present = false
         for _, entry in ipairs(owned_ships) do
            if entry.name == previous then present = true end
         end
         if not present then
            owned_ships[#owned_ships + 1] = {
               name = previous,
               deployed = false,
               ship = current_pilot:ship(),
            }
         end
      end
      current_hull = name
   end,
   infoButtonRegister = function(title, callback)
      assert(type(callback) == "function",
         "Naev info buttons require a function callback")
      next_info_handle = next_info_handle + 1
      info_actions[title] = callback
      info_handles[next_info_handle] = title
      return next_info_handle
   end,
   infoButtonUnregister = function(handle)
      info_actions[info_handles[handle]] = nil
      info_handles[handle] = nil
   end,
   commClose = function() comm_close_calls = comm_close_calls + 1 end,
   msg = function(message) last_player_message = message end,
   shipDeploy = function(name, deploy, escort)
      deploy_call = { name = name, deploy = deploy, escort = escort }
      for _, entry in ipairs(owned_ships) do
         if entry.name == name then entry.deployed = deploy end
      end
   end,
   fleetCapacitySet = function(capacity) fleet_capacity = capacity end,
   shipRm = function(name)
      removed_ship = name
      for index, entry in ipairs(owned_ships) do
         if entry.name == name then
            table.remove(owned_ships, index)
            break
         end
      end
   end,
   pay = function(amount) refunded_credits = refunded_credits + amount end,
   outfitRm = function(name, quantity)
      inventory_removals[#inventory_removals + 1] = {
         name = name, quantity = quantity,
      }
      inventory_counts[name] = (inventory_counts[name] or 0) - quantity
      return quantity
   end,
   outfitAdd = function(name, quantity)
      inventory_counts[name] = (inventory_counts[name] or 0) + (quantity or 1)
   end,
   outfitNum = function(name) return inventory_counts[name] or 0 end,
   shipOutfits = function(name)
      if not name or not carrier_tags[name] then return {} end
      local result = {}
      for _, outfit_name in ipairs(installed_outfits) do
         result[#result + 1] = {
            nameRaw = function() return outfit_name end,
         }
      end
      return result
   end,
   teleport = function(destination, no_simulate, silent)
      teleport_call = {
         destination = destination,
         no_simulate = no_simulate,
         silent = silent,
      }
      current_system_name = destination
   end,
}
naev.cache = function() return shared_cache end
naev.claimTest = function() return true end
naev.ticks = function() return 12345 end
local ordinary_spob_denied
local parked_spob_known
local wormhole_spob_known = {}
local wormhole_locations = {
   [config.wormhole.source_spob] = config.wormhole.storage_system,
   [config.wormhole.target_spob] = config.wormhole.storage_system,
}
local function wormhole_endpoint(name)
   return {
      nameRaw = function() return name end,
      system = function()
         local location = wormhole_locations[name]
         return location and { nameRaw = function() return location end }
      end,
      setKnown = function(_self, known) wormhole_spob_known[name] = known end,
   }
end
local wormhole_source_spob = wormhole_endpoint(config.wormhole.source_spob)
local wormhole_target_spob = wormhole_endpoint(config.wormhole.target_spob)
local ordinary_spob = {
   nameRaw = function() return "Ordinary Port" end,
   tags = function() return {} end,
   getLandDeny = function() return false end,
   getLandAllow = function() return false end,
   landDeny = function(_self, denied) ordinary_spob_denied = denied end,
}
local wormhole_spob = {
   nameRaw = function() return "Test Wormhole" end,
   tags = function() return { wormhole = true } end,
   landDeny = function() error("wormholes must remain landable") end,
}
local parked_spob = {
   nameRaw = function() return config.parking.spob end,
   tags = function() return {} end,
   landDeny = function() error("the temporary berth must remain landable") end,
   setKnown = function(_self, known) parked_spob_known = known end,
}
local test_system = {
   nameRaw = function() return current_system_name end,
   tags = function() return {} end,
   spobs = function() return { ordinary_spob, wormhole_spob, parked_spob } end,
   jumpDist = function(_self, candidate) return candidate.distance end,
}
local nearby_system = {
   distance = 2,
   nameRaw = function() return "Nearby System" end,
   name = function() return "Nearby System" end,
   tags = function() return {} end,
   radius = function() return 10000 end,
}
system = {
   cur = function() return test_system end,
   getAll = function() return { test_system, nearby_system } end,
}
spob = {
   get = function(name)
      if name == config.parking.spob then return parked_spob end
      if name == config.wormhole.source_spob then return wormhole_source_spob end
      if name == config.wormhole.target_spob then return wormhole_target_spob end
   end,
   cur = function()
      if not landed then
         error("Attempting to get landed spob when player not landed")
      end
      return current_spob
   end,
}
diff = {
   isApplied = function(name)
      return diff_applied and name == current_diff_name
   end,
   newDynamic = function(xml)
      if reject_next_diff then
         reject_next_diff = false
         return false
      end
      local name = assert(xml:match('<unidiff name="([^"]+)"'))
      if dynamic_names[name] then return false end
      dynamic_names[name] = true
      current_diff_name = name
      dynamic_diff = xml
      diff_applied = true
      for system_name, body in xml:gmatch(
            '<system name="([^"]+)">(.-)</system>') do
         local decoded_system_name = system_name:gsub("&quot;", '"')
            :gsub("&apos;", "'"):gsub("&gt;", ">")
            :gsub("&lt;", "<"):gsub("&amp;", "&")
         for spob_name in body:gmatch("<spob_add>(.-)</spob_add>") do
            if wormhole_locations[spob_name] then
               wormhole_locations[spob_name] = decoded_system_name
            end
         end
      end
      return true
   end,
   remove = function(name)
      assert(name == current_diff_name)
      if dynamic_diff
         and dynamic_diff:find(config.wormhole.source_spob, 1, true) then
         wormhole_locations[config.wormhole.source_spob] =
            config.wormhole.storage_system
         wormhole_locations[config.wormhole.target_spob] =
            config.wormhole.storage_system
      end
      diff_applied = false
   end,
}
local vector_mt = {
   __add = function(left, right)
      return vec2.new(left.x + right.x, left.y + right.y)
   end,
}
vec2 = {
   new = function(x, y)
      local value = { x = x or 0, y = y or 0 }
      value.get = function() return value.x, value.y end
      value.dist = function(_self, other)
         local dx, dy = value.x - other.x, value.y - other.y
         return math.sqrt(dx * dx + dy * dy)
      end
      return setmetatable(value, vector_mt)
   end,
   newP = function(radius, angle)
      return vec2.new(radius * math.cos(angle), radius * math.sin(angle))
   end,
}
rnd = {
   rnd = function(minimum, _maximum) return minimum end,
   angle = function() return math.pi * 0.25 end,
}
pilot = {
   get = function()
      local result = {}
      for _, candidate in ipairs(live_pilots) do
         if candidate:exists() then result[#result + 1] = candidate end
      end
      return result
   end,
   add = function(_ship, _faction, spawn_position, name)
      local exists = true
      local leader
      local direction = 0
      local position = spawn_position
      local velocity = vec2.new(0, 0)
      local candidate_outfits = {
         [99] = { nameRaw = function() return "Base Locked Hull Outfit" end },
      }
      local default_outfits = { [99] = true }
      if not position.dist then position.dist = function() return 0 end end
      local candidate = {
         name = function() return name end,
         exists = function() return exists end,
         withPlayer = function() return true end,
         rm = function() exists = false end,
         outfitAdd = function() end,
         outfitAddSlot = function(_, outfit_name, id)
            if candidate_outfits[id] and not default_outfits[id] then
               return false
            end
            candidate_outfits[id] = {
               nameRaw = function() return outfit_name end,
            }
            default_outfits[id] = nil
            return true
         end,
         outfits = function() return candidate_outfits end,
         setLeader = function(_, value) leader = value end,
         leader = function() return leader end,
         setNoClear = function() end,
         setFriendly = function() end,
         setInvincPlayer = function() end,
         setDir = function(_, value) direction = value end,
         dir = function() return direction end,
         setVel = function(_, value) velocity = value end,
         vel = function() return velocity end,
         setHealth = function(_, armour, shield_value, stress)
            applied_health[#applied_health + 1] = {
               armour = armour, shield = shield_value, stress = stress,
            }
         end,
         setEnergy = function() end,
         setFuel = function() end,
         fillAmmo = function() end,
         cargoAdd = function() end,
         cargoList = function() return {} end,
         weapsetList = function() return {} end,
         weapsetCleanup = function() end,
         weapsetAdd = function() end,
         health = function() return 100, 100, 0 end,
         energy = function() return 100 end,
         stats = function() return { armour = 100, fuel = 100 } end,
         ship = function() return _ship end,
         control = function() end,
         follow = function() end,
         pos = function() return position end,
      }
      live_pilots[#live_pilots + 1] = candidate
      return candidate
   end,
}
hook = {
   update = function(name)
      next_hook_id = next_hook_id + 1
      active_update_hooks[next_hook_id] = name
      registered.update = name
      return next_hook_id
   end,
   rm = function(id) active_update_hooks[id] = nil end,
   enter = function(name) registered.enter = name end,
   jumpout = function(name) registered.jumpout = name end,
   land = function(name) registered.land = name end,
   takeoff = function(name) registered.takeoff = name end,
   load = function(name) registered.load = name end,
   ship_swap = function(name) registered.ship_swap = name end,
   ship_buy = function(name) registered.ship_buy = name end,
   ship_sell = function(name) registered.ship_sell = name end,
   safe = function(name, argument)
      _G[name](argument)
   end,
   timer = function(delay, name, ...)
      scheduled_timers[#scheduled_timers + 1] = {
         delay = delay, name = name, arguments = { ... },
      }
   end,
   pilot = function(_pilot, event, callback)
      pilot_hook_callbacks[#pilot_hook_callbacks + 1] = {
         event = event, callback = callback,
      }
      return #pilot_hook_callbacks
   end,
   custom = function(name, callback) registered[name] = callback end,
}
evt = { save = function(saved) registered.saved = saved end }
tk.msg = function(title, message)
   carrier_status = { title = title, message = message }
end

dofile("events/nomad.lua")
create()
assert(not explicit_current_shipvar_lookup,
   "the current ship must use shipvarPeek's implicit current-ship form")
assert(landing_allowed == nil and ordinary_spob_denied == true,
   "the carrier must block ordinary spobs without a system-wide landing override")
assert(registered.enter == "nomad_apply_rules",
   "carrier landing rules must be restored after jumping")
assert(registered.jumpout == nil,
   "owned fleet launching must not install a proxy-cleanup jump hook")
assert(registered.land == "nomad_landed",
   "parking must only be verified by the completed-land hook")
assert(registered.ship_swap == "nomad_ship_changed",
   "carrier landing rules must follow ship changes")
assert(registered.takeoff == "nomad_takeoff",
   "takeoff hooks must restore a parked carrier")
assert(registered.nomad_wormhole_entering == "nomad_wormhole_entering",
   "wormhole traversal must register its mothership-follow suppression hook")
assert(registered.load == "nomad_restore_parked_diff",
   "load hooks must restore the dynamic spob before initialization")
assert(registered.saved == true, "Nomad campaign state must persist")
assert(ensured_commander.client == config.joyride_client,
   "Nomad must register its commander requirement with Crewmates")
assert(ensured_commander.options.minimum == config.minimum_crew.commander
   and ensured_commander.options.shuttle == config.starter_subship.hull
   and ensured_commander.options.shuttle_profile.client == config.joyride_client
   and ensured_commander.options.shuttle_profile.landable == true,
   "Crewmates must guarantee the configured commander and shuttle")
assert(fleet_capacity == 0,
   "Nomad initialization must disable vanilla fleet capacity")
assert(parked_spob_known == false,
   "Nomad initialization must erase temporary berth discovery state")
assert(installed_outfits[1] == "Medium Ship Bay"
   and installed_outfits[2] == "Small Ship Bay"
   and installed_outfits[3] == config.shuttle_bay
   and installed_outfits[4] == config.operational_core
   and inventory_counts[config.operational_core] == 0,
   "initialization must repair integrated systems without changing bay controls")
installed_outfits[1] = "Large Ship Bay"
nomad_initialize()
assert(installed_outfits[1] == "Large Ship Bay",
   "restored carriers must not overwrite manually selected bay controls")
installed_outfits[1] = "Medium Ship Bay"
assert(type(info_actions["Launch Shuttle"]) == "function"
   and type(info_actions["Park Carrier"]) == "function",
   "the carrier info menu must expose command launch and parking actions")

nomad_wormhole_generator_activated()
local first_wormhole_diff = current_diff_name
assert(diff_applied and mem.nomad.wormhole_diff == current_diff_name
   and wormhole_locations[config.wormhole.source_spob] == current_system_name
   and wormhole_locations[config.wormhole.target_spob]
      == nearby_system:nameRaw()
   and wormhole_spob_known[config.wormhole.source_spob] == true
   and wormhole_spob_known[config.wormhole.target_spob] == true,
   "generator activation must move both stored endpoints into a live pair: "
      .. tostring(diff_applied) .. " / "
      .. tostring(mem.nomad.wormhole_diff) .. " / "
      .. tostring(wormhole_locations[config.wormhole.source_spob]) .. " / "
      .. tostring(wormhole_locations[config.wormhole.target_spob]) .. " / "
      .. tostring(carrier_status and carrier_status.title) .. ": "
      .. tostring(carrier_status and carrier_status.message))
local wormhole_origin = current_system_name
current_hull = "Hyena"
current_size = 1
mem.nomad.active_sortie = true
mem.nomad.active_source = "bay"
shared_cache.joyride = {
   profile = { client = config.joyride_client },
   follow_mothership = true,
}
nomad_wormhole_entering({ origin = wormhole_origin })
assert(mem.nomad.wormhole_follow_origin == wormhole_origin
   and shared_cache.joyride.follow_mothership == false,
   "bay-ship traversal must remember the origin and pause Joyride following")
current_system_name = nearby_system:nameRaw()
nomad_wormhole_entering({ origin = current_system_name })
assert(mem.nomad.wormhole_follow_origin == wormhole_origin,
   "return traversal must not replace the system where the carrier was left")
landed = true
nomad_landed()
landed = false
nomad_takeoff()
assert(diff_applied and mem.nomad.wormhole_follow_origin == wormhole_origin,
   "landing and taking off away from the carrier must retain the return aperture")
current_system_name = wormhole_origin
nomad_apply_rules()
assert(mem.nomad.wormhole_follow_origin == nil
   and shared_cache.joyride.follow_mothership == true
   and attached_mothership.mothership == shared_cache.joyride.pilot,
   "the mothership may spawn normally once the bay ship returns to its origin")
current_hull = selected_starter.hull
current_size = 6
shared_cache.joyride = nil
nomad_joyride_ended({ client = config.joyride_client })
assert(not diff_applied and mem.nomad.wormhole_diff == nil
   and wormhole_locations[config.wormhole.source_spob]
      == config.wormhole.storage_system
   and wormhole_locations[config.wormhole.target_spob]
      == config.wormhole.storage_system,
   "returning to the carrier must synchronously move both endpoints to storage")
nomad_wormhole_generator_activated()
assert(diff_applied and current_diff_name ~= first_wormhole_diff
   and mem.nomad.wormhole_diff == current_diff_name
   and wormhole_locations[config.wormhole.source_spob] == current_system_name
   and wormhole_locations[config.wormhole.target_spob]
      == nearby_system:nameRaw(),
   "reactivation may repeat a destination but must create a fresh live pair")
nomad_joyride_ended({ client = config.joyride_client })
assert(not diff_applied and mem.nomad.wormhole_diff == nil,
   "a repeatedly opened pair must still close completely")
local function physical_id(outfit_name, occurrence)
   local found = 0
   for id, name in ipairs(installed_outfits) do
      if name == outfit_name then
         found = found + 1
         if found == (occurrence or 1) then return id end
      end
   end
end

info_actions["Launch Shuttle"]()
assert(command_launch_call == config.joyride_client,
   "the logical command action must delegate to Crewmates' persistent shuttle")
command_launch_call = nil
nomad_integrated_system_activated { action = "shuttle" }
assert(command_launch_call == config.joyride_client,
   "the shuttle bay weapon-set action must use the command launch path")
command_launch_call = nil
command_launch_failure = "another auxiliary ship is already active"
shared_cache.joyride = true
info_actions["Launch Shuttle"]()
assert(command_launch_call == config.joyride_client
   and last_player_message:find("already active", 1, true),
   "failed command launches must leave Joyride state unchanged and report why")
command_launch_call = nil
command_launch_failure = nil
shared_cache.joyride = nil

owned_ships = {{
   name = "Needle", deployed = false,
   ship = {
      nameRaw = function() return "Hyena" end,
      size = function() return 1 end,
   },
}}
mem.nomad.crafts.Needle = {
   phase = "ready",
   snapshot = { hull = "Soromid Arx", outfits = {}, cargo = {} },
   redeploy_transform = { x = 1, y = 2, direction = 3 },
}
local first_s = physical_id("Small Ship Bay", 1)
nomad_bay_activated { outfit = "Small Ship Bay", id = first_s, on = true }
assert(not deploy_call and owned_ships[1].deployed == false
   and last_player_message:find("Launching", 1, true),
   "activating an occupied bay must launch its carried ship")
assert(#live_pilots == 1 and live_pilots[1]:exists(),
   "launching must create exactly one plugin-owned carried pilot")
assert(mem.nomad.crafts.Needle.snapshot.hull == "Hyena"
   and mem.nomad.crafts.Needle.redeploy_transform == nil,
   "launch must repair a persisted snapshot belonging to the wrong hull")
assert(not command_launch_call and not borrow_call,
   "general-bay activation must not start an owned-ship Joyride")
assert(shared_cache.nomad_bay_tooltips[first_s] == "Deployed: Needle (Hyena)",
   "launching must refresh the physical control's deployed tooltip")
assert(shared_cache.nomad_bay_assignments[first_s].name == "Needle",
   "assigned ships must be cached by their physical bay controls")
assert(live_pilots[1]:outfitAddSlot(
   "Evolved Locked Hull Outfit", 99, true, false),
   "the fixture must model a locked outfit that differs from the base hull")
nomad_bay_activated { outfit = "Small Ship Bay", id = first_s, on = false }
assert(not deploy_call and live_pilots[1]:exists()
   and mem.nomad.crafts.Needle.phase == "returning",
   "turning a bay off must order the disposable copy home")
nomad_update(0.1)
assert(not live_pilots[1]:exists()
   and mem.nomad.crafts.Needle.phase == "cooldown",
   "the copy must disappear only after reaching docking distance")
assert(mem.nomad.crafts.Needle.serviced == true
   and mem.nomad.crafts.Needle.destroyed == nil
   and mem.nomad.crafts.Needle.zero_shields == nil
   and shared_cache.nomad_bay_cooldowns[first_s].remaining > 0,
   "an intact recall must enter visible servicing without a destroyed-craft shield override")
local pilots_before_early_launch = #live_pilots
nomad_bay_activated { outfit = "Small Ship Bay", id = first_s, on = true }
assert(#live_pilots == pilots_before_early_launch
   and mem.nomad.crafts.Needle.phase == "cooldown",
   "an early launch attempt must not corrupt the recalled craft")
nomad_update(100)
assert(mem.nomad.crafts.Needle.phase == "ready"
   and shared_cache.nomad_bay_cooldowns[first_s] == nil,
   "completed servicing must clear the native cooldown display")

nomad_bay_activated { outfit = "Small Ship Bay", id = first_s, on = true }
assert(applied_health[#applied_health].shield == 100,
   "an intact recalled craft must relaunch with serviced shields")
assert(live_pilots[2]:outfits()[99]:nameRaw() ==
   "Evolved Locked Hull Outfit",
   "relaunch must replace a base locked outfit with the saved variant")
local closes_before_hail = comm_close_calls
local timers_before_hail = #scheduled_timers
nomad_hail_owned(live_pilots[2], "Needle")
assert(comm_close_calls == closes_before_hail + 1 and not swap_call
   and #scheduled_timers == timers_before_hail + 1
   and scheduled_timers[#scheduled_timers].name == "nomad_begin_owned_joyride",
   "hailing a bay craft must close the stock escort comm before deferring the swap")
nomad_begin_owned_joyride("Needle", live_pilots[2])
assert(swap_call and swap_call.template == live_pilots[2]
   and not live_pilots[2]:exists()
   and mem.nomad.active_kind == "owned",
   "hailing a launched carried pilot must transfer control through Joyride")
end_joyride_call = nil
current_hull = "Hyena"
current_size = 1
player_x, player_y = 987.5, -432.25
player_vx, player_vy = 731.25, -94.5
mem.nomad.virtual_name = current_hull
nomad_joyride_started({ client = config.joyride_client })
mem.nomad.crafts.Needle.remaining = 7
mem.nomad.crafts.Needle.cooldown_total = 10
shared_cache.nomad_bay_cooldowns[first_s] = {
   remaining = 7, total = 10,
}
nomad_hail_mothership()
local hail_timer = scheduled_timers[#scheduled_timers]
nomad_complete_mothership_hail(hail_timer.arguments[1])
assert(end_joyride_call,
   "hailing the carrier from a bay craft must begin a deferred seat transfer: "
      .. tostring(last_player_message) .. " / "
      .. tostring(carrier_status and carrier_status.message))
assert(mem.nomad.crafts.Needle.snapshot.hull == "Hyena",
   "carrier hail must snapshot the controlled craft before Joyride swaps seats")
current_hull = selected_starter.hull
current_size = 6
nomad_joyride_ended({ client = config.joyride_client })
assert(mem.nomad.crafts.Needle.phase == "deployed"
   and live_pilots[#live_pilots]:exists()
   and live_pilots[#live_pilots]:pos().x == 987.5
   and live_pilots[#live_pilots]:pos().y == -432.25
   and live_pilots[#live_pilots]:vel().x == 731.25
   and live_pilots[#live_pilots]:vel().y == -94.5
   and shared_cache.nomad_bay_states[first_s] == true
   and shared_cache.nomad_bay_cooldowns[first_s] == nil
   and mem.nomad.crafts.Needle.remaining == nil,
   "carrier hail must restore an AI replacement for the vacated bay craft")
live_pilots[#live_pilots]:rm()
mem.nomad.crafts["Parked Scout"] = nil
player_x, player_y = 321.25, -654.5
mem.nomad.active_kind = nil
mem.nomad.active_sortie = nil
mem.nomad.active_source = nil
shared_cache.joyride = nil

owned_ships[1].deployed = true
owned_ships[1].deployed = false

installed_outfits[first_s] = nil
nomad_occupied_bay_removed {
   id = first_s,
   outfit = "Small Ship Bay",
   ship = { name = "Needle", hull = "Hyena" },
   inventory = 2,
}
assert(installed_outfits[first_s] == "Small Ship Bay"
   and inventory_removals[#inventory_removals].name == "Small Ship Bay"
   and carrier_status.title == "Bay In Use",
   "removing an occupied bay must restore it and balance the inventory copy")

deploy_call = nil
owned_ships = {}
nomad_bay_activated { outfit = "Medium Ship Bay", id = physical_id("Medium Ship Bay"), on = true }
assert(not deploy_call, "activating an empty general bay must change nothing")

owned_ships = {{
   name = "Needle", deployed = true,
   ship = {
      nameRaw = function() return "Hyena" end,
      size = function() return 1 end,
   },
}}
swap_call = nil
nomad_hail_owned(nil, "Needle")
assert(not borrow_call and not swap_call and comm_close_calls > 0,
   "hailing a non-Nomad native fleet pilot must not start a sortie")
mem.nomad.active_kind = nil
mem.nomad.active_sortie = nil
owned_ships = {}

shield = 89.9
toolkit_open = true
info_actions["Park Carrier"]()
assert(not diff_applied and not mem.nomad.parked
   and carrier_status.title == "Unable to Park Carrier",
   "parking below 90% shields must leave no dynamic state")
shield = 90
owned_ships = {{
   name = "Needle", deployed = false,
   ship = {
      nameRaw = function() return "Hyena" end,
      size = function() return 1 end,
   },
}}
mem.nomad.crafts.Needle = { phase = "ready" }
local parking_s = physical_id("Small Ship Bay", 1)
nomad_bay_activated { outfit = "Small Ship Bay", id = parking_s, on = true }
local parked_copy = live_pilots[#live_pilots]
info_actions["Park Carrier"]()
assert(not diff_applied and not mem.nomad.parked
   and last_player_message:find("Close the Info window", 1, true)
   and scheduled_timers[#scheduled_timers].name == "nomad_complete_parking",
   "parking must wait until the Info window has closed")
toolkit_open = false
player_vx, player_vy = config.parking.stop_speed + 1, 0
nomad_complete_parking()
assert(not diff_applied and not mem.nomad.parked
   and scheduled_timers[#scheduled_timers].name == "nomad_complete_parking",
   "parking must brake and wait while the carrier is still moving")
player_vx, player_vy = 0, 0
nomad_complete_parking()
assert(diff_applied and mem.nomad.parked,
   "parking must create its berth after the carrier stops")
assert(mem.nomad.parked.carrier == selected_starter.hull
   and owned_ships[1].deployed == false
   and not parked_copy:exists()
   and mem.nomad.crafts.Needle.phase == "ready"
   and info_actions["Park Carrier"] ~= nil,
   "parking must absorb and fully service disposable bay copies")
assert(forced_land_calls == 1 and normal_land_calls == 0,
   "parking must use the proven direct landing transition")
assert(brake_calls > 0,
   "parking must begin by braking the carrier")
assert(control_calls == 2 and not manual_control,
   "parking must temporarily take and release manual control to brake")
local first_parking_record = mem.nomad.parked
info_actions["Park Carrier"]()
assert(mem.nomad.parked == first_parking_record and diff_applied
   and carrier_status.title == "Unable to Park Carrier",
   "a second parking request must be rejected while a berth is active")
landed = false
nomad_landed()
assert(diff_applied and mem.nomad.parked,
   "an early land hook must never detach an in-progress landing target")
landed = true
nomad_landed()
assert(landed and mem.nomad.parked and diff_applied
   and mem.nomad.parked.x == 321.25 and mem.nomad.parked.y == -654.5
   and dynamic_diff:find('name="Test &amp; System"', 1, true),
   "parking must create the exact dynamic location and land on it")
assert(parked_spob_known == false,
   "parking must keep the temporary carrier berth out of map knowledge")
assert(next(info_actions) == nil,
   "carrier actions must be hidden while the carrier is landed")

owned_ships = {{
   name = "Parked Scout", deployed = false,
   ship = {
      nameRaw = function() return "Hyena" end,
      size = function() return 1 end,
   },
}}
player.shipSwap("Parked Scout", true, false)
current_size = 1
nomad_ship_changed("Parked Scout", owned_ships[1] and owned_ships[1].ship,
   selected_starter.hull)
assert(current_hull == "Parked Scout" and not shared_cache.joyride
   and mem.nomad.parked and diff_applied,
   "parked equipment-screen swaps must remain ordinary legal swaps")

landed = false
current_spob = nil
local parked_record = mem.nomad.parked
nomad_takeoff()
assert(not mem.nomad.parked and mem.nomad.departed_parking == parked_record
   and diff_applied
   and shared_cache.joyride and mem.nomad.active_kind == "owned"
   and mem.nomad.active_source == "bay"
   and mem.nomad.virtual_name == nil
   and mem.nomad.active_sortie == true
   and borrow_call.mothership == selected_starter.hull
   and borrow_call.transform.pos.x == 321.25
   and borrow_call.transform.pos.y == -654.5
   and restored_position.x == 321.25
   and restored_position.y == -654.5
   and restored_direction == parked_record.direction
   and scheduled_timers[#scheduled_timers].name ==
      "nomad_remove_departed_parking",
   "stored-ship takeoff must atomically adopt the selection and spawn its recorded carrier")
local cleanup = scheduled_timers[#scheduled_timers]
assert(cleanup.name == "nomad_remove_departed_parking",
   "successful carrier restoration must schedule stable-space berth cleanup")
landed = true
nomad_remove_departed_parking(cleanup.arguments[1], cleanup.arguments[2])
local cleanup_retry = scheduled_timers[#scheduled_timers]
assert(diff_applied and mem.nomad.departed_parking == parked_record
   and cleanup_retry.name == "nomad_remove_departed_parking"
   and cleanup_retry.arguments[3] == 1,
   "departure cleanup must retry while Naev still reports the takeoff transition as landed")
landed = false
nomad_remove_departed_parking(cleanup_retry.arguments[1],
   cleanup_retry.arguments[2], cleanup_retry.arguments[3])
assert(not mem.nomad.parked and not mem.nomad.departed_parking
   and not diff_applied and nojump_value ~= true,
   "stable-space cleanup must remove the old berth after the takeoff transition")
current_system_name = "Test & System"

current_hull = selected_starter.hull
current_size = 6
mem.nomad.active_sortie = nil
mem.nomad.active_kind = nil
shared_cache.joyride = nil
owned_ships = {}
landed = false
nomad_apply_rules()
assert(type(info_actions["Launch Shuttle"]) == "function"
   and type(info_actions["Park Carrier"]) == "function",
   "both carrier actions must return after takeoff")

shield = 0
shield_capacity = 0
nomad_park_carrier()
assert(diff_applied and mem.nomad.parked,
   "an unfitted carrier with zero shield capacity must still be parkable")
landed = false
current_spob = nil
nomad_takeoff()
assert(diff_applied and not mem.nomad.parked and mem.nomad.departed_parking,
   "carrier takeoff must retain its departure berth until stable-space cleanup")
local departed_diff_name = current_diff_name
landed = false
nomad_park_carrier()
assert(diff_applied and mem.nomad.departed_parking
   and scheduled_timers[#scheduled_timers].name == "nomad_complete_parking",
   "reparking must keep the active-system berth intact until landing")
nomad_complete_parking()
nomad_landed()
assert(diff_applied and mem.nomad.parked
   and not mem.nomad.departed_parking
   and current_diff_name == departed_diff_name,
   "same-system reparking must reuse the berth without stacking relocation diffs")
landed = false
current_spob = nil
nomad_takeoff()
current_system_name = "Cleanup System"
nomad_apply_rules()
cleanup = scheduled_timers[#scheduled_timers]
nomad_remove_departed_parking(cleanup.arguments[1], cleanup.arguments[2])
assert(not diff_applied and not mem.nomad.departed_parking,
   "carrier departure must remove its old berth in stable space")
current_system_name = "Test & System"

local first_diff_name = current_diff_name
shield = 100
shield_capacity = 100
nomad_park_carrier()
assert(diff_applied and mem.nomad.parked
   and current_diff_name ~= first_diff_name,
   "each parking cycle must use a fresh dynamic-diff name")
landed = false
current_spob = nil
nomad_takeoff()
assert(diff_applied and mem.nomad.departed_parking,
   "repeated parking must retain only its active departure berth")
current_system_name = "Second Cleanup System"
nomad_apply_rules()
cleanup = scheduled_timers[#scheduled_timers]
nomad_remove_departed_parking(cleanup.arguments[1], cleanup.arguments[2])
assert(not diff_applied and not mem.nomad.departed_parking,
   "repeated parking must remove its own location after departure")
current_system_name = "Test & System"

-- The Core's native state is sampled once after braking, before Naev's brake
-- cleanup can alter it. The following poll must use that sampled value.
local function finish_core_parking()
   assert(mem.nomad.parked and diff_applied,
      "an enabled operational core must create a parking berth")
   landed = false
   current_spob = nil
   nomad_takeoff()
   current_system_name = "Core Parking Cleanup"
   nomad_apply_rules()
   local core_cleanup = scheduled_timers[#scheduled_timers]
   nomad_remove_departed_parking(core_cleanup.arguments[1],
      core_cleanup.arguments[2])
   assert(not mem.nomad.parked and not mem.nomad.departed_parking
      and not diff_applied,
      "core parking tests must clean up their temporary berth")
   current_system_name = "Test & System"
end

local function set_core_choice(active)
   shared_cache.nomad_parking_core_choices =
      shared_cache.nomad_parking_core_choices or {}
   shared_cache.nomad_parking_core_choices[99] = active
end

local function begin_core_final_poll(active)
   player_vx, player_vy = config.parking.stop_speed + 1, 0
   nomad_park_carrier(99)
   set_core_choice(active)
   player_vx, player_vy = 0, 0
   nomad_update_parking_brake()
   assert(not mem.nomad.parked
      and scheduled_timers[#scheduled_timers].name == "nomad_complete_parking",
      "the first stopped Core poll must only capture its native state")
end

owned_ships = {{
   name = "Needle", deployed = false,
   ship = {
      nameRaw = function() return "Hyena" end,
      size = function() return 1 end,
   },
}}
mem.nomad.crafts.Needle = { phase = "ready" }
set_core_choice(true)
player_vx, player_vy = config.parking.stop_speed + 1, 0
nomad_park_carrier(99)
nomad_bay_activated {
   outfit = "Small Ship Bay", id = parking_s, on = true,
}
assert(shared_cache.nomad_parking_core_choices[99] == true,
   "launching a bay ship while parking must not alter the Core decision")
player_vx, player_vy = 0, 0
nomad_complete_parking()
nomad_complete_parking()
finish_core_parking()
owned_ships = {}

set_core_choice(true)
player_vx, player_vy = 0, 0
local timers_before_stationary_core = #scheduled_timers
local brakes_before_stationary_core = brake_calls
nomad_park_carrier(99)
assert(not mem.nomad.parked
   and #scheduled_timers == timers_before_stationary_core + 1
   and brake_calls == brakes_before_stationary_core,
   "a stationary Core activation must arm and defer its first stopped poll")
nomad_complete_parking()
assert(not mem.nomad.parked,
   "the deferred first stopped poll must only capture the Core state")
nomad_complete_parking()
finish_core_parking()

begin_core_final_poll(true)
-- This is the exact callback Naev emits when its completed brake task pops.
-- It must occur after the stopped-frame capture and cannot change the result.
set_core_choice(false)
nomad_complete_parking()
finish_core_parking()

begin_core_final_poll(false)
nomad_complete_parking()
assert(not mem.nomad.parked and not diff_applied and not manual_control,
   "a disabled operational core at the first final poll must resume flight")

set_core_choice(true)
player_vx, player_vy = config.parking.stop_speed + 1, 0
nomad_park_carrier(99)
set_core_choice(false)
set_core_choice(true)
player_vx, player_vy = 0, 0
nomad_complete_parking()
nomad_complete_parking()
finish_core_parking()

set_core_choice(true)
player_vx, player_vy = config.parking.stop_speed + 1, 0
nomad_park_carrier(99)
set_core_choice(false)
player_vx, player_vy = 0, 0
nomad_complete_parking()
nomad_complete_parking()
assert(not mem.nomad.parked and not diff_applied and not manual_control,
   "turning the operational core off before the first final poll must resume flight")

set_core_choice(true)
player_vx, player_vy = config.parking.stop_speed + 1, 0
nomad_park_carrier(99)
assert(manual_control
   and shared_cache.nomad_integrated_states[99] == "arming",
   "Core parking must own the carrier brake until completion or cancellation")
set_core_choice(false)
command_launch_call = nil
local restored_core_slot = physical_id(config.operational_core)
player_weapon_sets[1] = { 1, restored_core_slot }
player_weapon_sets[2] = { 2 }
nomad_integrated_system_activated { action = "shuttle" }
player_weapon_sets[1] = {}
player_weapon_sets[2] = {}
nomad_complete_parking()
assert(command_launch_call == config.joyride_client
   and not manual_control and not mem.nomad.parked and not diff_applied
   and shared_cache.nomad_integrated_states[99] == "off"
   and initialized_outfit_slots[#initialized_outfit_slots] == 99,
   "launching the command shuttle must reset the native Core before swapping ships")
shared_cache.nomad_integrated_states[restored_core_slot] = "armed"
shared_cache.nomad_parking_core_choices[restored_core_slot] = true
nomad_joyride_ended({ client = config.joyride_client })
assert(shared_cache.nomad_integrated_states[restored_core_slot] == "off"
   and shared_cache.nomad_parking_core_choices[restored_core_slot] == nil
   and initialized_outfit_slots[#initialized_outfit_slots]
      == restored_core_slot
   and player_weapon_sets[1][1] == 1
   and player_weapon_sets[1][2] == restored_core_slot
   and player_weapon_sets[2][1] == 2,
   "boarding the restored Mule must restore its Core state and weapon sets")
mem.nomad.active_source = nil
command_launch_call = nil
shared_cache.nomad_parking_core_choices = nil
reject_next_diff = true
nomad_park_carrier()
assert(not diff_applied and not mem.nomad.parked
   and carrier_status.title == "Unable to Park Carrier",
   "a rejected dynamic diff must roll parking state back completely")

mem.nomad.parked = {
   system = "Reloaded System", x = 12, y = 34, direction = 0.5,
}
diff_applied = false
landed = true
current_spob = parked_spob
current_system_name = config.parking.storage_system
teleport_call = nil
nomad_restore_parked_diff()
assert(not diff_applied and mem.nomad.parked.diff,
   "loading parked must use the statically placed storage spob")
assert(parked_spob_known == false,
   "loading must erase parked-carrier locations recorded by older saves")
landed = false
current_spob = nil
nomad_takeoff()
assert(teleport_call.destination == "Reloaded System"
   and teleport_call.no_simulate == true and teleport_call.silent == true
   and restored_position.x == 12 and restored_position.y == 34
   and restored_direction == 0.5,
   "taking off after load must restore the recorded system and transform")

landing_allowed = nil
current_hull = "Llama"
nomad_apply_rules()
assert(landing_allowed == nil and ordinary_spob_denied == false,
   "Nomad must remove only its own carrier landing restriction after a swap")
assert(next(info_actions) == nil,
   "carrier actions must be hidden while the player controls another ship")

current_hull = selected_starter.hull
landing_allowed = true
local mothership = {
   name = "Carrier Pilot",
   exists = function() return true end,
   setActiveBoard = function(_, allowed) mothership_boardable = allowed end,
   outfits = function()
      return {
         [1] = { nameRaw = function() return "Medium Ship Bay" end },
         [2] = { nameRaw = function() return "Small Ship Bay" end },
      }
   end,
}
current_hull = "Alpaca"
current_size = 2
nomad_joyride_started({ client = config.joyride_client, pilot = mothership })
assert(attached_mothership.client == config.joyride_client
   and attached_mothership.mothership == mothership,
   "Nomad sorties must attach the commander to the mothership")
mem.nomad.active_source = "command"
owned_ships = {{
   name = selected_starter.hull, deployed = false,
   ship = {
      nameRaw = function() return selected_starter.hull end,
      size = function() return 3 end,
   },
}}
local traded_reaver = {
   nameRaw = function() return "Soromid Reaver" end,
   size = function() return 2 end,
}
current_hull = "Purchased Reaver"
current_size = 2
carrier_status = nil
nomad_ship_acquired(traded_reaver, true)
assert(mem.nomad.virtual_name == "Purchased Reaver"
   and mothership_boardable == true and carrier_status == nil,
   "a legal traded command shuttle must remain returnable to its mothership")
local oversized_trade = {
   nameRaw = function() return "Oversized Shuttle" end,
   size = function() return 3 end,
}
current_hull = "Oversized Shuttle"
current_size = 3
nomad_ship_acquired(oversized_trade, true)
assert(carrier_status and carrier_status.title == "No Compatible Bay",
   "an oversized traded shuttle must report its violation without breaking acquisition hooks")
current_hull = "Alpaca"
current_size = 2
mem.nomad.virtual_name = current_hull
owned_ships = {
   {
      name = selected_starter.hull, deployed = false,
      ship = {
         nameRaw = function() return selected_starter.hull end,
         size = function() return 3 end,
      },
   },
   {
      name = "Voyager", deployed = false,
      ship = {
      nameRaw = function() return "Llama Voyager" end,
      size = function() return 2 end,
      price = function() return 120000 end,
      getSlots = function() return {} end,
      },
   },
}
current_hull = "Voyager"
nomad_ship_acquired(owned_ships[2].ship, false)
assert(handoff_call == nil,
   "acquisition must wait for Joyride to restore the landed shuttle")
current_hull = "Alpaca"
nomad_after_ownership_change(false)
assert(handoff_call == "Voyager" and nojump_value == false
   and mothership_boardable == true,
   "a compatible purchase must use the sortie carrier's snapshotted bays")
handoff_call = nil
owned_ships = {
   owned_ships[1],
   {
      name = "Rejected", deployed = false,
      ship = {
         nameRaw = function() return "Goddard" end,
         size = function() return 6 end,
         price = function() return 900000 end,
         getSlots = function() return {} end,
      },
   },
}
nomad_ship_acquired(owned_ships[2].ship, false)
assert(removed_ship == "Rejected" and refunded_credits == 900000
   and handoff_call == nil and carrier_status.title == "Purchase Refunded",
   "an unusable purchase must be removed and refunded instead of stranding the shuttle")

local hephaestus = {
   nameRaw = function() return "Hephaestus" end,
   size = function() return 6 end,
   price = function() return 12000000 end,
   getSlots = function()
      return {
         { id = 1, type = "Weapon", size = "Large",
            property = "fighter_bay" },
         { id = 2, type = "Weapon", size = "Large",
            property = "fighter_bay" },
         { id = 3, type = "Utility", size = "Medium" },
         { id = 4, type = "Utility", size = "Large" },
      }
   end,
}
owned_ships[#owned_ships + 1] = {
   name = "Hephaestus", deployed = false, ship = hephaestus,
}
nomad_ship_acquired(hephaestus, false)
assert(handoff_call == "Hephaestus",
   "a viable carrier candidate must be offered and handed off after confirmation")
current_hull = selected_starter.hull
current_size = 3
installed_outfits = {
   "Medium Ship Bay", "Small Ship Bay",
   config.shuttle_bay, config.operational_core,
}
nomad_joyride_ended({ client = config.joyride_client })
assert(current_hull == "Hephaestus" and carrier_tags.Hephaestus == true
   and carrier_tags[selected_starter.hull] == nil
   and installed_outfits[1] == "Large Ship Bay"
   and installed_outfits[2] == "Large Ship Bay"
   and installed_outfits[3] == config.shuttle_bay
   and installed_outfits[4] == config.operational_core
   and refunded_credits == 900000,
   "confirmed replacement must retain a fitting incumbent and retrofit the new carrier")
carrier_tags = { [selected_starter.hull] = true }
current_hull = "Alpaca"
current_size = 2
owned_ships = {}
pilot_hook_callbacks = {}
nomad_joyride_started({ client = config.joyride_client, pilot = mothership })
for _, installed in ipairs(pilot_hook_callbacks) do
   assert(installed.callback ~= "nomad_board_mothership",
      "command shuttles must retain Joyride Handler's normal board callback")
end
end_joyride_call = nil
last_player_message = nil
mem.nomad.active_source = "command"
shared_cache.joyride = {
   profile = { client = config.joyride_client },
   pilot = mothership,
   token = 1001,
   kind = "virtual",
}
nomad_hail_mothership()
assert(end_joyride_call == nil
   and scheduled_timers[#scheduled_timers].name ==
      "nomad_complete_mothership_hail",
   "mothership hailing must defer the transition until comms have closed")
hail_timer = scheduled_timers[#scheduled_timers]
nomad_complete_mothership_hail(hail_timer.arguments[1])
assert(last_player_message:find("must dock", 1, true),
   "hailing from the command shuttle must not bypass its docking return path")

landed = true
nomad_landed()
assert(shared_cache.joyride.follow_mothership == false,
   "landing during a sortie must pause delayed mothership jump-ins")
current_hull = "Landed Ship"
current_size = 2
mem.nomad.active_kind = "virtual"
mem.nomad.active_source = "command"
mem.nomad.virtual_name = "Alpaca"
nomad_joyride_controlled_changed {
   client = config.joyride_client,
   controlled = current_hull,
}
assert(mem.nomad.active_source == "bay"
   and mem.nomad.active_kind == "owned"
   and mem.nomad.virtual_name == nil
   and mem.nomad.controlled_craft == current_hull
   and mem.nomad.crafts[current_hull].phase == "controlled",
   "selecting an owned ship while landed must end command-shuttle restrictions")

-- Takeoff is an engine-confirmed lifecycle boundary. Recover there too if an
-- older or interrupted session missed Joyride's controlled-change event.
current_hull = "Recovered Ship"
mem.nomad.active_kind = "virtual"
mem.nomad.active_source = "command"
mem.nomad.controlled_craft = nil
mem.nomad.virtual_name = "Alpaca"
shared_cache.joyride.kind = "owned"
shared_cache.joyride.controlled = current_hull
shared_cache.joyride.pilot = nil
landed = false
nomad_takeoff()
assert(mem.nomad.active_source == "bay"
   and mem.nomad.active_kind == "owned"
   and mem.nomad.virtual_name == nil
   and mem.nomad.controlled_craft == current_hull
   and mem.nomad.crafts[current_hull].phase == "controlled"
   and shared_cache.joyride.follow_mothership == true
   and shared_cache.joyride.pilot,
   "taking off in an owned ship must recover the sortie without jumping the carrier")

-- The following cases exercise independent virtual-sortie boundaries.
mem.nomad.controlled_craft = nil
mem.nomad.crafts["Landed Ship"] = nil
mem.nomad.crafts["Recovered Ship"] = nil
mem.nomad.active_kind = "virtual"
mem.nomad.active_source = "bay"
current_hull = "Soromid Ira"
current_size = 5
mem.nomad.virtual_name = current_hull
nomad_hail_mothership()
assert(end_joyride_call == nil,
   "bay-craft seat transfer must not remove the hailed carrier in its hail hook")
hail_timer = scheduled_timers[#scheduled_timers]
nomad_complete_mothership_hail(hail_timer.arguments[1])
assert(end_joyride_call and end_joyride_call.seat_transfer == true,
   "a large bay craft must not be audited as the command shuttle")
mem.nomad.active_kind = "virtual"
mem.nomad.active_source = nil
current_hull = "Alpaca"
current_size = 2

current_hull = "Llama"
current_size = 3
mem.nomad.virtual_name = current_hull
mem.nomad.active_source = "command"
nomad_apply_rules()
assert(nojump_value == true and nojump_marker == true,
   "an oversized command-shuttle trade must receive Nomad's no-jump marker")
current_size = 2
nomad_apply_rules()
assert(nojump_value == false and nojump_marker == nil,
   "a compatible replacement must immediately clear only Nomad's marker")
mem.nomad.active_source = nil

current_hull = selected_starter.hull
current_size = 6
landing_allowed = nil
nomad_joyride_ended({ client = config.joyride_client })
assert(landing_allowed == nil and ordinary_spob_denied == true,
   "returning from a Nomad sortie must restore the carrier landing rule")
assert(released_mothership == config.joyride_client,
   "returning must release the commander from the mothership")

local parked_scout_type = {
   nameRaw = function() return "Hyena" end,
   size = function() return 1 end,
}
current_hull = "Fresh Parked Scout (Sortie)"
current_size = 1
owned_ships = {{
   name = "Fresh Parked Scout", deployed = false, ship = parked_scout_type,
}}
mem.nomad.crafts["Fresh Parked Scout"] = {
   phase = "controlled",
   snapshot = {
      hull = "Hyena", size = 1, outfits = {}, cargo = {},
      armour = 100, shield = 100, energy = 100,
   },
}
mem.nomad.controlled_craft = "Fresh Parked Scout"
mem.nomad.active_kind = "owned"
mem.nomad.active_source = "bay"
mem.nomad.parked = { carrier = selected_starter.hull }
shared_cache.joyride = { kind = "owned" }
player_x, player_y = 2468.5, -1357.25
nomad_hail_mothership()
hail_timer = scheduled_timers[#scheduled_timers]
nomad_complete_mothership_hail(hail_timer.arguments[1])
mem.nomad.parked = nil
current_hull = selected_starter.hull
current_size = 6
owned_ships = {}
last_player_message = nil
nomad_joyride_ended({
   client = config.joyride_client,
   returned_kind = "owned",
   snapshot = mem.nomad.crafts["Fresh Parked Scout"].snapshot,
})
local parked_scout_bay = physical_id("Large Ship Bay", 1)
assert(live_pilots[#live_pilots]:exists()
   and live_pilots[#live_pilots]:name() == "Fresh Parked Scout"
   and live_pilots[#live_pilots]:pos().x == 2468.5
   and live_pilots[#live_pilots]:pos().y == -1357.25
   and mem.nomad.controlled_craft == nil
   and mem.nomad.crafts["Fresh Parked Scout"].phase == "deployed"
   and shared_cache.nomad_bay_states[parked_scout_bay] == true
   and shared_cache.nomad_bay_cooldowns[parked_scout_bay] == nil
   and last_player_message == nil,
   "parked takeoff must return through the ordinary immediate bay replacement")
nomad_after_ownership_change(false)
assert(mem.nomad.crafts["Fresh Parked Scout"]
   and live_pilots[#live_pilots]:exists()
   and shared_cache.nomad_bay_states[parked_scout_bay] == true,
   "a queued ownership audit must retain the live bay craft and active outfit")
owned_ships = {{
   name = "Fresh Parked Scout", deployed = false, ship = parked_scout_type,
}}
nomad_after_ownership_change(false)
assert(mem.nomad.crafts["Fresh Parked Scout"]
   and live_pilots[#live_pilots]:exists()
   and shared_cache.nomad_bay_states[parked_scout_bay] == true,
   "the ordinary ownership audit must retain the restored bay pilot")

-- Reproduce the complete reported sequence. Even if the preceding bay return
-- has left its controlled-craft marker visible until its custom event finishes,
-- command launch must identify itself before Joyride synchronously spawns the
-- carrier. Nomad must therefore leave the normal command docking hook alone.
command_launch_call = nil
pilot_hook_callbacks = {}
mem.nomad.controlled_craft = "Fresh Parked Scout"
mem.nomad.active_source = "bay"
shared_cache.joyride = nil
nomad_launch_command_shuttle()
assert(command_launch_call == config.joyride_client
   and mem.nomad.active_source == "command",
   "command launch after a parked bay return must declare its lifecycle before spawning")
shared_cache.joyride = { profile = { client = config.joyride_client } }
nomad_joyride_started({ client = config.joyride_client, pilot = mothership })
for _, installed in ipairs(pilot_hook_callbacks) do
   assert(installed.callback ~= "nomad_board_mothership",
      "stale parked-return state must not replace the command shuttle docking hook")
end

print("ok - nomad event boundaries")
