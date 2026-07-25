local bioskills = require "bioship.skills"

local command_shuttle = {}

local function is_plain(value, seen)
   local kind = type(value)
   if kind == "nil" or kind == "boolean"
      or kind == "number" or kind == "string" then
      return true
   end
   if kind ~= "table" or seen[value] then return false end
   seen[value] = true
   for key, item in pairs(value) do
      local key_kind = type(key)
      if (key_kind ~= "number" and key_kind ~= "string")
         or not is_plain(item, seen) then
         seen[value] = nil
         return false
      end
   end
   seen[value] = nil
   return true
end

local function persistent_shipvars(extra)
   local names = {
      bioship = true,
      bioship_init = true,
      bioshipexp = true,
      biostage = true,
   }
   if bioskills.set then
      for _tree_name, tree in pairs(bioskills.set) do
         for skill_name in pairs(tree) do
            names["bio_" .. skill_name] = true
         end
      end
   end
   for _extra_index, name in ipairs(extra or {}) do
      names[name] = true
   end
   local result = {}
   for name in pairs(names) do result[#result + 1] = name end
   table.sort(result)
   return result
end

function command_shuttle.ensure(saved, default_hull)
   if type(saved) ~= "table" then saved = {} end
   if type(saved.hull) ~= "string" or saved.hull == "" then
      saved.hull = default_hull
   end
   if saved.virtual_state ~= nil
      and not is_plain(saved.virtual_state, {}) then
      saved.virtual_state = nil
   end
   return saved
end

function command_shuttle.profile(base, saved)
   local result = {}
   for key, value in pairs(base or {}) do result[key] = value end
   result.persist_virtual_state = true
   result.shipvars = persistent_shipvars(result.shipvars)
   result.virtual_state = type(saved) == "table"
      and saved.virtual_state or nil
   return result
end

function command_shuttle.record(saved, payload)
   if type(payload) ~= "table" then return saved end
   saved = command_shuttle.ensure(saved, payload.hull)
   if type(payload.hull) == "string" and payload.hull ~= "" then
      saved.hull = payload.hull
   end
   if type(payload.virtual_state) == "table"
      and is_plain(payload.virtual_state, {}) then
      saved.virtual_state = payload.virtual_state
   end
   return saved
end

return command_shuttle
