local config = {}

config.state_version = 0
config.joyride_client = "nomad"
config.joyride_profile = {
   client = config.joyride_client,
   landable = true,
   landed_ship_lock = true,
   protect_mothership_sale = true,
   trade_replacement = true,
   owned_handoff = true,
   owned_escorts = true,
}
config.active_var = "nomad_active"
config.crewmates_event = "Companion Handler000"
config.handler_event = "Nomad Fleet Handler"
config.carrier_shipvar = "nomad_carrier"
config.nojump_shipvar = "nomad_nojump"
config.fleet_capacity = 10000
config.bay_classes = { S = 2, M = 4, L = 5, XL = 6 }

config.carrier = {
   hull = "Soromid Arx",
   name = "El Ego de Deiz",
   acquired = "Your carrier and home among the stars.",
}

-- A plain temporary hull is replaced after player initialization so ship Lua
-- never receives an invalid pilot while Naev is constructing the new player.
config.bootstrap = {
   hull = "Llama",
   name = "Nomad Bootstrap",
   cleanup_outfits = { "Laser Cannon MK1" },
}

config.command_bay = {
   name = "S command",
   max_size = config.bay_classes.S,
}

config.general_bays = {
   ["Nomad S Bay"] = { name = "S", max_size = config.bay_classes.S,
      outfit = "Nomad S Bay" },
   ["Nomad M Bay"] = { name = "M", max_size = config.bay_classes.M,
      outfit = "Nomad M Bay" },
   ["Nomad L Bay"] = { name = "L", max_size = config.bay_classes.L,
      outfit = "Nomad L Bay" },
   ["Nomad XL Bay"] = { name = "XL", max_size = config.bay_classes.XL,
      outfit = "Nomad XL Bay" },
}

config.starter_bays = {
   "Nomad M Bay",
   "Nomad S Bay",
}

config.spare_bays = {
   ["Nomad S Bay"] = 2,
   ["Nomad M Bay"] = 2,
   ["Nomad L Bay"] = 2,
   ["Nomad XL Bay"] = 2,
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

config.minimum_crew = { commander = 1 }

return config
