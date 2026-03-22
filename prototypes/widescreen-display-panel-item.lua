local util = require("__core__/lualib/util")

local MOD = "__WidescreenDisplayPanels__"

local function scale_ingredients(ingredients, multiplier)
  if not ingredients then return end
  for _, ing in pairs(ingredients) do
    if ing.amount ~= nil then
      ing.amount = ing.amount * multiplier
    elseif ing[2] ~= nil then
      ing[2] = ing[2] * multiplier
    end
  end
end

local function make_overlay_icons(base_item, overlay_filename)
  local vanilla_icon = base_item.icon
  local vanilla_icon_size = base_item.icon_size or 64
  local vanilla_icon_mipmaps = base_item.icon_mipmaps

  return {
    {
      icon = vanilla_icon,
      icon_size = vanilla_icon_size,
      icon_mipmaps = vanilla_icon_mipmaps
    },
    {
      icon = MOD .. "/graphics/icons/" .. overlay_filename,
      icon_size = 64,
      scale = 0.38,
      shift = { -4, -5 },
      floating = true
    }
  }
end

local PANEL_DEFS = {
  { name = "widescreen-display-panel-2x1", multiplier = 2, overlay_icon = "2x1.png", order_suffix = "-0[2x1]" },
  { name = "widescreen-display-panel-3x1", multiplier = 3, overlay_icon = "3x1.png", order_suffix = "-1[3x1]" },
  { name = "widescreen-display-panel-4x1", multiplier = 4, overlay_icon = "4x1.png", order_suffix = "-2[4x1]" },

  { name = "widescreen-display-panel-1x2", multiplier = 2, overlay_icon = "1x2.png", order_suffix = "-3[1x2]" },
  { name = "widescreen-display-panel-1x3", multiplier = 3, overlay_icon = "1x3.png", order_suffix = "-4[1x3]" },
  { name = "widescreen-display-panel-1x4", multiplier = 4, overlay_icon = "1x4.png", order_suffix = "-5[1x4]" },
}

local function make_item_and_recipe(def)
  local name = def.name
  local multiplier = def.multiplier
  local overlay_icon = def.overlay_icon

  local base_item = data.raw["item"]["display-panel"]
  local item = util.table.deepcopy(base_item)
  item.name = name
  item.place_result = name
  item.stack_size = 10

  item.order = (base_item.order or "z[display-panel]") .. (def.order_suffix or "")
  item.subgroup = base_item.subgroup

  item.icons = make_overlay_icons(base_item, overlay_icon, 0.7, { -8, -8 })
  item.icon = nil
  item.icon_size = nil
  item.icon_mipmaps = nil

  data:extend({ item })

  local base_recipe = data.raw["recipe"]["display-panel"]
  local recipe = util.table.deepcopy(base_recipe)
  recipe.name = name

  recipe.enabled = false
  if recipe.normal then recipe.normal.enabled = false end
  if recipe.expensive then recipe.expensive.enabled = false end

  recipe.result = nil
  recipe.result_count = nil
  recipe.results = {
    { type = "item", name = name, amount = 1 }
  }

  scale_ingredients(recipe.ingredients, multiplier)
  if recipe.normal then scale_ingredients(recipe.normal.ingredients, multiplier) end
  if recipe.expensive then scale_ingredients(recipe.expensive.ingredients, multiplier) end

  data:extend({ recipe })
end

for _, def in ipairs(PANEL_DEFS) do
  make_item_and_recipe(def)
end

local function add_recipe_unlocks_to_display_panel_tech()
  local unlock_tech = nil

  for _, tech in pairs(data.raw["technology"]) do
    if tech.effects then
      for _, effect in pairs(tech.effects) do
        if effect.type == "unlock-recipe" and effect.recipe == "display-panel" then
          unlock_tech = tech
          break
        end
      end
    end
    if unlock_tech then break end
  end

  if not unlock_tech then return end

  local already_present = {}
  for _, effect in pairs(unlock_tech.effects or {}) do
    if effect.type == "unlock-recipe" and effect.recipe then
      already_present[effect.recipe] = true
    end
  end

  for _, def in ipairs(PANEL_DEFS) do
    if not already_present[def.name] then
      table.insert(unlock_tech.effects, {
        type = "unlock-recipe",
        recipe = def.name
      })
    end
  end
end

add_recipe_unlocks_to_display_panel_tech()