package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local config = require "nomad.config"
local wormhole = require "nomad.wormhole"

local function fake_system(name, distance, tags)
   return {
      nameRaw = function() return name end,
      tags = function() return tags or {} end,
      jumpDist = function(_self, candidate)
         return candidate.distance
      end,
      distance = distance,
   }
end

local source = fake_system("Origin", 0)
local near = fake_system("Near", 1)
local reasonable = fake_system("Reasonable", 3)
local distant = fake_system("Distant", 4)
local restricted = fake_system("Restricted", 2, { restricted = true })
local spoiler = fake_system("Spoiler", 2, { spoiler = true })
local storage = fake_system(config.wormhole.storage_system, 2)
local candidates = wormhole.destination_candidates(source, {
   distant, source, restricted, reasonable, storage, near, spoiler,
})
assert(#candidates == 2 and candidates[1] == near
   and candidates[2] == reasonable,
   "wormhole targets must be ordinary systems one to three jumps away")

local xml = wormhole.diff_xml(
   "Nomad Wormhole 7", 'A&B "Source"', "Target's Reach",
   12.5, -44, 900, 301.25)
assert(xml:find('name="Nomad Wormhole 7"', 1, true)
   and xml:find('name="A&amp;B &quot;Source&quot;"', 1, true)
   and xml:find('name="Target&apos;s Reach"', 1, true)
   and xml:find("<spob_remove>" .. config.wormhole.source_spob
      .. "</spob_remove>", 1, true)
   and xml:find("<spob_remove>" .. config.wormhole.target_spob
      .. "</spob_remove>", 1, true)
   and xml:find("<pos_x>12.5</pos_x>", 1, true)
   and xml:find("<pos_y>301.25</pos_y>", 1, true),
   "the dynamic pair diff must relocate both escaped endpoints exactly")
local remove_alpha = assert(xml:find(
   "<spob_remove>" .. config.wormhole.source_spob, 1, true))
local add_alpha = assert(xml:find(
   "<spob_add>" .. config.wormhole.source_spob, 1, true))
local remove_beta = assert(xml:find(
   "<spob_remove>" .. config.wormhole.target_spob, 1, true))
local add_beta = assert(xml:find(
   "<spob_add>" .. config.wormhole.target_spob, 1, true))
local position_alpha = assert(xml:find("<pos_x>12.5</pos_x>", 1, true))
local position_beta = assert(xml:find("<pos_x>900</pos_x>", 1, true))
assert(position_alpha < remove_alpha and position_beta < remove_alpha
   and remove_alpha < add_alpha and add_alpha < remove_beta
   and remove_beta < add_beta,
   "positions must be final and one endpoint placed before either loads")

print("ok - nomad unstable wormhole")
