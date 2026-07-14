package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path
local swap_call
local borrow_call
local comm_close_calls = 0
local end_joyride_call
local command_launch_call
local command_launch_failure
package.preload.joyride = function()
   return {
      swap_to_subship = function(carrier, template, acquired, profile)
         swap_call = {
            carrier = carrier, template = template,
            acquired = acquired, profile = profile,
         }
      end,
      end_joyride = function(options)
         end_joyride_call = options or {}
         return true
      end,
      handoff_to_owned = function() end,
      borrow_owned = function(name, profile)
         borrow_call = { name = name, profile = profile }
         return true
      end,
      launch_owned = function() end,
      recall_owned = function() end,
   }
end
package.preload.format = function()
   return {
      f = function(text, values)
         return (text:gsub("{([%w_]+)}", function(key)
            return tostring(values[key])
         end))
      end,
   }
end
local toolkit_open = false
tk = {
   msg = function() end,
   choice = function() return 1 end,
   isOpen = function() return toolkit_open end,
}
_ = function(message) return message end

local ensured_commander
local ensure_commander_calls = 0
local attached_mothership
local released_mothership
local fleet_capacity
local commander = { name = "Nomad Commander", faction = "Independent" }
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

local active_var
local carrier_tag
local starting_bays = {}
local starting_install_attempts = {}
local starting_inventory = {}
local starting_removed = {}
local starting_ship_add
local starting_ship_swap
local chained_events = {}
local start_finished
var = {
   push = function(key, value)
      active_var = { key = key, value = value }
   end,
}
naev = {
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
   shipAdd = function(hull, name, acquired, noname)
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
   outfitAdd = function(name, quantity)
      starting_inventory[name] = (starting_inventory[name] or 0) + (quantity or 1)
   end,
   pilot = function()
      return {
         outfitAdd = function(_, what)
            starting_install_attempts[#starting_install_attempts + 1] = what
            if what == "Nomad S Bay" then return 0 end
            starting_bays[#starting_bays + 1] = what
            return 1
         end,
         outfitRm = function(_, what, quantity)
            starting_removed[what] = (starting_removed[what] or 0)
               + (quantity or 1)
            return quantity or 1
         end,
      }
   end,
}

dofile("events/nomad_start.lua")
create()
assert(active_var.key == config.active_var and active_var.value == true,
   "Nomad start must mark only newly created pilots")
assert(#chained_events == 3 and chained_events[1] == "start_event"
   and chained_events[2] == config.crewmates_event
   and chained_events[3] == config.handler_event,
   "Nomad start must initialize Crewmates before its persistent handler")
assert(start_finished == true, "Nomad start marker event must finish successfully")
assert(carrier_tag.key == config.carrier_shipvar and carrier_tag.value == true,
   "Nomad start must tag the actual owned carrier")
assert(starting_ship_add.hull == config.carrier.hull
   and starting_ship_add.name == config.carrier.name
   and starting_ship_add.noname == true,
   "Nomad start must create the configured carrier after player initialization")
assert(starting_ship_swap.name == config.carrier.name
   and starting_ship_swap.ignore_cargo == true
   and starting_ship_swap.remove == true,
   "Nomad start must atomically replace the temporary bootstrap hull")
assert(#starting_install_attempts == 2 and #starting_bays == 1
   and starting_bays[1] == "Nomad M Bay",
   "Nomad start must attempt every configured starter bay")
for name, quantity in pairs(config.spare_bays) do
   local failed_starter = name == "Nomad S Bay" and 1 or 0
   assert(starting_inventory[name] == quantity + failed_starter,
      "new Nomad pilots must receive every configured spare bay control")
end
for _, name in ipairs(config.bootstrap.cleanup_outfits) do
   assert(starting_removed[name] == 1,
      "bootstrap-only outfits must be removed after the vanilla start event")
end

local current_hull = config.carrier.hull
local landing_allowed
local landing_reason
local registered = {}
local current_size = 6
local nojump_marker
local nojump_value
local explicit_current_shipvar_lookup
local restored_carrier_name
local installed_outfits = { "Nomad M Bay", "Nomad S Bay" }
local carrier_status
local owned_ships = {}
local shared_cache = {}
local deploy_call
local landed = false
local shield = 100
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
local inventory_counts = { ["Nomad S Bay"] = 3 }
local last_player_message
local scheduled_timers = {}
local teleport_call
local current_system_name = "Test & System"
mem = {}
local current_pilot = {
   ship = function()
      return {
         nameRaw = function() return current_hull end,
         size = function() return current_size end,
      }
   end,
   flags = function() return { nojump = nojump_value == true } end,
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
   pos = function()
      return { get = function() return 321.25, -654.5 end }
   end,
   vel = function() return "velocity" end,
   dir = function() return 0 end,
   health = function() return 100, shield end,
   setPos = function(_, value) restored_position = value end,
   setDir = function(_, value) restored_direction = value end,
   setVel = function(_, value) restored_velocity = value end,
}
player = {
   pilot = function() return current_pilot end,
   ship = function() return current_hull end,
   ships = function() return owned_ships end,
   isLanded = function() return landed end,
   land = function(target)
      landed = true
      current_spob = target
   end,
   landAllow = function(allowed, reason)
      landing_allowed = allowed
      landing_reason = reason
   end,
   shipvarPeek = function(key, name)
      if name == current_hull then explicit_current_shipvar_lookup = true end
      if key == config.carrier_shipvar then
         return (name or current_hull) == config.carrier.hull
      end
      if key == config.nojump_shipvar then return nojump_marker end
      return false
   end,
   shipvarPush = function(key, value, name)
      if key == config.nojump_shipvar then nojump_marker = value end
      if key == config.carrier_shipvar then restored_carrier_name = name end
   end,
   shipvarPop = function(key)
      if key == config.nojump_shipvar then nojump_marker = nil end
   end,
   fleetCapacitySet = function(value) fleet_capacity = value end,
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
   outfitRm = function(name, quantity)
      inventory_removals[#inventory_removals + 1] = {
         name = name, quantity = quantity,
      }
      inventory_counts[name] = (inventory_counts[name] or 0) - quantity
      return quantity
   end,
   outfitNum = function(name) return inventory_counts[name] or 0 end,
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
local test_system = { nameRaw = function() return current_system_name end }
system = { cur = function() return test_system end }
local parked_spob = { nameRaw = function() return config.parking.spob end }
spob = {
   get = function(name)
      if name == config.parking.spob then return parked_spob end
   end,
   cur = function() return current_spob end,
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
      return true
   end,
   remove = function(name)
      assert(name == current_diff_name)
      diff_applied = false
   end,
}
vec2 = { new = function(x, y) return { x = x or 0, y = y or 0 } end }
pilot = {
   get = function() return {} end,
   add = function()
      return { setVel = function() end, setDir = function() end }
   end,
}
hook = {
   enter = function(name) registered.enter = name end,
   land = function(name) registered.land = name end,
   takeoff = function(name) registered.takeoff = name end,
   load = function(name) registered.load = name end,
   ship_swap = function(name) registered.ship_swap = name end,
   ship_buy = function(name) registered.ship_buy = name end,
   ship_sell = function(name) registered.ship_sell = name end,
   safe = function(name, argument)
      _G[name](argument)
   end,
   timer = function(delay, name)
      scheduled_timers[#scheduled_timers + 1] = { delay = delay, name = name }
   end,
   pilot = function() end,
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
assert(landing_allowed == false and landing_reason:find("cannot land"),
   "the configured carrier must be prevented from landing")
assert(registered.enter == "nomad_apply_rules",
   "carrier landing rules must be restored after jumping")
assert(registered.land == "nomad_landed",
   "parking must only be verified by the completed-land hook")
assert(registered.ship_swap == "nomad_ship_changed",
   "carrier landing rules must follow ship changes")
assert(registered.takeoff == "nomad_takeoff",
   "takeoff hooks must restore a parked carrier")
assert(registered.load == "nomad_restore_parked_diff",
   "load hooks must restore the dynamic spob before initialization")
assert(registered.saved == true, "Nomad campaign state must persist")
assert(ensured_commander.client == config.joyride_client,
   "Nomad must register its commander requirement with Crewmates")
assert(ensured_commander.options.minimum == config.minimum_crew.commander
   and ensured_commander.options.shuttle == config.starter_subship.hull
   and ensured_commander.options.shuttle_profile.client == config.joyride_client
   and ensured_commander.options.shuttle_profile.landable == true
   and ensured_commander.options.shuttle_profile.landed_ship_lock == true
   and ensured_commander.options.shuttle_profile.protect_mothership_sale == true,
   "Crewmates must guarantee the configured commander and shuttle")
assert(#installed_outfits == 2 and installed_outfits[1] == "Nomad M Bay"
   and installed_outfits[2] == "Nomad S Bay",
   "Nomad initialization must preserve the player's bay configuration")
installed_outfits[1] = "Nomad L Bay"
nomad_initialize()
assert(installed_outfits[1] == "Nomad L Bay",
   "restored carriers must not overwrite manually selected bay controls")
installed_outfits[1] = "Nomad M Bay"
assert(fleet_capacity == config.fleet_capacity,
   "Nomad pilots must receive generous vanilla fleet capacity")
assert(type(info_actions["Launch Shuttle"]) == "function"
   and type(info_actions["Park Carrier"]) == "function",
   "the carrier info menu must expose command launch and parking actions")

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
local first_s = physical_id("Nomad S Bay", 1)
nomad_bay_activated { outfit = "Nomad S Bay", id = first_s }
assert(deploy_call and deploy_call.name == "Needle"
   and deploy_call.deploy == true and deploy_call.escort == true,
   "stored general-bay ships must launch as vanilla escorts")
assert(not command_launch_call and not borrow_call,
   "general-bay activation must not start an owned-ship Joyride")
assert(shared_cache.nomad_bay_tooltips[first_s] == "Deployed: Needle (Hyena)",
   "launching must refresh the physical control's deployed tooltip")
assert(shared_cache.nomad_bay_assignments[first_s].name == "Needle",
   "assigned ships must be cached by their physical bay controls")
nomad_bay_activated { outfit = "Nomad S Bay", id = first_s }
assert(deploy_call.deploy == false and deploy_call.escort == false,
   "deployed general-bay ships must be recalled by the same control")
assert(shared_cache.nomad_bay_tooltips[first_s] == "Assigned: Needle (Hyena)",
   "recalling must refresh the physical control's assigned tooltip")

installed_outfits[first_s] = nil
nomad_occupied_bay_removed {
   id = first_s,
   outfit = "Nomad S Bay",
   ship = { name = "Needle", hull = "Hyena" },
   inventory = 2,
}
assert(installed_outfits[first_s] == "Nomad S Bay"
   and inventory_removals[#inventory_removals].name == "Nomad S Bay"
   and carrier_status.title == "Bay In Use",
   "removing an occupied bay must restore it and balance the inventory copy")

deploy_call = nil
owned_ships = {}
nomad_bay_activated { outfit = "Nomad M Bay", id = physical_id("Nomad M Bay") }
assert(not deploy_call, "activating an empty general bay must change nothing")

owned_ships = {{
   name = "Needle", deployed = true,
   ship = {
      nameRaw = function() return "Hyena" end,
      size = function() return 1 end,
   },
}}
nomad_hail_owned("Needle")
assert(borrow_call and borrow_call.name == "Needle" and comm_close_calls > 0,
   "hailing a deployed general-bay ship must retain the owned Joyride path")
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
info_actions["Park Carrier"]()
assert(not diff_applied and not mem.nomad.parked
   and last_player_message:find("Close the Info window", 1, true)
   and scheduled_timers[#scheduled_timers].name == "nomad_complete_parking",
   "parking must wait until the Info window has closed")
toolkit_open = false
nomad_complete_parking()
assert(diff_applied and mem.nomad.parked
   and info_actions["Park Carrier"] ~= nil,
   "starting an asynchronous landing must retain the dynamic spob")
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
assert(next(info_actions) == nil,
   "carrier actions must be hidden while the carrier is landed")

landed = false
current_spob = nil
nomad_takeoff()
assert(not mem.nomad.parked and not diff_applied
   and teleport_call == nil
   and restored_position.x == 321.25 and restored_position.y == -654.5
   and restored_direction == 0
   and restored_velocity.x == 0 and restored_velocity.y == 0,
   "same-system takeoff must synchronously remove the spob and restore the exact carrier transform")
assert(type(info_actions["Launch Shuttle"]) == "function"
   and type(info_actions["Park Carrier"]) == "function",
   "both carrier actions must return after takeoff")

local first_diff_name = current_diff_name
shield = 100
nomad_park_carrier()
assert(diff_applied and mem.nomad.parked
   and current_diff_name ~= first_diff_name,
   "each parking cycle must use a fresh dynamic-diff name")
landed = false
current_spob = nil
nomad_takeoff()
assert(not diff_applied,
   "repeated parking must remove its own dynamic location cleanly")

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
assert(landing_allowed == true,
   "Nomad must remove only its own carrier landing restriction after a swap")
assert(next(info_actions) == nil,
   "carrier actions must be hidden while the player controls another ship")

current_hull = config.carrier.hull
landing_allowed = true
local mothership = {
   name = "Carrier Pilot",
   exists = function() return true end,
   setActiveBoard = function() end,
}
nomad_joyride_started({ client = config.joyride_client, pilot = mothership })
assert(attached_mothership.client == config.joyride_client
   and attached_mothership.mothership == mothership,
   "Nomad sorties must attach the commander to the mothership")
end_joyride_call = nil
last_player_message = nil
nomad_hail_mothership()
assert(end_joyride_call == nil
   and last_player_message:find("must dock", 1, true),
   "hailing from the command shuttle must not bypass its docking return path")
mem.nomad.active_kind = "owned"
nomad_hail_mothership()
assert(end_joyride_call and end_joyride_call.redeploy_owned == true,
   "hailing from an owned ship must return control and redeploy that ship")
mem.nomad.active_kind = "virtual"
assert(registered.joyride_mothership_restored == "nomad_mothership_restored",
   "Nomad must listen for restored mothership ownership")
nomad_mothership_restored({
   client = config.joyride_client,
   name = "Restored Carrier",
})
assert(restored_carrier_name == "Restored Carrier",
   "a restored mothership must recover its stable carrier tag")

current_hull = "Llama"
current_size = 3
mem.nomad.virtual_name = current_hull
nomad_apply_rules()
assert(nojump_value == true and nojump_marker == true,
   "an oversized command-shuttle trade must receive Nomad's no-jump marker")
current_size = 2
nomad_apply_rules()
assert(nojump_value == false and nojump_marker == nil,
   "a compatible replacement must immediately clear only Nomad's marker")

current_hull = config.carrier.hull
current_size = 6
nomad_joyride_ended({ client = config.joyride_client })
assert(landing_allowed == false,
   "returning from a Nomad sortie must restore the carrier landing rule")
assert(released_mothership == config.joyride_client,
   "returning must release the commander from the mothership")

print("ok - nomad event boundaries")
