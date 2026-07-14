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
assert(starting_hull == config.carrier.hull,
   "scenario and runtime carrier hulls must remain synchronized")
assert(starting_event == "Nomad Start",
   "the scenario must use the event that marks new Nomad pilots")

local handler = read_file("events/nomad.lua")
local condition_var = handler:match('<cond>var%.peek%(%"([^"]+)%"%) == true</cond>')
assert(condition_var == config.active_var,
   "the persistent handler must be conditional on the start marker")
assert(not handler:find('require%s*["\']tk["\']'),
   "events must use Naev's injected global tk API")

local starter = read_file("events/nomad_start.lua")
assert(not starter:find('eventStart%(["\']Nomad Fleet Handler["\']%)'),
   "the start event must let Naev's subsequent load trigger start the handler")

print("ok - nomad scenario contract")
