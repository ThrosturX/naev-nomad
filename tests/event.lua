package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path
local swap_call
local borrow_call
package.preload.joyride = function()
   return {
      swap_to_subship = function(carrier, template, acquired, profile)
         swap_call = {
            carrier = carrier, template = template,
            acquired = acquired, profile = profile,
         }
      end,
      end_joyride = function() end,
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
tk = { msg = function() end, choice = function() return 1 end }

local ensured_commander
local attached_mothership
local released_mothership
local fleet_capacity
local commander = { name = "Nomad Commander", faction = "Independent" }
package.preload["crewmates.api"] = function()
   return {
      is_ready = function() return true end,
      ensure_commander = function(client, options)
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
   }
end

local config = require "nomad.config"

local active_var
local carrier_tag
local starting_bays = {}
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
   shipvarPush = function(key, value)
      carrier_tag = { key = key, value = value }
   end,
   pilot = function()
      return {
         outfitRm = function(_, what) carrier_tag.unarmed = what end,
         outfitAdd = function(_, what) starting_bays[#starting_bays + 1] = what end,
      }
   end,
}

dofile("events/nomad_start.lua")
create()
assert(active_var.key == config.active_var and active_var.value == true,
   "Nomad start must mark only newly created pilots")
assert(#chained_events == 1 and chained_events[1] == "start_event",
   "Nomad start must retain Naev's standard setup")
assert(start_finished == true, "Nomad start marker event must finish successfully")
assert(carrier_tag.key == config.carrier_shipvar and carrier_tag.value == true,
   "Nomad start must tag the actual owned carrier")
assert(carrier_tag.unarmed == "all", "the starting carrier must be unarmed")
assert(#starting_bays == 5 and starting_bays[1] == config.command_bay.outfit,
   "the starting carrier must receive all configured bay controls")

local current_hull = config.carrier.hull
local landing_allowed
local landing_reason
local registered = {}
local current_size = 6
local nojump_marker
local nojump_value
local explicit_current_shipvar_lookup
local restored_carrier_name
local installed_outfits = {}
local carrier_status
local owned_ships = {}
local shared_cache = {}
local deploy_call
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
   pos = function() return "position" end,
   vel = function() return "velocity" end,
   dir = function() return 0 end,
}
player = {
   pilot = function() return current_pilot end,
   ship = function() return current_hull end,
   ships = function() return owned_ships end,
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
   infoButtonRegister = function(_, callback)
      assert(type(callback) == "function",
         "Naev info buttons require a function callback")
      return 1
   end,
   infoButtonUnregister = function() end,
   commClose = function() end,
   msg = function() end,
   shipDeploy = function(name, deploy, escort)
      deploy_call = { name = name, deploy = deploy, escort = escort }
      for _, entry in ipairs(owned_ships) do
         if entry.name == name then entry.deployed = deploy end
      end
   end,
}
naev.cache = function() return shared_cache end
naev.claimTest = function() return true end
system = { cur = function() return "Test System" end }
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
   safe = function(name, argument) _G[name](argument) end,
   pilot = function() end,
   custom = function(name, callback) registered[name] = callback end,
}
evt = { save = function(saved) registered.saved = saved end }
_ = function(message) return message end
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
assert(registered.ship_swap == "nomad_ship_changed",
   "carrier landing rules must follow ship changes")
assert(registered.load == "nomad_defer_initialize",
   "load hooks must defer commander registration until the spob is restored")
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
local installed_counts = {}
for _, name in ipairs(installed_outfits) do
   installed_counts[name] = (installed_counts[name] or 0) + 1
end
assert(#installed_outfits == 5
   and installed_counts[config.command_bay.outfit] == 1
   and installed_counts["Nomad XL Bay"] == 1
   and installed_counts["Nomad L Bay"] == 1
   and installed_counts["Nomad S Bay"] == 2,
   "Nomad initialization must restore each configured bay exactly once")
installed_outfits[#installed_outfits + 1] = "Nomad S Bay"
nomad_initialize()
installed_counts = {}
for _, name in ipairs(installed_outfits) do
   installed_counts[name] = (installed_counts[name] or 0) + 1
end
assert(#installed_outfits == 5 and installed_counts["Nomad S Bay"] == 2,
   "restored carriers must discard duplicate control outfits")
assert(fleet_capacity == config.fleet_capacity,
   "Nomad pilots must receive generous vanilla fleet capacity")

nomad_carrier_menu()
assert(carrier_status and carrier_status.title == "Nomad Carrier"
   and carrier_status.message:find("S command: Alpaca", 1, true),
   "an empty carrier menu must show bay status without a choice dialog")

local function physical_id(outfit_name, occurrence)
   local found = 0
   for id, name in ipairs(installed_outfits) do
      if name == outfit_name then
         found = found + 1
         if found == (occurrence or 1) then return id end
      end
   end
end

nomad_bay_activated {
   outfit = config.command_bay.outfit,
   id = physical_id(config.command_bay.outfit),
}
assert(swap_call and swap_call.profile.client == config.joyride_client,
   "command activation must launch and transfer control through Joyride")

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
assert(swap_call and not borrow_call,
   "general-bay activation must not start an owned-ship Joyride")
assert(shared_cache.nomad_bay_tooltips[first_s] == "Deployed: Needle (Hyena)",
   "launching must refresh the physical control's deployed tooltip")
nomad_bay_activated { outfit = "Nomad S Bay", id = first_s }
assert(deploy_call.deploy == false and deploy_call.escort == false,
   "deployed general-bay ships must be recalled by the same control")
assert(shared_cache.nomad_bay_tooltips[first_s] == "Assigned: Needle (Hyena)",
   "recalling must refresh the physical control's assigned tooltip")

deploy_call = nil
owned_ships = {}
nomad_bay_activated {
   outfit = "Nomad XL Bay",
   id = physical_id("Nomad XL Bay"),
}
assert(not deploy_call, "activating an empty general bay must change nothing")

owned_ships = {{
   name = "Needle", deployed = true,
   ship = {
      nameRaw = function() return "Hyena" end,
      size = function() return 1 end,
   },
}}
nomad_hail_owned("Needle")
assert(borrow_call and borrow_call.name == "Needle",
   "hailing a deployed general-bay ship must retain the owned Joyride path")
mem.nomad.active_kind = nil
mem.nomad.active_sortie = nil
owned_ships = {}

landing_allowed = nil
current_hull = "Llama"
nomad_apply_rules()
assert(landing_allowed == true,
   "Nomad must remove only its own carrier landing restriction after a swap")

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
