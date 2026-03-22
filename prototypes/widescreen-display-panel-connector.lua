local util = require("__core__/lualib/util")

local function px(x, y)
  return util.by_pixel(x, y)
end

local function add_shift(vec, shift)
  return { vec[1] + shift[1], vec[2] + shift[2] }
end

local function offset_conn_points(points, red_shift, green_shift)
  local shadow_extra = px(-7, 0)

  for _, p in pairs(points) do
    if p.wire then
      if p.wire.red then
        p.wire.red = add_shift(p.wire.red, red_shift)
      end
      if p.wire.green then
        p.wire.green = add_shift(p.wire.green, green_shift)
      end
    end

    if p.shadow then
      if p.shadow.red then
        p.shadow.red = add_shift(add_shift(p.shadow.red, red_shift), shadow_extra)
      end
      if p.shadow.green then
        p.shadow.green = add_shift(add_shift(p.shadow.green, green_shift), shadow_extra)
      end
    end
  end
end

local function make_port(name, selection_box, red_shift_px, green_shift_px)
  local base = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
  base.name = name

  base.minable = nil
  base.placeable_by = nil
  base.fast_replaceable_group = nil
  base.next_upgrade = nil
  base.corpse = nil

  base.flags = {
    "not-blueprintable",
    "not-deconstructable",
    "not-upgradable",
    "not-repairable",
    "not-on-map",
    "not-flammable",
    "hide-alt-info",
  }

  base.selectable_in_game = true
  base.selection_priority = 255

  base.collision_box = {{0, 0}, {0, 0}}
  base.collision_mask = { layers = {} }

  local empty = util.empty_sprite()
  base.sprites = {
    north = empty,
    east  = empty,
    south = empty,
    west  = empty,
  }

  base.activity_led_sprites = {
    north = empty,
    east  = empty,
    south = empty,
    west  = empty,
  }

  base.activity_led_light = nil
  base.activity_led_light_offsets = { {0,0}, {0,0}, {0,0}, {0,0} }

  base.circuit_wire_max_distance = 9

  base.selection_box = selection_box
  base.drawing_box = selection_box

  local red_shift   = px(red_shift_px[1], red_shift_px[2])
  local green_shift = px(green_shift_px[1], green_shift_px[2])

  if base.circuit_wire_connection_points then
    offset_conn_points(base.circuit_wire_connection_points, red_shift, green_shift)
  end

  return base
end

------------------------------------------------------------
-- Selection boxes (locked)
------------------------------------------------------------

local SEL_W  = 5 / 32
local SEL_UP = 27 / 32

local Y1 = -0.70 - SEL_UP
local Y2 =  0.70 - SEL_UP

local TOP_CHOP = 22 / 32
local Y1_CHOPPED = Y1 + TOP_CHOP

local RIGHT_SEL_BOX = {{ 0.00, Y1_CHOPPED }, { SEL_W, Y2 }}

local BOTTOM_SEL_HALF_W = 0.35
local BOTTOM_SEL_H = 5 / 32

local BOTTOM_SEL_SHIFT_X = 16 / 32
local BOTTOM_SEL_SHIFT_Y = 0 / 32

local BOTTOM_SEL_BOX = {
  { -BOTTOM_SEL_HALF_W + BOTTOM_SEL_SHIFT_X, -BOTTOM_SEL_H / 2 + BOTTOM_SEL_SHIFT_Y },
  {  BOTTOM_SEL_HALF_W + BOTTOM_SEL_SHIFT_X,  BOTTOM_SEL_H / 2 + BOTTOM_SEL_SHIFT_Y }
}

------------------------------------------------------------
-- Locked base wire endpoint shifts
------------------------------------------------------------

local BASE_RIGHT_RED   = {  3, -11 }
local BASE_RIGHT_GREEN = { -10,  3 }

local BASE_BOTTOM_RED   = {  -9, -5 }
local BASE_BOTTOM_GREEN = {   4, -18 }

local function shifted(v, dx, dy)
  return { v[1] + dx, v[2] + dy }
end

------------------------------------------------------------
-- Right-side size variants
------------------------------------------------------------

-- right side moves LEFT by gap_px
local function make_right(size_suffix, gap_px)
  local rname = "widescreen-display-panel-connector-right-" .. size_suffix

  local r_red   = shifted(BASE_RIGHT_RED,   -gap_px, 0)
  local r_green = shifted(BASE_RIGHT_GREEN, -gap_px, 0)

  return make_port(rname, RIGHT_SEL_BOX, r_red, r_green)
end

------------------------------------------------------------
-- Bottom-side size variants
------------------------------------------------------------

local function make_bottom(size_suffix, red_shift_px, green_shift_px)
  local bname = "widescreen-display-panel-connector-bottom-" .. size_suffix
  return make_port(bname, BOTTOM_SEL_BOX, red_shift_px, green_shift_px)
end

local out = {}

-- right-side widescreens
out[#out+1] = make_right("2x1", 0)
out[#out+1] = make_right("3x1", 6)
out[#out+1] = make_right("4x1", 13)

-- bottom-side tallscreens
out[#out+1] = make_bottom("1x2", { 37, 7.5 }, { -4, 7 })
out[#out+1] = make_bottom("1x3", { 36, -4  }, { -4, -4 })
out[#out+1] = make_bottom("1x4", { 36, 0   }, { -4, 0 })

data:extend(out)
