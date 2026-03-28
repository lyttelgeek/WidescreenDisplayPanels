local util = require("util")

local function make_blank_oriented_sprites()
  local blank = {
    filename = "__core__/graphics/empty.png",
    width = 1,
    height = 1,
    frame_count = 1,
    line_length = 1,
    shift = util.by_pixel(0, 0),
    scale = 1
  }

  return {
    north = blank,
    east = blank,
    south = blank,
    west = blank
  }
end

local function make_hidden_arithmetic()
  local base = table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
  if not base then return nil end

  base.name = "wdp-smart-arithmetic"

  ------------------------------------------------------------
  -- Off-grid / non-interactive / script-only
  ------------------------------------------------------------
  base.flags = {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable"
  }

  base.minable = nil
  base.next_upgrade = nil
  base.fast_replaceable_group = nil

  base.collision_box = nil
  base.selection_box = nil
  base.selectable_in_game = false

  base.draw_circuit_wires = false
  base.draw_copper_wires = false
  base.circuit_connector = nil
  base.circuit_wire_max_distance = 0

  base.energy_source = {
    type = "void"
  }
  base.active_energy_usage = "1W"

  ------------------------------------------------------------
  -- Invisible visuals
  ------------------------------------------------------------
  base.sprites = make_blank_oriented_sprites()
  base.activity_led_sprites = make_blank_oriented_sprites()

  base.plus_symbol_sprites = make_blank_oriented_sprites()
  base.minus_symbol_sprites = make_blank_oriented_sprites()
  base.multiply_symbol_sprites = make_blank_oriented_sprites()
  base.divide_symbol_sprites = make_blank_oriented_sprites()
  base.power_symbol_sprites = make_blank_oriented_sprites()
  base.left_shift_symbol_sprites = make_blank_oriented_sprites()
  base.right_shift_symbol_sprites = make_blank_oriented_sprites()
  base.and_symbol_sprites = make_blank_oriented_sprites()
  base.or_symbol_sprites = make_blank_oriented_sprites()
  base.xor_symbol_sprites = make_blank_oriented_sprites()
  base.modulo_symbol_sprites = make_blank_oriented_sprites()

  if base.water_reflection then
    base.water_reflection = nil
  end

  return base
end

local function make_hidden_decider()
  local base = table.deepcopy(data.raw["decider-combinator"]["decider-combinator"])
  if not base then return nil end

  base.name = "wdp-smart-decider"

  ------------------------------------------------------------
  -- Off-grid / non-interactive / script-only
  ------------------------------------------------------------
  base.flags = {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable"
  }

  base.minable = nil
  base.next_upgrade = nil
  base.fast_replaceable_group = nil

  base.collision_box = nil
  base.selection_box = nil
  base.selectable_in_game = false

  base.draw_circuit_wires = false
  base.draw_copper_wires = false
  base.circuit_connector = nil
  base.circuit_wire_max_distance = 0

  base.energy_source = {
    type = "void"
  }
  base.active_energy_usage = "1W"

  ------------------------------------------------------------
  -- Invisible visuals
  ------------------------------------------------------------
  base.sprites = make_blank_oriented_sprites()
  base.activity_led_sprites = make_blank_oriented_sprites()

  base.equal_symbol_sprites = make_blank_oriented_sprites()
  base.greater_symbol_sprites = make_blank_oriented_sprites()
  base.less_symbol_sprites = make_blank_oriented_sprites()
  base.not_equal_symbol_sprites = make_blank_oriented_sprites()
  base.greater_or_equal_symbol_sprites = make_blank_oriented_sprites()
  base.less_or_equal_symbol_sprites = make_blank_oriented_sprites()

  if base.water_reflection then
    base.water_reflection = nil
  end

  return base
end

local function make_hidden_feeder()
  local base = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
  if not base then return nil end

  base.name = "wdp-smart-feeder"

  base.flags = {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable"
  }

  base.minable = nil
  base.next_upgrade = nil
  base.fast_replaceable_group = nil

  base.collision_box = nil
  base.selection_box = nil
  base.selectable_in_game = false

  base.draw_circuit_wires = false
  base.draw_copper_wires  = false
  base.circuit_connector = nil
  base.circuit_wire_max_distance = 0

  base.energy_source = { type = "void" }
  base.active_energy_usage = "1W"

  local empty = util.empty_sprite()
  base.sprites = {
    north = empty, east = empty, south = empty, west = empty
  }
  base.activity_led_sprites = {
    north = empty, east = empty, south = empty, west = empty
  }
  base.activity_led_light = nil
  base.activity_led_light_offsets = { {0,0}, {0,0}, {0,0}, {0,0} }

  if base.water_reflection then base.water_reflection = nil end

  return base
end

local arithmetic = make_hidden_arithmetic()
local decider    = make_hidden_decider()
local feeder     = make_hidden_feeder()

data:extend({
  arithmetic,
  decider,
  feeder
})