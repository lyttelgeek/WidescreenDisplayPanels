local util = require("__core__/lualib/util")

local MOD = "__WidescreenDisplayPanels__"

-- Uniform remnant scale across the family (intended design choice)
local REMNANT_SCALE = 0.49

-- Base remnant specs (only what differs per size)
local REMNANTS = {
  {
    entity_name = "widescreen-display-panel-2x1",
    remnant = { filename = "2x1-remnants.png", w = 137, h = 76 },
    shadow  = { filename = "2x1-shadow.png",   w = 128, h = 42 },
    remnant_shift = { x = 0, y = -2 },
    shadow_offset = { x = 6, y = 8 },
  },
  {
    entity_name = "widescreen-display-panel-3x1",
    remnant = { filename = "3x1-remnants.png", w = 172, h = 83 },
    shadow  = { filename = "3x1-shadow.png",   w = 171, h = 42 },
    remnant_shift = { x = 0, y = 0 },
    shadow_offset = { x = 8, y = 5 },
  },
  {
    entity_name = "widescreen-display-panel-4x1",
    remnant = { filename = "4x1-remnants.png", w = 205, h = 80 },
    shadow  = { filename = "4x1-shadow.png",   w = 208, h = 42 },
    remnant_shift = { x = 0, y = 0 },
    shadow_offset = { x = 8, y = 6 },
  },
  {
    entity_name = "widescreen-display-panel-1x2",
    remnant = { filename = "1x2-remnants.png", w = 85, h = 159 },
    shadow  = { filename = "1x2-remnants-shadow.png",   w = 86, h = 160 },
    remnant_shift = { x = 0, y = 0 },
    shadow_offset = { x = 2, y = 0 },
  },
  {
    entity_name = "widescreen-display-panel-1x3",
    remnant = { filename = "1x3-remnants.png", w = 84, h = 199 },
    shadow  = { filename = "1x3-remnants-shadow.png",   w = 89, h = 199 },
    remnant_shift = { x = 0, y = 0 },
    shadow_offset = { x = 2, y = 0 },
  },
  {
    entity_name = "widescreen-display-panel-1x4",
    remnant = { filename = "1x4-remnants.png", w = 84, h = 270 },
    shadow  = { filename = "1x4-remnants-shadow.png",   w = 87, h = 270 },
    remnant_shift = { x = 0, y = 0 },
    shadow_offset = { x = 2, y = 0 },
  },
}

local function make_remnant_corpse(spec)
  local name = spec.entity_name .. "-remnants"

  local vanilla_entity = data.raw["display-panel"]["display-panel"]
  local vanilla_corpse = data.raw["corpse"][vanilla_entity.corpse]

  local corpse = util.table.deepcopy(vanilla_corpse)
  corpse.name = name

  local rem_shift = util.by_pixel(spec.remnant_shift.x, spec.remnant_shift.y)
  local sh_shift = util.by_pixel(
    spec.remnant_shift.x + spec.shadow_offset.x,
    spec.remnant_shift.y + spec.shadow_offset.y
  )

  corpse.animation = {
    layers = {
      {
        filename = MOD .. "/graphics/entity/widescreen-display-panel/" .. spec.remnant.filename,
        width = spec.remnant.w,
        height = spec.remnant.h,
        frame_count = 1,
        direction_count = 1,
        shift = rem_shift,
        scale = REMNANT_SCALE,
      },
      {
        filename = MOD .. "/graphics/entity/widescreen-display-panel/" .. spec.shadow.filename,
        width = spec.shadow.w,
        height = spec.shadow.h,
        frame_count = 1,
        direction_count = 1,
        shift = sh_shift,
        scale = REMNANT_SCALE,
        draw_as_shadow = true,
      }
    }
  }

  return corpse
end

local out = {}
for _, spec in ipairs(REMNANTS) do
  table.insert(out, make_remnant_corpse(spec))
end
data:extend(out)
