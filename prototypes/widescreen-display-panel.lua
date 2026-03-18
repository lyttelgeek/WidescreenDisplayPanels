local util = require("__core__/lualib/util")

local MOD = "__WidescreenDisplayPanels__"

local function box_for_tiles(w, h, inset)
  inset = inset or 0.05
  local half_w = w / 2
  local half_h = h / 2
  return {
    { -half_w + inset, -half_h + inset },
    {  half_w - inset,  half_h - inset }
  }
end

local function px(x, y)
  return util.by_pixel(x, y)
end

local function add_shift(vec, shift)
  return { vec[1] + shift[1], vec[2] + shift[2] }
end

local function shift_connector_points_rg(points, red_shift, green_shift)
  if not points then return end

  if points.wire then
    if points.wire.red then
      points.wire.red = add_shift(points.wire.red, red_shift)
    end
    if points.wire.green then
      points.wire.green = add_shift(points.wire.green, green_shift)
    end
  end

  if points.shadow then
    if points.shadow.red then
      points.shadow.red = add_shift(points.shadow.red, red_shift)
    end
    if points.shadow.green then
      points.shadow.green = add_shift(points.shadow.green, green_shift)
    end
  end
end

local function try_shift_native_connector_north_only(base, red_shift_px, green_shift_px)
  local red_shift = px(red_shift_px[1], red_shift_px[2])
  local green_shift = px(green_shift_px[1], green_shift_px[2])

  if not base.circuit_connector then return end


  local north = base.circuit_connector[1]
  if north and north.points then
    shift_connector_points_rg(north.points, red_shift, green_shift)
  end
end

-- LOCKED family constants
local MAIN_SCALE = 0.515
local MAIN_SHIFT_PX = 0
local MAIN_SHIFT_PY = -3

-- LOCKED native connector relocation:
local CONNECTOR_SHIFT_PX = {
  ["widescreen-display-panel-2x1"] = {
    red   = { -16, 18 },
    green = { -41, 4 },
  },
  ["widescreen-display-panel-3x1"] = {
    red   = { -27, 18 },
    green = { -52, 4 },
  },
  ["widescreen-display-panel-4x1"] = {
    red   = { -35, 18 },
    green = { -60, 4 },
  },
}

local PANELS = {
  {
    name = "widescreen-display-panel-2x1",
    tiles_w = 2,
    tiles_h = 1,
    main   = { filename = "2x1.png",        w = 122, h = 74 },
    shadow = { filename = "2x1-shadow.png", w = 128, h = 42 },
    shadow_offset = { x = 6, y = 8 },
  },
  {
    name = "widescreen-display-panel-3x1",
    tiles_w = 3,
    tiles_h = 1,
    main   = { filename = "3x1.png",        w = 163, h = 75 },
    shadow = { filename = "3x1-shadow.png", w = 171, h = 42 },
    shadow_offset = { x = 8, y = 8 },
  },
  {
    name = "widescreen-display-panel-4x1",
    tiles_w = 4,
    tiles_h = 1,
    main   = { filename = "4x1.png",        w = 196, h = 72 },
    shadow = { filename = "4x1-shadow.png", w = 208, h = 42 },
    shadow_offset = { x = 8, y = 8 },
  },
}

local function make_panel_entity(spec)
  local base = util.table.deepcopy(data.raw["display-panel"]["display-panel"])
  if not base then
    error("WidescreenDisplayPanels: vanilla display-panel prototype not found")
  end

  base.name = spec.name
  base.minable.result = spec.name

  base.corpse = spec.name .. "-remnants"
  base.remains_when_mined = spec.name .. "-remnants"

  base.collision_box = box_for_tiles(spec.tiles_w, spec.tiles_h or 1, 0.05)
  base.selection_box = box_for_tiles(spec.tiles_w, spec.tiles_h or 1, 0.00)

  -- Disable rotation entirely
  base.rotatable = false

  -- Permanently keep the native connector enabled
  if base.circuit_wire_max_distance == nil or base.circuit_wire_max_distance <= 0 then
    base.circuit_wire_max_distance = 9
  end

  -- Move native connector
  local conn_shift = CONNECTOR_SHIFT_PX[spec.name]
  if conn_shift then
    try_shift_native_connector_north_only(base, conn_shift.red, conn_shift.green)
  end

  local main_shift = util.by_pixel(MAIN_SHIFT_PX, MAIN_SHIFT_PY)
  local shadow_shift = util.by_pixel(
    MAIN_SHIFT_PX + spec.shadow_offset.x,
    MAIN_SHIFT_PY + spec.shadow_offset.y
  )

  local function make_dir()
    return {
      layers = {
        {
          filename = MOD .. "/graphics/entity/widescreen-display-panel/" .. spec.main.filename,
          width = spec.main.w,
          height = spec.main.h,
          shift = main_shift,
          scale = MAIN_SCALE,
          priority = "high",
        },
        {
          filename = MOD .. "/graphics/entity/widescreen-display-panel/" .. spec.shadow.filename,
          width = spec.shadow.w,
          height = spec.shadow.h,
          shift = shadow_shift,
          scale = MAIN_SCALE,
          draw_as_shadow = true,
          priority = "high",
        }
      }
    }
  end

  local d = make_dir()
  base.sprites = { north = d, east = d, south = d, west = d }

  return base
end

local out = {}
for _, spec in ipairs(PANELS) do
  table.insert(out, make_panel_entity(spec))
end
data:extend(out)