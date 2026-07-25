package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local available = {}
ship = {
   exists = function(name) return available[name] end,
}

local optional_variants = require "nomad.optional_variants"
assert(not optional_variants.has_ship("Soromid Vox Carrier"),
   "missing variant hulls must remain optional")
available["Soromid Vox Carrier"] = {}
assert(optional_variants.has_ship("Soromid Vox Carrier"),
   "an installed variant hull must enable its compatible start")
ship.exists = nil
assert(not optional_variants.has_ship("Soromid Vox Carrier"),
   "older Naev versions without ship.exists must degrade safely")

print("ok - optional variant content")
