local config = require "nomad.config"

local wormhole = {}

local function xml_escape(value)
   return tostring(value)
      :gsub("&", "&amp;")
      :gsub("<", "&lt;")
      :gsub(">", "&gt;")
      :gsub('"', "&quot;")
      :gsub("'", "&apos;")
end

function wormhole.destination_candidates(source, systems)
   local candidates = {}
   for _system_index, candidate in ipairs(systems or {}) do
      local tags = candidate:tags() or {}
      local name = candidate:nameRaw()
      if candidate ~= source and name ~= config.wormhole.storage_system
         and not tags.restricted and not tags.spoiler then
         local ok, distance = pcall(source.jumpDist, source, candidate, false)
         distance = ok and tonumber(distance) or nil
         if distance and distance >= config.wormhole.minimum_jumps
            and distance <= config.wormhole.maximum_jumps then
            candidates[#candidates + 1] = candidate
         end
      end
   end
   table.sort(candidates, function(left, right)
      return left:nameRaw() < right:nameRaw()
   end)
   return candidates
end

function wormhole.diff_xml(diff_name, source_system, target_system,
      source_x, source_y, target_x, target_y)
   local settings = config.wormhole
   return string.format([[
<unidiff name="%s">
 <spob name="%s">
  <pos_x>%.17g</pos_x>
  <pos_y>%.17g</pos_y>
 </spob>
 <spob name="%s">
  <pos_x>%.17g</pos_x>
  <pos_y>%.17g</pos_y>
 </spob>
 <system name="%s">
  <spob_remove>%s</spob_remove>
 </system>
 <system name="%s">
  <spob_add>%s</spob_add>
 </system>
 <system name="%s">
  <spob_remove>%s</spob_remove>
 </system>
 <system name="%s">
  <spob_add>%s</spob_add>
 </system>
</unidiff>]],
      xml_escape(diff_name),
      xml_escape(settings.source_spob),
      source_x, source_y,
      xml_escape(settings.target_spob),
      target_x, target_y,
      xml_escape(settings.storage_system),
      xml_escape(settings.source_spob),
      xml_escape(source_system),
      xml_escape(settings.source_spob),
      xml_escape(settings.storage_system),
      xml_escape(settings.target_spob),
      xml_escape(target_system),
      xml_escape(settings.target_spob))
end

return wormhole
