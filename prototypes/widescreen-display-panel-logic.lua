local util = require("util")

local function make_smart_arithmetic()
  local base = table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
  if not base then return nil end

  base.name = "wdp-smart-arithmetic"

  -- Non-interactive: managed entirely by script on the hidden surface.
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

  base.energy_source = { type = "void" }
  base.active_energy_usage = "1W"

  if base.water_reflection then base.water_reflection = nil end

  return base
end

local function make_smart_decider()
  local base = table.deepcopy(data.raw["decider-combinator"]["decider-combinator"])
  if not base then return nil end

  base.name = "wdp-smart-decider"

  -- Non-interactive: managed entirely by script on the hidden surface.
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

  base.energy_source = { type = "void" }
  base.active_energy_usage = "1W"

  if base.water_reflection then base.water_reflection = nil end

  return base
end

local function make_smart_feeder()
  local base = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
  if not base then return nil end

  base.name = "wdp-smart-feeder"

  -- Non-interactive and fully invisible: internal signal routing entity.
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

local arithmetic = make_smart_arithmetic()
local decider    = make_smart_decider()
local feeder     = make_smart_feeder()

data:extend({
  arithmetic,
  decider,
  feeder
})
