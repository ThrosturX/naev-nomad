--[[
<?xml version='1.0' encoding='utf8'?>
<event name="start_event">
 <location>none</location>
</event>
--]]

local cinema = require "cinema"
local config = require "nomad.config"
local intro = require "intro"

local chapter_one_hypergates = {
   "Hypergate Gamma Polaris",
   "Hypergate Ruadan",
   "Hypergate Feye",
   "Hypergate Kiwi",
   "Hypergate Dvaer",
}

local function initialize_chapter(chapter)
   if chapter ~= "1" then
      diff.apply("Chapter 0")
      return
   end
   player.chapterSet("1")
   player.canDiscover(true)
   if diff.isApplied("Chapter 0") then diff.remove("Chapter 0") end
   for _, name in ipairs({ "hypergates_1", "hypergates_2" }) do
      if diff.isApplied(name) then diff.remove(name) end
   end
   if not diff.isApplied("hypergates_3") then diff.apply("hypergates_3") end
   for _, name in ipairs(chapter_one_hypergates) do
      local _gate, gate_system = spob.getS(name)
      if gate_system then gate_system:setKnown(true) end
   end
end

function create()
   local chapter = var.peek(config.start_chapter_var) or "0"
   var.pop(config.start_chapter_var)
   initialize_chapter(chapter)

   jump.setKnown("Delta Polaris", "Jade")
   var.push("autonav_reset_shield", 1)
   var.push("autonav_reset_dist", 3e3)
   var.push("autonav_compr_speed", 5e3)
   var.push("autonav_compr_max", 50)
   for _, gui in ipairs({
      "GUI - Brushed", "GUI - Slim", "GUI - Slimv2", "GUI - Legacy",
   }) do player.outfitAdd(gui) end

   cinema.on()
   music.choose("intro")
   intro.init()
   intro.text(_("Home is not a world. It is the carrier beneath your feet and the ships secured in its bays."))
   intro.text()
   intro.text(_("Ports offer supplies, rumours, and work, but your fleet must always return to the wandering home that carries it."))
   intro.text()
   intro.text(_("You are a Nomad. Take your home among the stars."))
   intro.run()
   music.choose("ambient")
   cinema.off()
   evt.finish(true)
end
