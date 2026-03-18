local tech = data.raw.technology["circuit-network"]

local function has_unlock(t, recipe_name)
  if not (t and t.effects) then return false end
  for _, effect in ipairs(t.effects) do
    if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local function add_unlock(t, recipe_name)
  if t and t.effects and not has_unlock(t, recipe_name) then
    t.effects[#t.effects + 1] = {
      type = "unlock-recipe",
      recipe = recipe_name
    }
  end
end

add_unlock(tech, "widescreen-display-panel-2x1")
add_unlock(tech, "widescreen-display-panel-3x1")
add_unlock(tech, "widescreen-display-panel-4x1")