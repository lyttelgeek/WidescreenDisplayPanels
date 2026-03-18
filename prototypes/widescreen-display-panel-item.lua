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
  
  local icons = nil

  if base_item.icons then
    icons = util.table.deepcopy(base_item.icons)
  else
    icons = {
      {
        icon = base_item.icon,
        icon_size = base_item.icon_size or 64,
        icon_mipmaps = base_item.icon_mipmaps
      }
    }
  end

  table.insert(icons, {
    icon = MOD .. "/graphics/icons/" .. overlay_filename,
    icon_size = 64
  })

  return icons
end

local function make_item_and_recipe(name, width_multiplier, overlay_icon)
  -- Item
  local base_item = data.raw["item"]["display-panel"]
  local item = util.table.deepcopy(base_item)
  item.name = name
  item.place_result = name
  item.stack_size = 50

  item.icons = make_overlay_icons(base_item, overlay_icon)
  item.icon = nil
  item.icon_size = nil
  item.icon_mipmaps = nil

  data:extend({ item })

  -- Recipe (copy vanilla, scale ingredients, use results for quality)
  local base_recipe = data.raw["recipe"]["display-panel"]
  local recipe = util.table.deepcopy(base_recipe)
  recipe.name = name

  -- Ensure recipe is locked behind technology
  recipe.enabled = false
  if recipe.normal then recipe.normal.enabled = false end
  if recipe.expensive then recipe.expensive.enabled = false end

  -- Use results format
  recipe.result = nil
  recipe.result_count = nil
  recipe.results = {
    { type = "item", name = name, amount = 1 }
  }

  scale_ingredients(recipe.ingredients, width_multiplier)
  if recipe.normal then scale_ingredients(recipe.normal.ingredients, width_multiplier) end
  if recipe.expensive then scale_ingredients(recipe.expensive.ingredients, width_multiplier) end

  data:extend({ recipe })
end

make_item_and_recipe("widescreen-display-panel-2x1", 2, "2x1.png")
make_item_and_recipe("widescreen-display-panel-3x1", 3, "3x1.png")
make_item_and_recipe("widescreen-display-panel-4x1", 4, "4x1.png")