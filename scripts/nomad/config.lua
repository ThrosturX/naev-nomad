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
config.carrier_shipvar = "nomad_carrier"
config.nojump_shipvar = "nomad_nojump"
config.fleet_capacity = 10000
config.bay_classes = { S = 2, M = 4, L = 5, XL = 6 }

config.carrier = {
   hull = "Za'lek Hephaestus",
   bays = {
      { name = "XL", max_size = config.bay_classes.XL, outfit = "Nomad XL Bay" },
      { name = "L", max_size = config.bay_classes.L, outfit = "Nomad L Bay" },
      { name = "S", max_size = config.bay_classes.S, outfit = "Nomad S Bay" },
      { name = "S", max_size = config.bay_classes.S, outfit = "Nomad S Bay" },
   },
}

config.command_bay = {
   name = "S command",
   max_size = config.bay_classes.S,
   outfit = "Nomad Command Bay",
}

config.installed_bays = {
   config.command_bay.outfit,
   config.carrier.bays[1].outfit,
   config.carrier.bays[2].outfit,
   config.carrier.bays[3].outfit,
   config.carrier.bays[4].outfit,
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
