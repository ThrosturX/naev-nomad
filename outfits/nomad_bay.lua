local function cache()
   local shared = naev.cache()
   shared.nomad_bay_tooltips = shared.nomad_bay_tooltips or {}
   return shared.nomad_bay_tooltips
end

local function is_player(subject)
   return subject == player.pilot()
end

local function desired_state(id)
   local shared = naev.cache()
   shared.nomad_bay_states = shared.nomad_bay_states or {}
   return shared.nomad_bay_states[id] == true
end

local function cooldown(id)
   local shared = naev.cache()
   shared.nomad_bay_cooldowns = shared.nomad_bay_cooldowns or {}
   return shared.nomad_bay_cooldowns[id]
end

local function apply_state(pilot_outfit)
   local id = pilot_outfit:id()
   local cooling = cooldown(id)
   local shared = naev.cache()
   shared.nomad_bay_rendered = shared.nomad_bay_rendered or {}
   local mode
   if cooling and cooling.remaining > 0 then
      mode = "cooldown"
      if shared.nomad_bay_rendered[id] ~= mode then
         pilot_outfit:state(mode)
         shared.nomad_bay_rendered[id] = mode
      end
      pilot_outfit:progress(cooling.remaining / cooling.total)
   else
      mode = desired_state(id) and "on" or "off"
      if shared.nomad_bay_rendered[id] ~= mode then
         pilot_outfit:state(mode)
         shared.nomad_bay_rendered[id] = mode
      end
   end
end

function descextra(subject, _outfit, pilot_outfit)
   if not is_player(subject) or not pilot_outfit then return nil end
   return cache()[pilot_outfit:id()]
end

function init(subject, pilot_outfit)
   if not is_player(subject) then return end
   local shared = naev.cache()
   shared.nomad_bay_states = shared.nomad_bay_states or {}
   shared.nomad_bay_rendered = shared.nomad_bay_rendered or {}
   shared.nomad_bay_states[pilot_outfit:id()] = false
   shared.nomad_bay_rendered[pilot_outfit:id()] = "off"
   pilot_outfit:state("off")
end

function update(subject, pilot_outfit)
   if not is_player(subject) then return end
   apply_state(pilot_outfit)
end

function onremove(subject, pilot_outfit)
   if not is_player(subject) then return end
   local assignments = naev.cache().nomad_bay_assignments or {}
   local assigned = assignments[pilot_outfit:id()]
   if assigned then
      local outfit_name = pilot_outfit:outfit():nameRaw()
      naev.trigger("nomad_occupied_bay_removed", {
         id = pilot_outfit:id(),
         outfit = outfit_name,
         ship = assigned,
         inventory = player.outfitNum(outfit_name),
      })
   end
   naev.trigger("nomad_bay_configuration_changed", {
      id = pilot_outfit:id(),
   })
end

function ontoggle(subject, pilot_outfit, on)
   if not is_player(subject) then return false end
   if on and cooldown(pilot_outfit:id()) then
      apply_state(pilot_outfit)
      return false
   end
   local shared = naev.cache()
   shared.nomad_bay_states = shared.nomad_bay_states or {}
   shared.nomad_bay_rendered = shared.nomad_bay_rendered or {}
   shared.nomad_bay_states[pilot_outfit:id()] = on == true
   local mode = on and "on" or "off"
   pilot_outfit:state(mode)
   shared.nomad_bay_rendered[pilot_outfit:id()] = mode
   naev.trigger("nomad_bay_activated", {
      outfit = pilot_outfit:outfit():nameRaw(),
      id = pilot_outfit:id(),
      on = on == true,
   })
   return true
end
