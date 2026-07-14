package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local config = require "nomad.config"

local function read_file(path)
   local file = assert(io.open(path, "r"))
   local contents = file:read("*a")
   file:close()
   return contents
end

local scenario = read_file("start.toml")
local starting_hull = scenario:match('ship_model%s*=%s*"([^"]+)"')
local starting_event = scenario:match('event%s*=%s*"([^"]+)"')
assert(starting_hull == config.bootstrap.hull,
   "scenario must use the non-Lua bootstrap hull")
assert(config.bootstrap.hull ~= config.carrier.hull,
   "the carrier must be created after player_newShipMake")
assert(starting_event == "Nomad Start",
   "the scenario must use the event that marks new Nomad pilots")

local handler = read_file("events/nomad.lua")
local condition_var = handler:match('<cond>var%.peek%(%"([^"]+)%"%) == true</cond>')
assert(condition_var == config.active_var,
   "the persistent handler must be conditional on the start marker")
assert(not handler:find('require%s*["\']tk["\']'),
   "events must use Naev's injected global tk API")

local starter = read_file("events/nomad_start.lua")
assert(starter:find("player%.shipAdd", 1)
   and starter:find("player%.shipSwap", 1),
   "the start event must replace the bootstrap hull with the carrier")
assert(not starter:find('outfitRm%(["\']all["\']%)'),
   "the start event must preserve the configured stock hull's loadout")
assert(starter:find("player%.outfitAdd", 1),
   "the start event must grant configurable bay controls to inventory")
assert(starter:find("outfitAdd%(outfit_name%) <= 0", 1),
   "starter controls that do not fit must be preserved in inventory")
assert(starter:find("naev%.eventStart%(config%.handler_event%)"),
   "the start event must establish the persistent handler before the first save")
local crewmates_start = assert(starter:find(
   "naev%.eventStart%(config%.crewmates_event%)"))
local handler_start = assert(starter:find(
   "naev%.eventStart%(config%.handler_event%)"))
assert(crewmates_start < handler_start,
   "the current pilot's Crewmates provider must exist before Nomad initializes")

local parked_spob = read_file("spob/nomad_parked_carrier.xml")
assert(parked_spob:find("<land/>", 1, true)
   and parked_spob:find("<refuel/>", 1, true)
   and parked_spob:find("<bar/>", 1, true)
   and parked_spob:find("<outfits/>", 1, true)
   and not parked_spob:find("<shipyard/>", 1, true),
   "the parked carrier must expose landing, mess hall, and equipment services")
assert(parked_spob:find("<uninhabited/>", 1, true)
   and parked_spob:find("<nomissionspawn/>", 1, true)
   and parked_spob:find("<tag>nonpc</tag>", 1, true),
   "the parked carrier must suppress faction traffic and generic NPCs")

local storage = read_file("ssys/nomad_carrier_storage.xml")
assert(storage:find('<ssys name="' .. config.parking.storage_system .. '">',
      1, true)
   and storage:find("<spob>" .. config.parking.spob .. "</spob>", 1, true)
   and storage:find("<jumps/>", 1, true),
   "the parked carrier must have a permanent unreachable save location")

local copied_carrier = io.open("ships/nomad_arx.xml", "r")
assert(not copied_carrier,
   "logical carrier capabilities must never require a copied hull definition")
assert(not handler:find("Nomad Command Bay", 1, true),
   "the command launch path must not depend on a physical outfit")
for _, name in ipairs({ "s", "m", "l", "xl" }) do
   local control = read_file("outfits/nomad_" .. name .. "_bay.xml")
   assert(control:find("<size>small</size>", 1, true),
      "logical bay size must not impose a large physical slot requirement")
end

print("ok - nomad scenario contract")
