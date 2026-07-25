local optional_variants = {}

function optional_variants.has_ship(name)
   return type(ship.exists) == "function" and ship.exists(name) ~= nil
end

return optional_variants
