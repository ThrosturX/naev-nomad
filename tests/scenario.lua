package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local config = require "nomad.config"

local function read_file(path)
   local file = assert(io.open(path, "r"))
   local contents = file:read("*a")
   file:close()
   return contents
end

local scenario = read_file("start.toml")
assert(scenario:match('ship_model%s*=%s*"([^"]+)"') == config.bootstrap.hull
   and scenario:match('event%s*=%s*"([^"]+)"') == "Nomad Start",
   "the scenario must use its bootstrap hull and Nomad initializer")

local mule = config.starter_carriers[1]
local arx = config.starter_carriers[2]
local raven = config.starter_carriers[3]
assert(mule.hull == "Mule" and arx.hull == "Soromid Arx"
   and raven.hull == "Raven Starbridge",
   "all three requested carrier starts must remain available")
assert(arx.chapter == "1" and mule.chapter == nil and raven.chapter == nil,
   "only the Arx start may begin in Chapter 1")
assert(#arx.roster == 3 and arx.roster[1].hull == "Soromid Copia"
   and arx.roster[2].hull == "Soromid Ira"
   and arx.roster[3].hull == "Soromid Reaver",
   "the Arx start must retain its Soromid fleet")
assert(raven.start_system == "Qorel" and raven.home_spob == "Qorellia"
   and raven.reputation.faction == "Raven Clan",
   "the Raven start must retain its regional setup")

local parked = read_file("spob/nomad_parked_carrier.xml")
assert(parked:find("<land/>", 1, true)
   and parked:find("<outfits/>", 1, true)
   and parked:find("<space>nomad_invisible</space>", 1, true),
   "the parked carrier must provide services with its transparent marker")

local storage = read_file("ssys/ngc_nomad.xml")
local ngc2601 = read_file("ssys/ngc2601.xml")
local storage_wormhole = read_file("spob/nomad_storage_wormhole.xml")
local storage_wormhole_lua = read_file(
   "spob/lua/nomad_storage_wormhole.lua")
assert(config.parking.storage_system == "NGC-N0M4D"
   and storage:find('<ssys name="NGC-N0M4D">', 1, true)
   and storage:find('<pos x="-1709.736566" y="-389.2039425"/>', 1, true),
   "carrier storage must remain hidden between Zied and NGC-2601")
assert(storage:find('<jump target="NGC-2601">', 1, true)
   and storage:find("<hidden/>", 1, true)
   and ngc2601:find('<jump target="NGC-N0M4D">', 1, true)
   and ngc2601:find("<exitonly/>", 1, true),
   "carrier storage must have a hidden one-way path to NGC-2601")
assert(storage:find("<spob>Nomad Storage Wormhole</spob>", 1, true)
   and storage_wormhole:find("<tag>wormhole</tag>", 1, true)
   and storage_wormhole_lua:find("spob.getAll()", 1, true)
   and storage_wormhole_lua:find("candidate:tags().wormhole", 1, true),
   "carrier storage must retain its random wormhole exit")

local core = read_file("outfits/nomadic_operational_core.xml")
local shuttle = read_file("outfits/shuttle_bay.xml")
local small_bay = read_file("outfits/nomad_s_bay.xml")
local medium_bay = read_file("outfits/nomad_m_bay.xml")
local large_bay = read_file("outfits/nomad_l_bay.xml")
local xl_bay = read_file("outfits/nomad_xl_bay.xml")
assert(core:find("<size>large</size>", 1, true)
   and core:find("<mass_mod>100</mass_mod>", 1, true)
   and core:find("<shield_mod>200</shield_mod>", 1, true)
   and shuttle:find("<size>medium</size>", 1, true),
   "the physical integrated systems must retain their slot requirements")
assert(small_bay:find("<size>small</size>", 1, true)
   and medium_bay:find("<size>medium</size>", 1, true)
   and large_bay:find("<size>large</size>", 1, true)
   and xl_bay:find("<size>large</size>", 1, true),
   "bay outfits must retain their native fighter-bay size requirements")

package.preload.cinema = function()
   return { on = function() end, off = function() end }
end
package.preload.intro = function()
   return { init = function() end, text = function() end, run = function() end }
end
_ = function(text) return text end
local applied, known = {}, 0
diff = {
   isApplied = function() return false end,
   apply = function(name) applied[name] = true end,
   remove = function(name) applied[name] = nil end,
}
player = {
   chapterSet = function(chapter) applied.chapter = chapter end,
   canDiscover = function(value) applied.discovery = value end,
   outfitAdd = function() end,
}
spob = { getS = function()
   return nil, { setKnown = function() known = known + 1 end }
end }
var = {
   peek = function() return "1" end,
   pop = function() end,
   push = function() end,
}
jump = { setKnown = function() end }
music = { choose = function() end }
evt = { finish = function(value) applied.finished = value end }
dofile("events/start.lua")
create()
assert(applied.chapter == "1" and applied.discovery == true
   and applied.hypergates_3 == true and not applied["Chapter 0"]
   and known == 5 and applied.finished == true,
   "the Arx opening must initialize final Chapter 1 state without Chapter 0")

print("ok - nomad scenario contract")
