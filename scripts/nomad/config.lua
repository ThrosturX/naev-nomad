local config = {}

config.state_version = 0
config.joyride_client = "nomad"
config.joyride_profile = {
   client = config.joyride_client,
   landable = true,
   trade_replacement = true,
   owned_handoff = true,
}
config.active_var = "nomad_active"
config.start_chapter_var = "nomad_start_chapter"
config.crewmates_event = "Companion Handler000"
config.handler_event = "Nomad Fleet Handler"
config.carrier_shipvar = "nomad_carrier"
config.nojump_shipvar = "nomad_nojump"
config.fleet_capacity = 10000
config.bay_classes = { S = 2, M = 4, L = 5, XL = 6 }

config.starter_carriers = {
   {
      hull = "Mule",
      name = "Workhorse",
      acquired = "Your carrier and home among the stars.",
      credits = 30000,
      choice = "Mule — 30,000 credits",
      bays = { "Medium Ship Bay", "Small Ship Bay" },
   },
   {
      hull = "Soromid Arx",
      name = "Muoiyja",
      acquired = "Your carrier and home among the stars.",
      credits = 20000000,
      choice = "Soromid Arx — 20,000,000 credits and a Soromid flotilla",
      bays = { "XL Ship Bay", "XL Ship Bay", "XL Ship Bay" },
      chapter = "1",
      command_shuttle = "Soromid Brigand",
      roster = {
         {
            hull = "Soromid Vox",
            name = "Deep Thunder",
            acquired = "A battleship carried by your first Nomad home.",
            size = 6,
         },
         {
            hull = "Soromid Ira",
            name = "Long Memory",
            acquired = "A cruiser carried by your first Nomad home.",
            size = 5,
         },
         {
            hull = "Soromid Reaver",
            name = "Swift Thorn",
            acquired = "A fighter carried by your first Nomad home.",
            size = 2,
         },
      },
   },
   {
      -- This starter-only Raven refit inherits the stock Pirate Starbridge.
      -- Its two converted mounts make the requested hull a valid first home
      -- without changing the eligibility rules for later carrier purchases.
      hull = "Raven Starbridge",
      name = "Nevermore",
      acquired = "Your carrier and home among the stars.",
      credits = 350000,
      choice = "Raven Clan Pirate Starbridge — 350,000 credits",
      bays = { "Medium Ship Bay", "Small Ship Bay" },
      start_system = "Qorel",
      home_spob = "Qorellia",
      known_jumps = { "Doowa", "Trask" },
      reputation = {
         faction = "Raven Clan",
         value = 20,
         pirate_value = 20,
      },
   },
}

config.operational_core = "Nomadic Operational Core"
config.shuttle_bay = "Shuttle Bay"
config.integrated_systems = {
   {
      outfit = config.operational_core,
      minimum_size = "Large",
      preference = "largest",
   },
   {
      outfit = config.shuttle_bay,
      minimum_size = "Medium",
      preference = "smallest",
   },
}

-- A plain temporary hull is replaced after player initialization so ship Lua
-- never receives an invalid pilot while Naev is constructing the new player.
config.bootstrap = {
   hull = "Llama",
   name = "Nomad Bootstrap",
}

config.command_bay = {
   name = "S command",
   max_size = config.bay_classes.S,
}

config.general_bays = {
   ["Small Ship Bay"] = { name = "S", max_size = config.bay_classes.S,
      outfit = "Small Ship Bay" },
   ["Medium Ship Bay"] = { name = "M", max_size = config.bay_classes.M,
      outfit = "Medium Ship Bay" },
   ["Large Ship Bay"] = { name = "L", max_size = config.bay_classes.L,
      outfit = "Large Ship Bay" },
   ["XL Ship Bay"] = { name = "XL", max_size = config.bay_classes.XL,
      outfit = "XL Ship Bay" },
}

config.bay_outfit_by_slot_size = {
   Small = "Small Ship Bay",
   Medium = "Medium Ship Bay",
   Large = "XL Ship Bay",
}

config.starter_bays = {
   "Medium Ship Bay",
   "Small Ship Bay",
}

config.spare_bays = {
   ["Small Ship Bay"] = 2,
   ["Medium Ship Bay"] = 2,
   ["Large Ship Bay"] = 2,
   ["XL Ship Bay"] = 2,
}

config.parking = {
   diff = "Nomad Parked Carrier Location",
   spob = "Nomad Parked Carrier",
   storage_system = "Nomad Carrier Storage",
   minimum_shield = 90,
}
config.starter_subship = {
   id = "nomad_starter_shuttle",
   name = "Nomad Shuttle",
   hull = "Alpaca",
   size = 1,
   role = "shuttle",
}

function config.command_shuttle_for(carrier_hull)
   for _, starter in ipairs(config.starter_carriers) do
      if starter.hull == carrier_hull and starter.command_shuttle then
         return starter.command_shuttle
      end
   end
   return config.starter_subship.hull
end

config.minimum_crew = { commander = 1 }

return config
