package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local config = require "nomad.config"

local function read_file(path)
   local file = assert(io.open(path, "r"))
   local contents = file:read("*a")
   file:close()
   return contents
end

local scenario = read_file("start.toml")
assert(scenario:match('scenario_name%s*=%s*"([^"]+)"')
      == "Sea of Isolation"
   and scenario:match('ship_model%s*=%s*"([^"]+)"') == config.bootstrap.hull
   and scenario:match('event%s*=%s*"([^"]+)"') == "Nomad Start",
   "the scenario title, bootstrap hull, and initializer must remain explicit")

local starters = {}
for _, starter in ipairs(config.starter_carriers) do
   starters[starter.hull] = starter
end
local mule = starters.Mule
local arx = starters["Soromid Arx"]
local rhino = starters["Pirate Rhino"]
assert(mule.hull == "Mule" and arx.hull == "Soromid Arx"
   and rhino.hull == "Pirate Rhino" and #config.starter_carriers == 3,
   "all requested carrier starts must remain available")
assert(arx.chapter == "1",
   "the Arx start must begin in Chapter 1")
assert(#arx.roster == 3 and arx.roster[1].hull == "Soromid Copia"
   and arx.roster[2].hull == "Soromid Ira"
   and arx.roster[3].hull == "Soromid Reaver",
   "the Arx start must retain its Soromid fleet")
assert(rhino.credits == 750000 and rhino.start_system == "Qorel"
   and rhino.home_spob == "Qorellia"
   and rhino.command_shuttle == "Pirate Hyena"
   and rhino.reputation.faction == "Raven Clan"
   and rhino.reputation.faction_value == 20
   and rhino.reputation.value == -10
   and rhino.reputation.pirate_value == 20
   and rhino.reputation.factions[1] == "Empire"
   and rhino.reputation.factions[8] == "Traders Society"
   and #rhino.bays == 2 and rhino.bays[1] == "Medium Ship Bay"
   and rhino.bays[2] == "Medium Ship Bay",
   "the Rhino start must retain its Raven Clan pirate setup")

local vox = config.optional_starter_carriers[1]
assert(#config.optional_starter_carriers == 1
   and vox.hull == "Soromid Vox Carrier"
   and vox.choice == "Mutated Vox carrier"
   and vox.command_shuttle == "Soromid Brigand"
   and #vox.bays == 2
   and vox.bays[1] == "Large Ship Bay"
   and vox.bays[2] == "Large Ship Bay"
   and #vox.roster == 2
   and vox.roster[1].hull == "Soromid Odium"
   and vox.roster[1].size == 3
   and vox.roster[2].hull == "Soromid Marauder"
   and vox.roster[2].size == 2,
   "the optional Vox start must carry two complementary non-capital craft")
assert(#config.available_starter_carriers(false) == 3
   and #config.available_starter_carriers(true) == 4
   and config.command_shuttle_for(vox.hull) == "Soromid Brigand",
   "variant availability must only append the compatible Vox start")

local parked = read_file("spob/nomad_parked_carrier.xml")
assert(parked:find("<land/>", 1, true)
   and parked:find("<outfits/>", 1, true)
   and parked:find("<hide>0</hide>", 1, true)
   and parked:find("<space>nomad_invisible</space>", 1, true),
   "the parked carrier must provide services without appearing on local maps")

local storage = read_file("ssys/ngc_nomad.xml")
local ngc2601 = read_file("ssys/ngc2601.xml")
assert(config.parking.storage_system == "NGC-N0M4D"
   and storage:find('<ssys name="NGC-N0M4D">', 1, true)
   and storage:find('<pos x="-1709.736566" y="-389.2039425"/>', 1, true),
   "carrier storage must remain hidden between Zied and NGC-2601")
assert(storage:find('<jump target="NGC-2601">', 1, true)
   and storage:find("<hidden/>", 1, true)
   and ngc2601:find('<jump target="NGC-N0M4D">', 1, true)
   and ngc2601:find("<exitonly/>", 1, true),
   "carrier storage must have a hidden one-way path to NGC-2601")
