local fitting = {}

function fitting.calculate(base, outfits)
   local mass = base.mass or 0
   local engine_limit = base.engine_limit or 0
   local energy_regen = base.energy_regen or 0
   local energy_drain = base.energy_drain or 0

   for _index, stats in ipairs(outfits or {}) do
      mass = mass + (stats.mass or 0)
      engine_limit = engine_limit + (stats.engine_limit or 0)
      energy_regen = energy_regen + (stats.energy_regen or 0)
      energy_drain = energy_drain + (stats.energy_drain or 0)
   end

   mass = mass * (base.mass_mod or 1)
   engine_limit = engine_limit * (base.engine_limit_mod or 1)
   energy_regen = energy_regen * (base.energy_regen_mod or 1)

   return {
      mass = mass,
      engine_limit = engine_limit,
      energy_regen = energy_regen - energy_drain,
   }
end

function fitting.validate(base, outfits)
   local totals = fitting.calculate(base, outfits)
   if totals.mass > totals.engine_limit then
      return false, "fitted mass exceeds engine limit", totals
   end
   if totals.energy_regen <= 0 then
      return false, "energy regeneration is not positive", totals
   end
   return true, nil, totals
end

return fitting
