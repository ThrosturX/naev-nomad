package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local config = require "nomad.config"
local parking = require "nomad.parking"

local ok, reason = parking.validate(true, false, 89.999)
assert(not ok and reason:find("90%%"),
   "parking must reject shields below the configured threshold")
assert(parking.validate(true, false, 90),
   "parking must accept shields exactly at the configured threshold")
assert(not parking.validate(false, false, 100),
   "only the tagged carrier may be parked")
assert(not parking.validate(true, true, 100),
   "an already landed carrier cannot be parked again")

local record = parking.record(
   'A&B "System"', 123.5, -987.25, 1.75, 'Nomad Park 1&2')
assert(record.system == 'A&B "System"' and record.x == 123.5
   and record.y == -987.25 and record.direction == 1.75
   and record.diff == 'Nomad Park 1&2',
   "parking records must contain only reload-safe scalar data")
local xml = parking.diff_xml(record)
assert(xml:find('name="Nomad Park 1&amp;2"', 1, true)
   and xml:find('name="' .. config.parking.storage_system .. '"', 1, true)
   and xml:find("<spob_remove>" .. config.parking.spob .. "</spob_remove>",
      1, true)
   and xml:find('name="A&amp;B &quot;System&quot;"', 1, true)
   and xml:find("<spob_add>" .. config.parking.spob .. "</spob_add>", 1, true)
   and xml:find("<pos_x>123.5</pos_x>", 1, true)
   and xml:find("<pos_y>-987.25</pos_y>", 1, true),
   "dynamic parking diffs must escape names and retain exact coordinates")

print("ok - nomad carrier parking")
