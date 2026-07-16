local config = require "nomad.config"

local parking = {}

local function xml_escape(value)
   return tostring(value)
      :gsub("&", "&amp;")
      :gsub("<", "&lt;")
      :gsub(">", "&gt;")
      :gsub('"', "&quot;")
      :gsub("'", "&apos;")
end

function parking.record(system_name, x, y, direction, diff_name, carrier_name)
   return {
      system = tostring(system_name),
      x = assert(tonumber(x), "parking x coordinate is required"),
      y = assert(tonumber(y), "parking y coordinate is required"),
      direction = tonumber(direction) or 0,
      diff = assert(diff_name, "parking diff name is required"),
      carrier = assert(carrier_name, "parked carrier name is required"),
   }
end

function parking.validate(aboard_carrier, landed, shield, shield_capacity)
   if not aboard_carrier then
      return false, "you must be aboard the Nomad carrier"
   end
   if landed then return false, "the carrier is already parked" end
   if type(shield) ~= "number" then
      return false, "carrier shield status is unavailable"
   end
   if shield_capacity == 0 then return true end
   if shield < config.parking.minimum_shield then
      return false, string.format("carrier shields must be at least %d%%",
         config.parking.minimum_shield)
   end
   return true
end

function parking.diff_xml(record)
   return string.format([[
<unidiff name="%s">
 <system name="%s">
  <spob_remove>%s</spob_remove>
 </system>
 <system name="%s">
  <spob_add>%s</spob_add>
 </system>
 <spob name="%s">
  <pos_x>%.17g</pos_x>
  <pos_y>%.17g</pos_y>
 </spob>
</unidiff>]],
      xml_escape(record.diff),
      xml_escape(config.parking.storage_system),
      xml_escape(config.parking.spob),
      xml_escape(record.system),
      xml_escape(config.parking.spob),
      xml_escape(config.parking.spob),
      record.x,
      record.y)
end

return parking