assert(not storage:find("Nomad Storage Wormhole", 1, true)
   and parked:find('<pos x="100000" y="100000"/>', 1, true),
   "carrier storage must omit the old exit and keep its berth off-screen")

local wormhole_outfit = read_file(
   "outfits/unstable_wormhole_generator.xml")
local wormhole_alpha = read_file(
   "spob/nomad_unstable_wormhole_alpha.xml")
local wormhole_beta = read_file(
   "spob/nomad_unstable_wormhole_beta.xml")
local wormhole_alpha_lua = read_file(
   "spob/lua/nomad_unstable_wormhole_alpha.lua")
local wormhole_beta_lua = read_file(
   "spob/lua/nomad_unstable_wormhole_beta.lua")
assert(wormhole_outfit:find("<slot>utility</slot>", 1, true)
   and wormhole_outfit:find("<size>medium</size>", 1, true)
   and parked:find("<item>Unstable Wormhole Generator</item>", 1, true),
   "the optional generator must be a medium utility sold aboard the carrier")
assert(storage:find("<spob>" .. config.wormhole.source_spob
      .. "</spob>", 1, true)
   and storage:find("<spob>" .. config.wormhole.target_spob
      .. "</spob>", 1, true)
   and wormhole_alpha:find("<tag>wormhole</tag>", 1, true)
   and wormhole_beta:find("<tag>wormhole</tag>", 1, true),
   "both wormhole mouths must permanently exist in the storage system")
assert(wormhole_alpha:find('<pos x="700" y="200"/>', 1, true)
   and wormhole_beta:find('<pos x="700" y="-200"/>', 1, true),
   "stored wormhole mouths must retain functional initialization positions")
assert(not wormhole_alpha_lua:find("nomad_wormhole_enabled", 1, true)
   and wormhole_alpha_lua:find("wormhole.setup", 1, true)
   and wormhole_alpha_lua:find("nomad_wormhole_entering", 1, true)
   and wormhole_alpha_lua:find("wormhole_land(target_spob, subject)", 1, true)
   and wormhole_alpha_lua:find("shipvarPeek", 1, true)
   and not wormhole_beta_lua:find("nomad_wormhole_enabled", 1, true)
   and wormhole_beta_lua:find("wormhole.setup", 1, true)
   and wormhole_beta_lua:find("nomad_wormhole_entering", 1, true)
   and wormhole_beta_lua:find("wormhole_land(target_spob, subject)", 1, true)
   and wormhole_beta_lua:find("shipvarPeek", 1, true),
   "present apertures must use unconditional upstream traversal and report bay traversal")

local core = read_file("outfits/nomadic_operational_core.xml")
local shuttle = read_file("outfits/shuttle_bay.xml")
local small_bay = read_file("outfits/nomad_s_bay.xml")
local medium_bay = read_file("outfits/nomad_m_bay.xml")
local large_bay = read_file("outfits/nomad_l_bay.xml")
local xl_bay = read_file("outfits/nomad_xl_bay.xml")
assert(core:find("<size>medium</size>", 1, true)
   and not core:find("<mass_mod>", 1, true)
   and not core:find("<shield_mod>", 1, true)
   and not core:find("<ew_hide>", 1, true)
   and not core:find("<ew_stealth>", 1, true)
   and not core:find("<ew_stealth_min>", 1, true)
   and not core:find("<armour_regen>", 1, true)
   and shuttle:find("<size>medium</size>", 1, true)
   and shuttle:find("<mass>100</mass>", 1, true),
   "integrated systems must fit the Mule's native utility slots")
assert(small_bay:find("<size>small</size>", 1, true)
   and medium_bay:find("<size>medium</size>", 1, true)
   and large_bay:find("<size>large</size>", 1, true)
   and xl_bay:find("<size>large</size>", 1, true)
   and small_bay:find("<mass>100</mass>", 1, true)
   and medium_bay:find("<mass>150</mass>", 1, true)
   and large_bay:find("<mass>200</mass>", 1, true)
   and xl_bay:find("<mass>350</mass>", 1, true),
   "bay outfits must retain their native sizes and physical mass")

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
