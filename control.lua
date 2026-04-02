local PANEL_SPECS = {
  ["widescreen-display-panel-2x1"] = { tiles_w = 2, tiles_h = 1, segments = 2, port_suffix = "2x1", port_side = "right",  title = "Widescreen Display Panel 2x1" },
  ["widescreen-display-panel-3x1"] = { tiles_w = 3, tiles_h = 1, segments = 3, port_suffix = "3x1", port_side = "right",  title = "Widescreen Display Panel 3x1" },
  ["widescreen-display-panel-4x1"] = { tiles_w = 4, tiles_h = 1, segments = 4, port_suffix = "4x1", port_side = "right",  title = "Widescreen Display Panel 4x1" },
  ["widescreen-display-panel-1x2"] = { tiles_w = 1, tiles_h = 2, segments = 2, port_suffix = "1x2", port_side = "bottom", title = "Widescreen Display Panel 1x2" },
  ["widescreen-display-panel-1x3"] = { tiles_w = 1, tiles_h = 3, segments = 3, port_suffix = "1x3", port_side = "bottom", title = "Widescreen Display Panel 1x3" },
  ["widescreen-display-panel-1x4"] = { tiles_w = 1, tiles_h = 4, segments = 4, port_suffix = "1x4", port_side = "bottom", title = "Widescreen Display Panel 1x4" },
}

local COMPARATORS = {
  { key = ">",  caption = ">"  },
  { key = "<",  caption = "<"  },
  { key = "=",  caption = "="  },
  { key = ">=", caption = "≥"  },
  { key = "<=", caption = "≤"  },
  { key = "!=", caption = "≠"  },
}

local COMPARATOR_INDEX = {}
for i, row in ipairs(COMPARATORS) do
  COMPARATOR_INDEX[row.key] = i
end

local SEGMENT_X_OFFSETS = {
  [2] = { -0.5,  0.5 },
  [3] = { -1.0,  0.0,  1.0 },
  [4] = { -1.5, -0.5,  0.5,  1.5 },
}

local SEGMENT_RENDER_X_ADJUST = {
  [2] = {  0.15625, -0.15625 },
  [3] = {  0.3125, 0.00, -0.3125 },
  [4] = {  0.53125, 0.171875, -0.171875, -0.53125 },
}

local ICON_Y_OFFSET = -0.258125
local TEXT_Y_OFFSET = -0.840625
local ICON_SCALE = 0.51
local TEXT_SCALE = 0.76

local SEGMENT_Y_OFFSETS_TALL = {
  [2] = { -0.40,  0.46 },
  [3] = { -0.75,  0.00,  0.75 },
  [4] = { -1.34, -0.46,  0.46,  1.34 },
}

local PANEL_TOP_BIAS_TALL = {
  [2] = -0.10 - (5 / 32),
  [3] = -0.18 - (7.5 / 32),
  [4] = -0.26 - (3 / 32),
}

local ICON_X_OFFSET_TALL = -1 / 32
local TEXT_X_OFFSET_TALL = -1 / 32
local TEXT_Y_OFFSET_TALL = -0.38
local BACKER_Y_OFFSET_TALL = TEXT_Y_OFFSET_TALL + 0.01

local BACKER_ENABLED = true
local BACKER_COLOR = { 0, 0, 0, 0.35 }
local BACKER_MIN_WIDTH = 0.22
local BACKER_CHAR_WIDTH = 0.070
local BACKER_PADDING_X = 0.035
local BACKER_HALF_HEIGHT = 0.150
local BACKER_Y_OFFSET = TEXT_Y_OFFSET + 0.01

local CAP_INSET_PX      = 7
local BASELINE_PX       = 7
local MAIN_SHIFT_PX     = 0
local MAIN_SHIFT_PY     = -3
local PORT_X_OUTSET_PX  = 12
local PORT_BOTTOM_OUTSET_PX = 20
local TALL_PORT_X_SHIFT_PX = -6

local DEBUG = false
local function dlog(msg) if DEBUG then log("WDP: " .. msg) end end
local function px_to_tiles(px) return px / 32 end

local function is_tall_panel(panel)
  local spec = panel and PANEL_SPECS[panel.name]
  return spec and spec.port_side == "bottom"
end

local function port_name_for(panel_name)
  local spec = PANEL_SPECS[panel_name]
  if not spec then return nil end

  if spec.port_side == "bottom" then
    return "widescreen-display-panel-connector-bottom-" .. spec.port_suffix
  end

  return "widescreen-display-panel-connector-right-" .. spec.port_suffix
end

local PORT_NAME_SET = {}
for _, spec in pairs(PANEL_SPECS) do
  PORT_NAME_SET["widescreen-display-panel-connector-right-" .. spec.port_suffix] = true
  PORT_NAME_SET["widescreen-display-panel-connector-bottom-" .. spec.port_suffix] = true
end

--[[
  Runtime responsibilities:
  - Attach and maintain hidden smart combinator and feeder entities on a hidden surface
  - Attach and maintain output port connector entities for widescreen panels
  - Merge panel circuit-network signals and feed them to smart combinators each tick
  - Evaluate per-segment rule stacks and render icon/message output
  - Provide chart-tag, hover-preview, and GUI editing behaviour
  - Expose merged signals for Signal Display compatibility
]]

local function ensure_global()
  if _G.storage == nil then _G.storage = {} end
  _G.global = _G.storage

  global.wdp = global.wdp or {}

  global.wdp.ports = global.wdp.ports or {}
  global.wdp.panels = global.wdp.panels or {}
  global.wdp.settings = global.wdp.settings or {}
  global.wdp.cache = global.wdp.cache or {}
  global.wdp.last_output_hash = global.wdp.last_output_hash or {}
  global.wdp.saved_settings = global.wdp.saved_settings or {}

  global.wdp.segment_data = global.wdp.segment_data or {}
  global.wdp.saved_segment_data = global.wdp.saved_segment_data or {}
  global.wdp.clipboard = global.wdp.clipboard or {}
  global.wdp.gui = global.wdp.gui or {}

  global.wdp.render_objects = global.wdp.render_objects or {}
  global.wdp.last_render_hash = global.wdp.last_render_hash or {}

  global.wdp.chart_tags = global.wdp.chart_tags or {}
  global.wdp.chart_tag_hash = global.wdp.chart_tag_hash or {}
  global.wdp.hover_render_objects = global.wdp.hover_render_objects or {}

  ------------------------------------------------------------
  -- Smart combinator registry
  ------------------------------------------------------------
  
  global.wdp.smart = global.wdp.smart or {}
  global.wdp.smart.combinators = global.wdp.smart.combinators or {}
end

------------------------------------------------------------
-- Hidden surface for internal entities (feeders, smart
-- combinators). Spawning them here keeps their wire
-- connection triangles off the player's surfaces entirely.
------------------------------------------------------------

local HIDDEN_SURFACE_NAME = "wdp-hidden"

local function get_or_create_hidden_surface()
  local s = game.get_surface(HIDDEN_SURFACE_NAME)
  if s then return s end
  return game.create_surface(HIDDEN_SURFACE_NAME, {
    width = 1, height = 1,
    default_enable_all_natural_resources = false,
    starting_points = {},
    autoplace_controls = {},
  })
end

------------------------------------------------------------
-- Smart combinator helpers
------------------------------------------------------------

local function get_smart_combinator_name(kind)
  if kind == "arithmetic_a" or kind == "arithmetic_b" then
    return "wdp-smart-arithmetic"
  elseif kind == "decider" then
    return "wdp-smart-decider"
  end
  return nil
end


local function get_registered_smart_combinator(unit_number)
  ensure_global()
  if not unit_number then return nil end

  local entry = global.wdp.smart.combinators[unit_number]
  if not entry then return nil end

  local ent = entry.entity
  if not (ent and ent.valid) then
    global.wdp.smart.combinators[unit_number] = nil
    return nil
  end

  return ent
end


local function register_smart_combinator(ent, panel, seg_index, kind)
  ensure_global()
  if not (ent and ent.valid and ent.unit_number) then return end
  if not (panel and panel.valid and panel.unit_number) then return end

  global.wdp.smart.combinators[ent.unit_number] = {
    entity = ent,
    panel_unit_number = panel.unit_number,
    segment_index = seg_index,
    kind = kind
  }
end


local function unregister_smart_combinator(unit_number)
  ensure_global()
  if not unit_number then return end
  global.wdp.smart.combinators[unit_number] = nil
end


local function destroy_smart_combinator_by_unit_number(unit_number)
  ensure_global()
  local entry = global.wdp.smart.combinators[unit_number]
  if entry then
    if entry.red_feeder   and entry.red_feeder.valid   then entry.red_feeder.destroy()   end
    if entry.green_feeder and entry.green_feeder.valid then entry.green_feeder.destroy() end
    if entry.entity       and entry.entity.valid       then entry.entity.destroy()       end
  end
  unregister_smart_combinator(unit_number)
end


local function create_smart_combinator(panel, seg_index, kind)
  ensure_global()
  if not (panel and panel.valid and panel.surface and panel.force) then return nil end

  local name = get_smart_combinator_name(kind)
  if not name then return nil end

  local hidden_surface = get_or_create_hidden_surface()
  if not hidden_surface then return nil end

  local ent = hidden_surface.create_entity{
    name = name,
    position = { panel.position.x + 0.1, panel.position.y + 0.1 },
    force = panel.force,
    create_build_effect_smoke = false
  }

  if not (ent and ent.valid and ent.unit_number) then return nil end

------------------------------------------------------------
-- Spawn two hidden constant combinator feeders -- one for
-- red signals, one for green -- and wire each to the
-- corresponding input connector of the smart combinator.
--
-- A constant combinator emits its signals on both wires
-- simultaneously, so separate entities are required to preserve
-- the red/green split the player wired to the panel.
-- Neither feeder is connected to the player's network.
------------------------------------------------------------

  local function make_feeder(offset_x, offset_y, feeder_wire_id, comb_connector_id)
    local f = hidden_surface.create_entity{
      name = "wdp-smart-feeder",
      position = { panel.position.x + offset_x, panel.position.y + offset_y },
      force = panel.force,
      create_build_effect_smoke = false,
    }
    if not (f and f.valid) then return nil end
    f.destructible = false
    f.minable      = false
    f.rotatable    = false
    f.operable     = false

    -- Wire feeder output -> combinator input connector (colour-matched).
    local f_out = f.get_wire_connector(feeder_wire_id, true)
    local c_in  = ent.get_wire_connector(comb_connector_id, true)
    if f_out and c_in then
      f_out.connect_to(c_in, false, defines.wire_origin.script)
    end
    return f
  end

  local red_feeder   = make_feeder(0.2, 0.2, defines.wire_connector_id.circuit_red,   defines.wire_connector_id.combinator_input_red)
  local green_feeder = make_feeder(0.3, 0.3, defines.wire_connector_id.circuit_green, defines.wire_connector_id.combinator_input_green)

  ent.destructible = false
  ent.minable = false
  ent.rotatable = false
  ent.operable = true


  register_smart_combinator(ent, panel, seg_index, kind)

  -- Store both feeders in the registry entry.
  local entry = global.wdp.smart.combinators[ent.unit_number]
  if entry then
    entry.red_feeder   = red_feeder
    entry.green_feeder = green_feeder
  end

  return ent
end

local function get_segment_smart_ref(seg, kind)
  if not seg then return nil end
  if not seg.smart then return nil end
  if not seg.smart[kind] then return nil end
  return seg.smart[kind].entity_unit_number
end

local function set_segment_smart_ref(seg, kind, unit_number)
  if not seg.smart then seg.smart = {} end
  if not seg.smart[kind] then seg.smart[kind] = {} end
  seg.smart[kind].entity_unit_number = unit_number
end

local function destroy_segment_smart_combinator(seg, kind)
  local ref = get_segment_smart_ref(seg, kind)
  if ref then
    destroy_smart_combinator_by_unit_number(ref)
    set_segment_smart_ref(seg, kind, nil)
  end
end

local function is_panel(e)
  return e and e.valid and PANEL_SPECS[e.name] ~= nil
end

local function is_port(e)
  return e and e.valid and PORT_NAME_SET[e.name] == true
end

local function destroy_if_valid(e)
  if e and e.valid then e.destroy() end
end

local function get_segment_count_for_panel_name(panel_name)
  local spec = PANEL_SPECS[panel_name]
  return spec and spec.segments or 1
end

local function normalize_signal_type_internal(t)
  if t == "virtual-signal" then
    return "virtual"
  end
  return t
end

local function infer_signal_type_from_name(name)
  if not name then return nil end

  if prototypes and prototypes.item and prototypes.item[name] then
    return "item"
  end

  if prototypes and prototypes.fluid and prototypes.fluid[name] then
    return "fluid"
  end

  if prototypes and prototypes.virtual_signal and prototypes.virtual_signal[name] then
    return "virtual"
  end

  return nil
end

local function normalize_signal(sig)
  if not sig or not sig.name then return nil end

  local t = sig.type
  if not t then
    t = infer_signal_type_from_name(sig.name)
  end

  t = normalize_signal_type_internal(t)
  if not t then return nil end

  return {
    type = t,
    name = sig.name,
    quality = sig.quality or "normal",
  }
end

local function clone_signal(sig)
  return normalize_signal(sig)
end

local function default_rhs()
  return {
    kind = "constant",
    constant = 0,
    signal = nil,
  }
end

local function default_rule()
  return {
    icon_signal = nil,
    first_signal = nil,
    comparator = ">",
    rhs = default_rhs(),
    message = "",
  }
end

local function default_segment()
  return {
    show_in_alt_mode = false,
    show_in_chart = false,
    rules = { default_rule() },
  }
end

local function default_panel_settings()
  return {
    show_in_chart = false,
  }
end

local function deep_copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do
    out[deep_copy(k)] = deep_copy(v)
  end
  return out
end

local function persist_panel_config(panel)
  ensure_global()
  if not (panel and panel.valid and panel.unit_number) then return end

  local unit = panel.unit_number
  local settings = global.wdp.settings[unit]
  local segdata = global.wdp.segment_data[unit]

  global.wdp.saved_settings[unit] = settings and deep_copy(settings) or nil
  global.wdp.saved_segment_data[unit] = segdata and deep_copy(segdata) or nil
end

------------------------------------------------------------
-- Settings / migration helpers
------------------------------------------------------------

local function ensure_rule_shape(rule)
  rule = rule or default_rule()
  rule.icon_signal = normalize_signal(rule.icon_signal)
  rule.first_signal = normalize_signal(rule.first_signal)
  rule.comparator = rule.comparator or ">"
  rule.message = rule.message or ""

  if rule.rhs == nil then
    local kind = (rule.rhs_mode == "signal") and "signal" or "constant"
    rule.rhs = {
      kind = kind,
      constant = tonumber(rule.constant) or 0,
      signal = normalize_signal(rule.second_signal),
    }
  end

  rule.rhs.kind = (rule.rhs.kind == "signal") and "signal" or "constant"
  rule.rhs.constant = tonumber(rule.rhs.constant) or 0
  rule.rhs.signal = normalize_signal(rule.rhs.signal)

  rule.rhs_mode = nil
  rule.constant = nil
  rule.second_signal = nil
  rule.show_in_alt_mode = nil
  rule.show_in_chart = nil

  return rule
end

local function ensure_panel_settings(panel)
  ensure_global()
  if not (panel and panel.valid and panel.unit_number) then return nil end

  local unit = panel.unit_number
  local settings = global.wdp.settings[unit]
  if not settings then
    settings = deep_copy(global.wdp.saved_settings[unit]) or default_panel_settings()
    global.wdp.settings[unit] = settings
  end

  if settings.show_in_chart == nil then
    settings.show_in_chart = false
  end

  return settings
end

local function ensure_panel_segment_data(panel)
  ensure_global()
  if not (panel and panel.valid and panel.unit_number) then return nil end

  local unit = panel.unit_number
  local wanted = get_segment_count_for_panel_name(panel.name)

  local data = global.wdp.segment_data[unit]
  if not data then
    data = deep_copy(global.wdp.saved_segment_data[unit]) or {
      segment_count = wanted,
      segments = {},
    }
    global.wdp.segment_data[unit] = data
  end

  data.segment_count = wanted
  data.segments = data.segments or {}

  for i = 1, wanted do
    data.segments[i] = data.segments[i] or default_segment()
    local seg = data.segments[i]

    if seg.rules == nil then
      seg.rules = {
        ensure_rule_shape({
          icon_signal = seg.icon_signal,
          first_signal = seg.first_signal,
          comparator = seg.comparator,
          rhs_mode = seg.rhs_mode,
          constant = seg.constant,
          second_signal = seg.second_signal,
          message = seg.message,
        })
      }
      seg.icon_signal = nil
      seg.first_signal = nil
      seg.comparator = nil
      seg.rhs_mode = nil
      seg.constant = nil
      seg.second_signal = nil
      seg.message = nil
    end

    if #seg.rules == 0 then
      seg.rules[1] = default_rule()
    end

    for r = 1, #seg.rules do
      local old_alt = seg.rules[r] and seg.rules[r].show_in_alt_mode
      seg.rules[r] = ensure_rule_shape(seg.rules[r])
      if seg.show_in_alt_mode == nil and old_alt ~= nil then
        seg.show_in_alt_mode = (old_alt == true)
      end
    end

    if seg.show_in_alt_mode == nil then
      seg.show_in_alt_mode = false
    end
    if seg.show_in_chart == nil then
      seg.show_in_chart = false
    end

    ------------------------------------------------------------
    -- Smart logic data model
    ------------------------------------------------------------
	
    seg.smart = seg.smart or {}

    if seg.smart.enabled == nil then
      seg.smart.enabled = false
    end

    -- Migrate legacy "arithmetic" slot to "arithmetic_b"
    if seg.smart.arithmetic and not seg.smart.arithmetic_b then
      seg.smart.arithmetic_b = seg.smart.arithmetic
      seg.smart.arithmetic = nil
    end

    seg.smart.arithmetic_a = seg.smart.arithmetic_a or {}
    if seg.smart.arithmetic_a.enabled == nil then
      seg.smart.arithmetic_a.enabled = false
    end
    if seg.smart.arithmetic_a.entity_unit_number == nil then
      seg.smart.arithmetic_a.entity_unit_number = nil
    end

    seg.smart.arithmetic_b = seg.smart.arithmetic_b or {}
    if seg.smart.arithmetic_b.enabled == nil then
      seg.smart.arithmetic_b.enabled = false
    end
    if seg.smart.arithmetic_b.entity_unit_number == nil then
      seg.smart.arithmetic_b.entity_unit_number = nil
    end

    seg.smart.decider = seg.smart.decider or {}
    if seg.smart.decider.enabled == nil then
      seg.smart.decider.enabled = false
    end
    if seg.smart.decider.entity_unit_number == nil then
      seg.smart.decider.entity_unit_number = nil
    end
  end

  for i = wanted + 1, #data.segments do
    data.segments[i] = nil
  end

  local psettings = ensure_panel_settings(panel)
  if psettings and psettings.show_in_chart then
    local any_chart = false
    for i = 1, wanted do
      if data.segments[i] and data.segments[i].show_in_chart then
        any_chart = true
        break
      end
    end
    if not any_chart and data.segments[1] then
      data.segments[1].show_in_chart = true
    end
    psettings.show_in_chart = false
  end

  return data
end

local function destroy_render_id(id)
  if not id then return end
  local obj = rendering.get_object_by_id(id)
  if obj then obj.destroy() end
end

local function clear_segment_render(panel_unit, seg_idx)
  ensure_global()

  local bucket = global.wdp.render_objects[panel_unit]
  if not bucket then return end

  local seg = bucket[seg_idx]
  if not seg then return end

  destroy_render_id(seg.icon)
  destroy_render_id(seg.backer)
  destroy_render_id(seg.text)

  bucket[seg_idx] = nil

  local hashes = global.wdp.last_render_hash[panel_unit]
  if hashes then hashes[seg_idx] = nil end
end

local function clear_all_panel_render(panel_unit)
  ensure_global()

  local bucket = global.wdp.render_objects[panel_unit]
  if bucket then
    for seg_idx, seg in pairs(bucket) do
      destroy_render_id(seg.icon)
      destroy_render_id(seg.backer)
      destroy_render_id(seg.text)
      bucket[seg_idx] = nil
    end
  end

  global.wdp.render_objects[panel_unit] = nil
  global.wdp.last_render_hash[panel_unit] = nil
end

local function clear_hover_render_for_player(player_index)
  ensure_global()

  local state = global.wdp.hover_render_objects[player_index]
  if not state then return end

  if state.segments then
    for seg_idx, seg in pairs(state.segments) do
      destroy_render_id(seg.icon)
      destroy_render_id(seg.backer)
      destroy_render_id(seg.text)
      state.segments[seg_idx] = nil
    end
  end

  global.wdp.hover_render_objects[player_index] = nil
end

local function destroy_chart_tag_if_valid(tag)
  if tag and tag.valid then
    tag.destroy()
  end
end

local function clear_panel_chart_tag(panel_unit)
  ensure_global()
  local tag = global.wdp.chart_tags[panel_unit]
  if tag then
    destroy_chart_tag_if_valid(tag)
  end
  global.wdp.chart_tags[panel_unit] = nil
  global.wdp.chart_tag_hash[panel_unit] = nil
end

local function expected_port_position(panel)
  local spec = PANEL_SPECS[panel.name]
  if not spec then return nil end

  local p = panel.position

  if spec.port_side == "bottom" then
    local half_height_px = (spec.tiles_h * 32) / 2
    local end_y_px = (half_height_px - CAP_INSET_PX) + PORT_BOTTOM_OUTSET_PX

    return {
      x = p.x + px_to_tiles(MAIN_SHIFT_PX + TALL_PORT_X_SHIFT_PX),
      y = p.y + px_to_tiles(end_y_px + MAIN_SHIFT_PY),
    }
  end

  local half_width_px = (spec.tiles_w * 32) / 2
  local end_x_px = (half_width_px - CAP_INSET_PX) + PORT_X_OUTSET_PX

  local y_px = BASELINE_PX + MAIN_SHIFT_PY
  local dx_right = end_x_px + MAIN_SHIFT_PX

  return {
    x = p.x + px_to_tiles(dx_right),
    y = p.y + px_to_tiles(y_px),
  }
end

local function destroy_ports_at_expected_pos(panel)
  if not (panel and panel.valid) then return end

  local port_name = port_name_for(panel.name)
  local pos = expected_port_position(panel)
  if not port_name or not pos then return end

  local eps_x = 0.30
  local eps_y = 0.30

  local found = panel.surface.find_entities_filtered{
    area = {
      { pos.x - eps_x, pos.y - eps_y },
      { pos.x + eps_x, pos.y + eps_y },
    },
    name = port_name,
    force = panel.force,
  }

  for i = 1, #found do
    local e = found[i]
    if e and e.valid then e.destroy() end
  end
end

local function destroy_ports_for_removed_panel(panel)
  if not (panel and panel.valid) then return end

  local spec = PANEL_SPECS[panel.name]
  local pname = port_name_for(panel.name)
  if not spec or not pname then return end

  local area
  if spec.port_side == "bottom" then
    local half_h = spec.tiles_h / 2
    area = {
      { panel.position.x - 1.5, panel.position.y },
      { panel.position.x + 1.5, panel.position.y + half_h + 1.5 },
    }
  else
    local half_w = spec.tiles_w / 2
    area = {
      { panel.position.x,                 panel.position.y - 1.5 },
      { panel.position.x + half_w + 1.5, panel.position.y + 1.5 },
    }
  end

  local found = panel.surface.find_entities_filtered{
    area = area,
    name = pname,
    force = panel.force,
  }

  for i = 1, #found do
    local e = found[i]
    if e and e.valid then e.destroy() end
  end
end

local function get_panel_by_unit(unit_number)
  ensure_global()

  local panel = global.wdp.panels[unit_number]
  if panel and panel.valid then
    return panel
  end

  global.wdp.panels[unit_number] = nil
  return nil
end

------------------------------------------------------------
-- Destroy every smart combinator that belongs to a panel,
-- working from the segment data.  Call this BEFORE clearing
-- segment_data so the entity_unit_numbers are still valid.
------------------------------------------------------------

local function destroy_all_panel_smart_combinators(unit_number)
  local segdata = global.wdp.segment_data[unit_number]
  if not segdata or not segdata.segments then return end

  for _, seg in ipairs(segdata.segments) do
    if seg.smart then
      for _, kind in ipairs({ "arithmetic_a", "arithmetic_b", "decider" }) do
        local ref = seg.smart[kind]
                    and seg.smart[kind].entity_unit_number
        if ref then
          destroy_smart_combinator_by_unit_number(ref)
          seg.smart[kind].entity_unit_number = nil
        end
      end
    end
  end
end

local function detach_ports_by_unit(unit_number, keep_settings)
  ensure_global()

  local ports = global.wdp.ports[unit_number]
  if ports then
    destroy_if_valid(ports.output)
    global.wdp.ports[unit_number] = nil
  end

  clear_all_panel_render(unit_number)
  clear_panel_chart_tag(unit_number)

  global.wdp.panels[unit_number] = nil
  global.wdp.cache[unit_number] = nil
  global.wdp.last_output_hash[unit_number] = nil

  -- Always destroy smart combinators regardless of keep_settings, since the entities themselves must not outlive the panel.
  destroy_all_panel_smart_combinators(unit_number)

  if not keep_settings then
    global.wdp.settings[unit_number] = nil
    global.wdp.segment_data[unit_number] = nil
    global.wdp.saved_settings[unit_number] = nil
    global.wdp.saved_segment_data[unit_number] = nil
  end

  for player_index, state in pairs(global.wdp.gui) do
    if state and state.panel_unit == unit_number then
      global.wdp.gui[player_index] = nil
    end
  end

  for player_index, hstate in pairs(global.wdp.hover_render_objects) do
    if hstate and hstate.panel_unit == unit_number then
      clear_hover_render_for_player(player_index)
    end
  end
end

------------------------------------------------------------
-- Port spawning
------------------------------------------------------------

local function make_ports_for_panel(panel)
  local spec = PANEL_SPECS[panel.name]
  if not spec then return nil end

  local pname = port_name_for(panel.name)
  if not pname then return nil end

  local pos = expected_port_position(panel)
  if not pos then return nil end

  local output = panel.surface.create_entity{
    name = pname,
    position = pos,
    force = panel.force,
    create_build_effect_smoke = false,
    raise_built = false,
  }

  if not (output and output.valid) then
    destroy_if_valid(output)
    return nil
  end

  -- Script-wire the port to the panel on both colours so the port shares the panel's input network. Downstream entities wired to the port see the same signals as the panel input.
  local port_red  = output.get_wire_connector(defines.wire_connector_id.circuit_red,  true)
  local panel_red = panel.get_wire_connector(defines.wire_connector_id.circuit_red,   true)
  if port_red and panel_red then
    port_red.connect_to(panel_red, false, defines.wire_origin.script)
  end

  local port_green  = output.get_wire_connector(defines.wire_connector_id.circuit_green, true)
  local panel_green = panel.get_wire_connector(defines.wire_connector_id.circuit_green,  true)
  if port_green and panel_green then
    port_green.connect_to(panel_green, false, defines.wire_origin.script)
  end

  return { output = output }
end

local function attach_ports(panel)
  if not is_panel(panel) or not panel.unit_number then return end

  ensure_global()

  local unit = panel.unit_number
  local old_ports = global.wdp.ports[unit]

  if old_ports then
    destroy_if_valid(old_ports.output)
    global.wdp.ports[unit] = nil
  end

  destroy_ports_at_expected_pos(panel)

  local ports = make_ports_for_panel(panel)

  global.wdp.panels[unit] = panel
  ensure_panel_settings(panel)
  ensure_panel_segment_data(panel)

  if ports then
    global.wdp.ports[unit] = ports
  end
end

local function detach_ports(panel)
  if not (panel and panel.unit_number) then return end
  detach_ports_by_unit(panel.unit_number)
end

local function ensure_panel_runtime(panel)
  if not is_panel(panel) or not panel.unit_number then return false end

  ensure_global()

  local unit = panel.unit_number
  global.wdp.panels[unit] = panel
  ensure_panel_settings(panel)
  ensure_panel_segment_data(panel)

  local ports = global.wdp.ports[unit]
  if not ports or not ports.output or not ports.output.valid then
    attach_ports(panel)
  end

  ------------------------------------------------------------
  -- Reconcile smart combinators: after a config change (or
  -- any other scenario where the entities were lost but the
  -- segment data still marks them as enabled) missing combinators
  -- are re-spawned so the refs stay valid.
  ------------------------------------------------------------
  
  local segdata = global.wdp.segment_data[unit]
  if segdata and segdata.segments then
    for seg_idx, seg in ipairs(segdata.segments) do
      if seg.smart and seg.smart.enabled then
        for _, kind in ipairs({ "arithmetic_a", "arithmetic_b", "decider" }) do
          local smart_slot = seg.smart[kind]
          if smart_slot and smart_slot.enabled then
            local ref = smart_slot.entity_unit_number
            local ent = ref and get_registered_smart_combinator(ref) or nil
            if not ent then
              -- If entity is missing then respawn it.
              ent = create_smart_combinator(panel, seg_idx, kind)
              if ent and ent.valid then
                smart_slot.entity_unit_number = ent.unit_number
              else
                smart_slot.entity_unit_number = nil
              end
            end
          end
        end
      end
    end
  end

  return true
end

------------------------------------------------------------
-- Signal helpers
------------------------------------------------------------

local function add_signals(dst, sigs)
  if not sigs then return end
  for _, s in ipairs(sigs) do
    if s.signal and s.signal.name then
      -- In Factorio 2.0, item signals have type = nil when read from the network.
      local stype = s.signal.type
      if not stype or stype == "" then
        stype = infer_signal_type_from_name(s.signal.name) or "item"
      end
      stype = normalize_signal_type_internal(stype)
      local quality = s.signal.quality or "normal"
      local key = stype .. ":" .. s.signal.name .. ":" .. quality
      dst[key] = (dst[key] or 0) + (s.count or 0)
    end
  end
end

local function table_to_signal_array(t)
  local arr = {}
  for key, count in pairs(t) do
    local typ, name, quality = key:match("^([^:]+):([^:]+):?(.*)$")
    typ = normalize_signal_type_internal(typ)
    arr[#arr + 1] = {
      signal = {
        type = typ,
        name = name,
        quality = (quality ~= "" and quality or "normal")
      },
      count = count
    }
  end
  return arr
end

local function sorted_keys(t)
  local keys = {}
  for k, _ in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

local function hash_signal_table(t)
  if not t or next(t) == nil then return "" end
  local keys = sorted_keys(t)
  local parts = {}
  for i = 1, #keys do
    local k = keys[i]
    parts[#parts + 1] = k .. "=" .. tostring(t[k])
  end
  return table.concat(parts, ";")
end

local function signal_key_from_signal(sig)
  if not sig or not sig.name then return nil end

  local t = sig.type
  if not t then
    t = infer_signal_type_from_name(sig.name)
  end

  t = normalize_signal_type_internal(t)
  if not t then return nil end

  return t .. ":" .. sig.name .. ":" .. (sig.quality or "normal")
end

local function signal_value_from_table(merged_tbl, sig)
  local key = signal_key_from_signal(sig)
  if not key then return 0 end
  return merged_tbl[key] or 0
end

local function comparator_pass(lhs, op, rhs)
  if op == ">"  then return lhs >  rhs end
  if op == "<"  then return lhs <  rhs end
  if op == "="  then return lhs == rhs end
  if op == ">=" then return lhs >= rhs end
  if op == "<=" then return lhs <= rhs end
  if op == "!=" then return lhs ~= rhs end
  return false
end

local function sprite_namespace_for_signal(sig)
  if not sig or not sig.name then return nil end

  local t = sig.type
  if not t then
    t = infer_signal_type_from_name(sig.name)
  end

  t = normalize_signal_type_internal(t)

  if t == "virtual" or t == "virtual-signal" then
    return "virtual-signal"
  elseif t == "item" then
    return "item"
  elseif t == "fluid" then
    return "fluid"
  elseif t == "recipe" then
    return "recipe"
  elseif t == "entity" then
    return "entity"
  elseif t == "space-location" then
    return "space-location"
  elseif t == "asteroid-chunk" then
    return "asteroid-chunk"
  elseif t == "quality" then
    return "quality"
  end

  return nil
end

local function sprite_path_from_signal(sig)
  local ns = sprite_namespace_for_signal(sig)
  if not ns then return nil end
  return ns .. "/" .. sig.name
end

local function rich_text_token_for_signal(sig)
  local ns = sprite_namespace_for_signal(sig)
  if not ns then return nil end
  return "[img=" .. ns .. "/" .. sig.name .. "]"
end

local function rhs_value_from_rule(rule, merged_tbl)
  if not rule or not rule.rhs then return 0 end
  if rule.rhs.kind == "signal" then
    return signal_value_from_table(merged_tbl, rule.rhs.signal)
  end
  return tonumber(rule.rhs.constant) or 0
end

local function segment_offsets_for_count(segment_count)
  return SEGMENT_X_OFFSETS[segment_count]
end

local function segment_render_adjust_for_count(segment_count)
  return SEGMENT_RENDER_X_ADJUST[segment_count]
end

local function estimated_backer_width_for_message(message)
  local msg = message or ""

  local visible_units = 0
  local i = 1

  while i <= #msg do
    local lb = string.find(msg, "[", i, true)
    if not lb then
      visible_units = visible_units + (#msg - i + 1)
      break
    end

    if lb > i then
      visible_units = visible_units + (lb - i)
    end

    local rb = string.find(msg, "]", lb + 1, true)
    if not rb then
      visible_units = visible_units + (#msg - lb + 1)
      break
    end

    local inside = string.sub(msg, lb + 1, rb - 1)

    if string.find(inside, "sig ", 1, true) == 1 then
      visible_units = visible_units + 4.0
    end

    i = rb + 1
  end

  local width = (visible_units * BACKER_CHAR_WIDTH) + (BACKER_PADDING_X * 2)
  if width < BACKER_MIN_WIDTH then width = BACKER_MIN_WIDTH end
  return width
end

local function evaluate_segment_rules(seg_cfg, merged_tbl)
  if not seg_cfg or not seg_cfg.rules then return nil end

  for i = 1, #seg_cfg.rules do
    local rule = seg_cfg.rules[i]
    local first_sig = rule.first_signal
    local lhs = signal_value_from_table(merged_tbl, first_sig)
    local rhs = rhs_value_from_rule(rule, merged_tbl)
    local visible = first_sig and comparator_pass(lhs, rule.comparator or ">", rhs) or false

    if visible then
      return {
        rule_index = i,
        rule = rule,
        lhs_value = lhs,
        rhs_value = rhs,
      }
    end
  end

  return nil
end

-- Core hash builder: takes an already-evaluated match (or nil).
-- Avoids re-running evaluate_segment_rules when the caller already has it.
local function make_render_hash_from_match(seg_cfg, match)
  if not match then return "hidden" end

  local rule = match.rule
  local rhs_sig_key = signal_key_from_signal(rule.rhs and rule.rhs.signal) or "nil"
  local icon_key    = signal_key_from_signal(rule.icon_signal)              or "nil"
  local first_key   = signal_key_from_signal(rule.first_signal)             or "nil"

  return table.concat({
    "rule="     .. tostring(match.rule_index),
    "lhs="      .. tostring(match.lhs_value),
    "rhs="      .. tostring(match.rhs_value),
    "rhs_kind=" .. tostring(rule.rhs and rule.rhs.kind or "constant"),
    "rhs_sig="  .. rhs_sig_key,
    "icon="     .. icon_key,
    "first="    .. first_key,
    "op="       .. tostring(rule.comparator or ">"),
    "msg="      .. tostring(rule.message or ""),
    "alt="      .. tostring(seg_cfg and seg_cfg.show_in_alt_mode == true),
  }, "|")
end

-- Convenience wrapper for callers that don't have a pre-computed match (used by the hover-render path).
local function make_render_hash(seg_cfg, merged_tbl)
  local match = evaluate_segment_rules(seg_cfg, merged_tbl)
  return make_render_hash_from_match(seg_cfg, match)
end

local function get_panel_networks(panel)
  local networks = {}
  local ids = {}

  local function try_add(net)
    if net and net.valid and net.network_id ~= nil
        and not ids[net.network_id] then
      ids[net.network_id] = true
      networks[#networks + 1] = net
    end
  end

  -- Use entity-direct API only (Factorio 2.0).
  -- The old behavior.get_circuit_network path can return a different network object for the same connector, causing double-counting.
  local ok_r, net_r = pcall(function()
    return panel.get_circuit_network(defines.wire_connector_id.circuit_red)
  end)
  if ok_r then try_add(net_r) end

  local ok_g, net_g = pcall(function()
    return panel.get_circuit_network(defines.wire_connector_id.circuit_green)
  end)
  if ok_g then try_add(net_g) end

  return networks
end

local function read_networks_to_table(networks)
  local merged_tbl = {}
  for i = 1, #networks do
    local net = networks[i]
    if net and net.valid then
      add_signals(merged_tbl, net.signals)
    end
  end
  return merged_tbl
end

------------------------------------------------------------
-- Read all circuit-network signals visible to a panel and
-- return them as both a flat key->count table and an array.
------------------------------------------------------------

local function compute_merged_for_panel(panel)
  if not (panel and panel.valid and panel.unit_number) then
    return {}, {}
  end
  local networks   = get_panel_networks(panel)
  local merged_tbl = read_networks_to_table(networks)
  local merged_arr = table_to_signal_array(merged_tbl)
  return merged_tbl, merged_arr
end

------------------------------------------------------------
-- Read a smart combinator's computed output into a flat
-- key->count table.
--
-- Use signals_last_tick from LuaCombinatorControlBehavior
-- which gives the signals the combinator *output* last tick
-- directly: no need to read a circuit network at all.
-- This works regardless of whether the output connectors
-- are wired to anything.
------------------------------------------------------------

local function read_combinator_output_to_table(ent)
  local out = {}
  if not (ent and ent.valid) then return out end

  local ok, cb = pcall(function()
    return ent.get_or_create_control_behavior()
  end)
  if not ok or not cb then return out end

  local ok2, signals = pcall(function()
    return cb.signals_last_tick
  end)
  if not ok2 or not signals then return out end

  add_signals(out, signals)
  return out
end

------------------------------------------------------------
-- Merge two flat key->count tables.
-- high_tbl wins on key collision (decider > arithmetic).
------------------------------------------------------------

local function merge_signal_tables_with_priority(low_tbl, high_tbl)
  local out = {}
  for k, v in pairs(low_tbl  or {}) do out[k] = v end
  for k, v in pairs(high_tbl or {}) do out[k] = v end
  return out
end

------------------------------------------------------------
-- Compute the effective signal table for a single segment.
-- Signal flow:
--   panel input -> arithmetic_a -> arithmetic_b -> segment
--   decider is independent, merges with arithmetic_b output
--   (decider wins on collision).
-- Falls back to raw panel input if nothing produces output.
------------------------------------------------------------

local function compute_smart_output_for_segment(panel, seg)
  local raw_tbl, raw_arr = compute_merged_for_panel(panel)

  if not (seg and seg.smart and seg.smart.enabled) then
    return raw_tbl, raw_arr
  end

  -- arithmetic_b reads from arithmetic_a output (if arithmetic_a enabled), otherwise reads raw panel input via its feeders.
  local arithmetic_b_tbl = {}
  if seg.smart.arithmetic_b
      and seg.smart.arithmetic_b.enabled
      and seg.smart.arithmetic_b.entity_unit_number then
    local ent = get_registered_smart_combinator(
                  seg.smart.arithmetic_b.entity_unit_number)
    if ent and ent.valid then
      arithmetic_b_tbl = read_combinator_output_to_table(ent)
    end
  end

  local decider_tbl = {}
  if seg.smart.decider
      and seg.smart.decider.enabled
      and seg.smart.decider.entity_unit_number then
    local ent = get_registered_smart_combinator(
                  seg.smart.decider.entity_unit_number)
    if ent and ent.valid then
      decider_tbl = read_combinator_output_to_table(ent)
    end
  end

  -- Merge arithmetic_b and decider; decider wins on collision.
  local merged_tbl = merge_signal_tables_with_priority(arithmetic_b_tbl, decider_tbl)

  -- Fall back to raw panel input if nothing produced output.
  if next(merged_tbl) == nil then
    return raw_tbl, raw_arr
  end

  return merged_tbl, table_to_signal_array(merged_tbl)
end

------------------------------------------------------------
-- Constant combinator write
------------------------------------------------------------

local function write_const(port, merged_tbl)
  local cb = port.get_or_create_control_behavior()
  if not cb then
    dlog("write_const: no control behavior")
    return false
  end

  cb.enabled = true

  local section = cb.get_section(1)
  if not section then
    section = cb.add_section()
  end
  if not section then
    dlog("write_const: failed to get/add section")
    return false
  end

  section.active = true

  local old_count = section.filters_count or 0
  for i = old_count, 1, -1 do
    pcall(function() section.clear_slot(i) end)
  end

  if not merged_tbl or next(merged_tbl) == nil then
    return true
  end

  local keys = sorted_keys(merged_tbl)
  local slot = 1

  for i = 1, #keys do
    local key = keys[i]
    local count = merged_tbl[key]
    local typ, name, quality = key:match("^([^:]+):([^:]+):?(.*)$")
    typ = normalize_signal_type_internal(typ)

    local sig = {
      type = typ,
      name = name,
      quality = (quality ~= "" and quality or "normal")
    }

    local ok = pcall(function()
      section.set_slot(slot, {
        value = sig,
        min = count
      })
    end)

    if ok then
      slot = slot + 1
      if slot > 1000 then break end
    else
      dlog("write_const: failed set_slot for " .. key)
    end
  end

  return true
end

local function chart_payload_for_panel(panel, merged_tbl)
  local pdata = ensure_panel_segment_data(panel)
  if not pdata then
    return nil, ""
  end

  for seg_idx = 1, pdata.segment_count do
    local seg = pdata.segments[seg_idx]
    if seg.show_in_chart then
      local match = evaluate_segment_rules(seg, merged_tbl)

      if match then
        local rule = match.rule
        local icon = normalize_signal(rule.icon_signal)
        local text = rule.message or ""

        if icon or text ~= "" then
          local icon_key = signal_key_from_signal(icon) or "nil"
          local hash = table.concat({
            "seg=" .. tostring(seg_idx),
            "icon=" .. icon_key,
            "msg=" .. tostring(text),
            "x=" .. tostring(panel.position.x),
            "y=" .. tostring(panel.position.y),
          }, "|")

          return {
            position = { panel.position.x, panel.position.y },
            icon = icon,
            text = (text ~= "" and text or nil),
          }, hash
        end
      end
    end
  end

  return nil, ""
end

local function update_panel_chart_tag(panel, panel_unit, merged_tbl)
  ensure_global()

  local payload, new_hash = chart_payload_for_panel(panel, merged_tbl)
  local old_hash = global.wdp.chart_tag_hash[panel_unit]

  if not payload then
    if old_hash ~= "" then
      clear_panel_chart_tag(panel_unit)
      global.wdp.chart_tag_hash[panel_unit] = ""
    end
    return
  end

  if new_hash == old_hash then
    local tag = global.wdp.chart_tags[panel_unit]
    if tag and tag.valid then
      return
    end
  end

  clear_panel_chart_tag(panel_unit)

  local tag = panel.force.add_chart_tag(panel.surface, {
    position = payload.position,
    icon = payload.icon,
    text = payload.text,
  })

  global.wdp.chart_tags[panel_unit] = tag
  global.wdp.chart_tag_hash[panel_unit] = new_hash
end

local function get_network_ids_by_color(panel)
  local red_id   = nil
  local green_id = nil

  local ok_r, net_r = pcall(function()
    return panel.get_circuit_network(defines.wire_connector_id.circuit_red)
  end)
  if ok_r and net_r and net_r.valid and net_r.network_id ~= nil then
    red_id = net_r.network_id
  end

  local ok_g, net_g = pcall(function()
    return panel.get_circuit_network(defines.wire_connector_id.circuit_green)
  end)
  if ok_g and net_g and net_g.valid and net_g.network_id ~= nil then
    green_id = net_g.network_id
  end

  return red_id, green_id
end

local function message_preview_text(message)
  local msg = message or ""
  msg = string.gsub(msg, string.char(13), " ")
  msg = string.gsub(msg, string.char(10), " ")

  if msg == "" then
    return "(No label)"
  end

  local max_visible = 24
  local out = {}
  local visible = 0
  local i = 1
  local truncated = false

  while i <= #msg do
    local token_start = string.find(msg, "[img=", i, true)

    if token_start == i then
      local close_pos = string.find(msg, "]", i + 5, true)
      if close_pos then
        if visible >= max_visible then
          truncated = true
          break
        end

        out[#out + 1] = string.sub(msg, token_start, close_pos)
        visible = visible + 1
        i = close_pos + 1
      else
        out[#out + 1] = string.sub(msg, i, i)
        visible = visible + 1
        i = i + 1
      end
    else
      local text_end = token_start and (token_start - 1) or #msg
      local chunk = string.sub(msg, i, text_end)

      for ch in string.gmatch(chunk, ".") do
        if visible >= max_visible then
          truncated = true
          break
        end
        out[#out + 1] = ch
        visible = visible + 1
      end

      if truncated then
        break
      end

      i = text_end + 1
    end
  end

  local preview = table.concat(out)
  if truncated or i <= #msg then
    preview = preview .. "…"
  end

  return preview
end

------------------------------------------------------------
-- Segment rendering
------------------------------------------------------------

local function ensure_render_bucket(panel_unit)
  ensure_global()
  global.wdp.render_objects[panel_unit] = global.wdp.render_objects[panel_unit] or {}
  global.wdp.last_render_hash[panel_unit] = global.wdp.last_render_hash[panel_unit] or {}
  return global.wdp.render_objects[panel_unit], global.wdp.last_render_hash[panel_unit]
end

-- smart_tbl_cache: optional table[seg_idx] -> pre-computed effective signal table for smart segments.
-- Built once per tick in update_panel_render and passed down to avoid re-reading combinator outputs per segment. 
local function render_segment(panel, panel_unit, seg_idx, seg_cfg, merged_tbl, segment_count, smart_tbl_cache)
  local bucket, hash_bucket = ensure_render_bucket(panel_unit)

  ------------------------------------------------------------
  -- Resolve effective signal table for this segment.
  -- Use the pre-computed cache entry when available, otherwise
  -- fall back to computing it now (e.g. direct calls outside
  -- the tick loop).
  ------------------------------------------------------------
  
  local effective_tbl
  if smart_tbl_cache and smart_tbl_cache[seg_idx] then
    effective_tbl = smart_tbl_cache[seg_idx]
  elseif seg_cfg and seg_cfg.smart and seg_cfg.smart.enabled then
    effective_tbl = select(1, compute_smart_output_for_segment(panel, seg_cfg))
  else
    effective_tbl = merged_tbl
  end

  -- Evaluate rules once; reuse result for both hash and render.
  local match    = evaluate_segment_rules(seg_cfg, effective_tbl)
  local new_hash = make_render_hash_from_match(seg_cfg or {}, match)
  local old_hash = hash_bucket[seg_idx]

  if new_hash == old_hash then return end

  clear_segment_render(panel_unit, seg_idx)

  if not match then
    hash_bucket[seg_idx] = new_hash
    return
  end

  local render_x, icon_y, text_y, backer_y

  if is_tall_panel(panel) then
    local y_offsets = SEGMENT_Y_OFFSETS_TALL[segment_count]
    if not y_offsets or not y_offsets[seg_idx] then
      hash_bucket[seg_idx] = new_hash
      return
    end

    local bias = PANEL_TOP_BIAS_TALL[segment_count] or 0

    render_x = ICON_X_OFFSET_TALL
    icon_y = y_offsets[seg_idx] + bias
    text_y = y_offsets[seg_idx] + TEXT_Y_OFFSET_TALL + bias
    backer_y = y_offsets[seg_idx] + BACKER_Y_OFFSET_TALL + bias
  else
    local offsets = segment_offsets_for_count(segment_count)
    local adjusts = segment_render_adjust_for_count(segment_count)
    if not offsets or not offsets[seg_idx] then
      hash_bucket[seg_idx] = new_hash
      return
    end

    render_x = offsets[seg_idx] + ((adjusts and adjusts[seg_idx]) or 0)
    icon_y = ICON_Y_OFFSET
    text_y = TEXT_Y_OFFSET
    backer_y = BACKER_Y_OFFSET
  end

  local rule = match.rule
  local sprite = sprite_path_from_signal(rule.icon_signal)
  local message = rule.message or ""
  local always_visible_message = (seg_cfg and seg_cfg.show_in_alt_mode == true)

  local seg_bucket = {}

  if sprite then
    local obj = rendering.draw_sprite{
      sprite = sprite,
      surface = panel.surface,
      target = { entity = panel, offset = { render_x, icon_y } },
      x_scale = ICON_SCALE,
      y_scale = ICON_SCALE,
      forces = panel.force,
    }
    seg_bucket.icon = obj and obj.id or nil
  end

  if always_visible_message and BACKER_ENABLED and message ~= "" then
    local width = estimated_backer_width_for_message(message)
    local half_width = width / 2
    local rect = rendering.draw_rectangle{
      color = BACKER_COLOR,
      filled = true,
      surface = panel.surface,
      left_top = { entity = panel, offset = { render_x - half_width, backer_y - BACKER_HALF_HEIGHT } },
      right_bottom = { entity = panel, offset = { render_x + half_width, backer_y + BACKER_HALF_HEIGHT } },
      forces = panel.force,
    }
    seg_bucket.backer = rect and rect.id or nil
  end

  if always_visible_message and message ~= "" then
    local txt = rendering.draw_text{
      text = message,
      surface = panel.surface,
      target = { entity = panel, offset = { render_x, text_y } },
      color = { 1, 1, 1 },
      scale = TEXT_SCALE,
      scale_with_zoom = true,
      alignment = "center",
      vertical_alignment = "middle",
      forces = panel.force,
      use_rich_text = true,
    }
    seg_bucket.text = txt and txt.id or nil
  end

  bucket[seg_idx] = seg_bucket
  hash_bucket[seg_idx] = new_hash
end

local function update_hover_render_for_player(player)
  if not (player and player.valid) then return end
  ensure_global()

  local selected = player.selected
  if not is_panel(selected) then
    clear_hover_render_for_player(player.index)
    return
  end

  ensure_panel_runtime(selected)

  local panel = selected
  local panel_unit = panel.unit_number
  local pdata = ensure_panel_segment_data(panel)
  if not pdata then
    clear_hover_render_for_player(player.index)
    return
  end

  local merged_tbl = compute_merged_for_panel(panel)

  local state = global.wdp.hover_render_objects[player.index]
  if not state or state.panel_unit ~= panel_unit then
    clear_hover_render_for_player(player.index)
    state = {
      panel_unit = panel_unit,
      segments = {},
      hashes = {},
    }
    global.wdp.hover_render_objects[player.index] = state
  end

  for seg_idx = 1, pdata.segment_count do
    local seg_cfg = pdata.segments[seg_idx]
    local new_hash = make_render_hash(seg_cfg or {}, merged_tbl)
    local old_hash = state.hashes[seg_idx]
    local always_visible_message = (seg_cfg and seg_cfg.show_in_alt_mode == true)

    if always_visible_message then
      local seg = state.segments[seg_idx]
      if seg then
        destroy_render_id(seg.backer)
        destroy_render_id(seg.text)
        state.segments[seg_idx] = nil
      end
      state.hashes[seg_idx] = nil

    elseif new_hash ~= old_hash then
      local seg = state.segments[seg_idx]
      if seg then
        destroy_render_id(seg.backer)
        destroy_render_id(seg.text)
        state.segments[seg_idx] = nil
      end

      local match = evaluate_segment_rules(seg_cfg, merged_tbl)
      if match then
        local render_x, text_y, backer_y

        if is_tall_panel(panel) then
          local y_offsets = SEGMENT_Y_OFFSETS_TALL[pdata.segment_count]
          if y_offsets and y_offsets[seg_idx] then
            local bias = PANEL_TOP_BIAS_TALL[pdata.segment_count] or 0

            render_x = TEXT_X_OFFSET_TALL
            text_y = y_offsets[seg_idx] + TEXT_Y_OFFSET_TALL + bias
            backer_y = y_offsets[seg_idx] + BACKER_Y_OFFSET_TALL + bias
          end
        else
          local offsets = segment_offsets_for_count(pdata.segment_count)
          local adjusts = segment_render_adjust_for_count(pdata.segment_count)
          if offsets and offsets[seg_idx] then
            render_x = offsets[seg_idx] + ((adjusts and adjusts[seg_idx]) or 0)
            text_y = TEXT_Y_OFFSET
            backer_y = BACKER_Y_OFFSET
          end
        end

        if render_x ~= nil and text_y ~= nil and backer_y ~= nil then
          local rule = match.rule
          local message = rule.message or ""
          local seg_bucket = {}

          if BACKER_ENABLED and message ~= "" then
            local width = estimated_backer_width_for_message(message)
            local half_width = width / 2
            local rect = rendering.draw_rectangle{
              color = BACKER_COLOR,
              filled = true,
              surface = panel.surface,
              left_top = { entity = panel, offset = { render_x - half_width, backer_y - BACKER_HALF_HEIGHT } },
              right_bottom = { entity = panel, offset = { render_x + half_width, backer_y + BACKER_HALF_HEIGHT } },
              players = { player },
            }
            seg_bucket.backer = rect and rect.id or nil
          end

          if message ~= "" then
            local txt = rendering.draw_text{
              text = message,
              surface = panel.surface,
              target = { entity = panel, offset = { render_x, text_y } },
              color = { 1, 1, 1 },
              scale = TEXT_SCALE,
              scale_with_zoom = true,
              alignment = "center",
              vertical_alignment = "middle",
              players = { player },
              use_rich_text = true,
            }
            seg_bucket.text = txt and txt.id or nil
          end

          state.segments[seg_idx] = seg_bucket
        end
      end

      state.hashes[seg_idx] = new_hash
    end
  end
end

local function update_panel_render(panel, panel_unit, merged_tbl)
  ensure_global()

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then
    clear_all_panel_render(panel_unit)
    return
  end

  ------------------------------------------------------------
  -- Build smart output cache: one combinator read per enabled
  -- segment, shared across this entire render pass.
  ------------------------------------------------------------
  
  local smart_tbl_cache = nil
  for seg_idx = 1, pdata.segment_count do
    local seg = pdata.segments[seg_idx]
    if seg and seg.smart and seg.smart.enabled then
      smart_tbl_cache = smart_tbl_cache or {}
      smart_tbl_cache[seg_idx] = select(1, compute_smart_output_for_segment(panel, seg))
    end
  end

  for seg_idx = 1, pdata.segment_count do
    render_segment(panel, panel_unit, seg_idx, pdata.segments[seg_idx], merged_tbl, pdata.segment_count, smart_tbl_cache)
  end

  local bucket = global.wdp.render_objects[panel_unit]
  if bucket then
    for seg_idx, _ in pairs(bucket) do
      if seg_idx > pdata.segment_count then
        clear_segment_render(panel_unit, seg_idx)
      end
    end
  end
end
------------------------------------------------------------
-- Core mirror / update loop
------------------------------------------------------------

------------------------------------------------------------
-- Update smart combinator feeders for a panel.
-- Called each tick so combinators always see current signals.
------------------------------------------------------------

local function update_smart_feeders_for_panel(panel, panel_unit)
  ensure_global()
  local segdata = global.wdp.segment_data[panel_unit]
  if not segdata or not segdata.segments then return end

  local function read_net(connector_id)
    local t = {}
    local ok, net = pcall(function()
      return panel.get_circuit_network(connector_id)
    end)
    if ok and net and net.valid and net.signals then
      add_signals(t, net.signals)
    end
    return t
  end

  local red_tbl   = read_net(defines.wire_connector_id.circuit_red)
  local green_tbl = read_net(defines.wire_connector_id.circuit_green)

  for _, seg in ipairs(segdata.segments) do
    if seg.smart and seg.smart.enabled then

      -- arithmetic_a: fed by raw panel input (red/green split)
      local slot_a = seg.smart.arithmetic_a
      if slot_a and slot_a.enabled and slot_a.entity_unit_number then
        local entry = global.wdp.smart.combinators[slot_a.entity_unit_number]
        if entry then
          if entry.red_feeder   and entry.red_feeder.valid   then
            write_const(entry.red_feeder,   red_tbl)
          end
          if entry.green_feeder and entry.green_feeder.valid then
            write_const(entry.green_feeder, green_tbl)
          end
        end
      end

      -- arithmetic_b: fed by arithmetic_a output if enabled, else raw panel input
      local slot_b = seg.smart.arithmetic_b
      if slot_b and slot_b.enabled and slot_b.entity_unit_number then
        local entry = global.wdp.smart.combinators[slot_b.entity_unit_number]
        if entry then
          local feed_tbl
          if slot_a and slot_a.enabled and slot_a.entity_unit_number then
            local ent_a = get_registered_smart_combinator(slot_a.entity_unit_number)
            if ent_a and ent_a.valid then
              feed_tbl = read_combinator_output_to_table(ent_a)
            end
          end
          feed_tbl = feed_tbl or {}
          -- Fall back to raw panel input if arithmetic_a produced nothing
          if next(feed_tbl) == nil then
            feed_tbl = nil  -- signal: use raw split below
          end
          if entry.red_feeder and entry.red_feeder.valid then
            write_const(entry.red_feeder,   feed_tbl or red_tbl)
          end
          if entry.green_feeder and entry.green_feeder.valid then
            write_const(entry.green_feeder, feed_tbl or green_tbl)
          end
        end
      end

      -- decider: always fed by raw panel input (independent)
      local slot_d = seg.smart.decider
      if slot_d and slot_d.enabled and slot_d.entity_unit_number then
        local entry = global.wdp.smart.combinators[slot_d.entity_unit_number]
        if entry then
          if entry.red_feeder   and entry.red_feeder.valid   then
            write_const(entry.red_feeder,   red_tbl)
          end
          if entry.green_feeder and entry.green_feeder.valid then
            write_const(entry.green_feeder, green_tbl)
          end
        end
      end

    end
  end
end

local function mirror_and_cache(panel_unit)
  ensure_global()

  local panel = get_panel_by_unit(panel_unit)
  local ports = global.wdp.ports[panel_unit]

  if not panel then
    global.wdp.cache[panel_unit] = {}
    clear_all_panel_render(panel_unit)
    clear_panel_chart_tag(panel_unit)

    return
  end

  local merged_tbl, merged_arr = compute_merged_for_panel(panel)
  global.wdp.cache[panel_unit] = merged_arr

  update_smart_feeders_for_panel(panel, panel_unit)
  update_panel_render(panel, panel_unit, merged_tbl)
  update_panel_chart_tag(panel, panel_unit, merged_tbl)
end

------------------------------------------------------------
-- Signal bar: rebuild (full) and tick-update (in-place)
------------------------------------------------------------

local function format_si_compact(n)
  if not n then return "0" end
  n = tonumber(n) or 0

  local abs_n = math.abs(n)
  local sign = (n < 0) and "-" or ""

  if abs_n < 1000 then
    return tostring(n)
  elseif abs_n < 1000000 then
    return string.format("%s%.1fk", sign, abs_n / 1000):gsub("%.0k", "k")
  elseif abs_n < 1000000000 then
    return string.format("%s%.1fM", sign, abs_n / 1000000):gsub("%.0M", "M")
  elseif abs_n < 1000000000000 then
    return string.format("%s%.1fG", sign, abs_n / 1000000000):gsub("%.0G", "G")
  else
    return string.format("%s%.1fT", sign, abs_n / 1000000000000):gsub("%.0T", "T")
  end
end
local tick_update_gui_signal_bars  -- defined after get_gui_state
local tick_update_signal_bar         -- defined after get_gui_state
local rebuild_signal_bar             -- defined after get_gui_state

local function tick_merge()
  ensure_global()
  for panel_unit, _ports in pairs(global.wdp.ports) do
    mirror_and_cache(panel_unit)
  end

  for _, player in pairs(game.connected_players) do
    update_hover_render_for_player(player)
    tick_update_gui_signal_bars(player)
  end
end

------------------------------------------------------------
-- GUI helpers
------------------------------------------------------------

local function get_gui_state(player_index)
  ensure_global()
  return global.wdp.gui[player_index]
end

local function get_panel_from_gui_state(state)
  if not state then return nil end
  return get_panel_by_unit(state.panel_unit)
end

-- Called each tick for every connected player.
-- Updates the signal bar in-place if the player has the panel GUI open.
tick_update_gui_signal_bars = function(player)
  if not (player and player.valid) then return end
  local state = get_gui_state(player.index)
  if not state then return end
  local panel = get_panel_from_gui_state(state)
  if not (panel and panel.valid) then return end
  local frame = player.gui.screen.wdp_main
  if frame and frame.valid then
    tick_update_signal_bar(frame, panel, player.index)
  end
end

------------------------------------------------------------
-- Signal bar functions
-- (defined here so get_gui_state and get_panel_from_gui_state
--  are already in scope)
------------------------------------------------------------

-- Returns red_tbl, green_tbl -- signal tables split by wire colour.
-- When a smart combinator is active and producing output, its result
-- is returned on both wires (combinators output on both red and green).
local function get_active_segment_signals_by_wire(panel, player_index)
  local state = get_gui_state(player_index)

  local seg = nil
  if state then
    local pdata = ensure_panel_segment_data(panel)
    if pdata then
      local seg_idx = math.max(1, math.min(state.active_tab or 1, pdata.segment_count))
      seg = pdata.segments[seg_idx]
    end
  end

  local function read_net(connector_id)
    local t = {}
    local ok, net = pcall(function()
      return panel.get_circuit_network(connector_id)
    end)
    if ok and net and net.valid and net.signals then
      add_signals(t, net.signals)
    end
    return t
  end

  -- If a smart combinator is enabled and producing output, show that on both wires (combinators output on both red and green).
  -- The master toggle alone does not change signals: only an enabled smart combinator does.
  local any_sub_enabled = seg and seg.smart and seg.smart.enabled and (
    (seg.smart.arithmetic_a and seg.smart.arithmetic_a.enabled) or
    (seg.smart.arithmetic_b and seg.smart.arithmetic_b.enabled) or
    (seg.smart.decider      and seg.smart.decider.enabled)
  )

  if any_sub_enabled then
    local smart_tbl = select(1, compute_smart_output_for_segment(panel, seg))
    if smart_tbl and next(smart_tbl) ~= nil then
      return smart_tbl, smart_tbl
    end
  end

  -- Raw: red/green split from the panel input
  return read_net(defines.wire_connector_id.circuit_red),
         read_net(defines.wire_connector_id.circuit_green)
end

-- Helper: add a row of signal slots to a parent element.
local function add_signal_row(parent, row_name, slot_style, entries)
  if #entries == 0 then return end

  local tbl = parent.add{
    type = "table",
    name = row_name,
    column_count = 13,
  }
  tbl.style.horizontal_spacing = 0
  tbl.style.vertical_spacing = 0

  for _, entry in ipairs(entries) do
    local typ, name, quality = entry.key:match("^([^:]+):([^:]+):?(.*)$")
    typ     = normalize_signal_type_internal(typ)
    quality = (quality ~= "" and quality or "normal")

    local sprite_path = sprite_namespace_for_signal({ type = typ, name = name })
    sprite_path = sprite_path and (sprite_path .. "/" .. name) or nil

    parent[row_name].add{
      type    = "sprite-button",
      name    = "wdp_sigbar" .. entry.key,
      style   = slot_style,
      sprite  = sprite_path,
	  quality = quality,
      tooltip = name .. ": " .. format_si_compact(entry.count),
      number  = entry.count,
    }
  end
end

local function tbl_to_sorted_entries(t)
  local entries = {}
  for key, count in pairs(t) do
    entries[#entries + 1] = { key = key, count = count }
  end
  table.sort(entries, function(a, b) return a.key < b.key end)
  return entries
end

rebuild_signal_bar = function(frame, panel, player_index)
  local body = frame.wdp_body
  if not (body and body.valid) then return end

  -- Destroy and re-add holder and footer so they are always the last children of body, regardless of rebuild order. 
  if body.wdp_signal_bar_holder and body.wdp_signal_bar_holder.valid then
    body.wdp_signal_bar_holder.destroy()
  end
  if body.wdp_footer and body.wdp_footer.valid then
    body.wdp_footer.destroy()
  end

  local holder = body.add{
    type = "flow",
    name = "wdp_signal_bar_holder",
    direction = "vertical",
  }
  holder.style.horizontally_stretchable = true
  holder.style.padding = 0
  holder.style.vertical_spacing = 0

  local footer = body.add{ type = "flow", name = "wdp_footer", direction = "horizontal" }
  footer.style.top_margin = 6
  local footer_spacer = footer.add{ type = "empty-widget" }
  footer_spacer.style.horizontally_stretchable = true
  local confirm_btn = footer.add{ type = "sprite-button", name = "wdp_confirm", style = "wdp_confirm_button", sprite = "utility/confirm_slot", tooltip = "Apply and close" }
  confirm_btn.style.width = 28
  confirm_btn.style.height = 28

  holder.clear()

  local red_tbl, green_tbl = get_active_segment_signals_by_wire(panel, player_index)
  local red_entries   = tbl_to_sorted_entries(red_tbl)
  local green_entries = tbl_to_sorted_entries(green_tbl)

  if #red_entries == 0 and #green_entries == 0 then
    local lbl = holder.add{ type = "label", caption = "No signals" }
    lbl.style.font_color = { 0.5, 0.5, 0.5 }
    lbl.style.top_margin = 2
    lbl.style.bottom_margin = 2
    return
  end

  -- deep_slots_scroll_pane with a vertical flow (vertical_spacing=0).
  -- 2 rows × 30px per colour before scrolling.
  local pane = holder.add{
    type  = "scroll-pane",
    name  = "wdp_signal_pane",
    style = "deep_slots_scroll_pane",
    vertical_scroll_policy   = "auto",
    horizontal_scroll_policy = "never",
  }
  pane.style.horizontally_stretchable = true
  pane.style.minimal_height = 160  -- 2 rows × 30px × 2 colours + spacing
  pane.style.maximal_height = 160  

  local inner = pane.add{
    type      = "flow",
    name      = "wdp_signal_inner",
    direction = "vertical",
  }
  inner.style.vertical_spacing = 0

  if #red_entries > 0 then
    add_signal_row(inner, "wdp_red_row", "red_slot", red_entries)
  end

  if #green_entries > 0 then
    add_signal_row(inner, "wdp_green_row", "green_slot", green_entries)
  end
end

tick_update_signal_bar = function(frame, panel, player_index)
  local holder = frame.wdp_body and frame.wdp_body.wdp_signal_bar_holder
  if not (holder and holder.valid) then return end

  local pane = holder.wdp_signal_pane
  if not (pane and pane.valid) then
    rebuild_signal_bar(frame, panel, player_index)
    return
  end

  local inner = pane.wdp_signal_inner
  if not (inner and inner.valid) then
    rebuild_signal_bar(frame, panel, player_index)
    return
  end

  local red_tbl, green_tbl = get_active_segment_signals_by_wire(panel, player_index)

  -- Check if the signal sets have changed; rebuild if so.
  local function count_keys(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

  local function row_needs_rebuild(row_elem, tbl)
    if not (row_elem and row_elem.valid) then
      return count_keys(tbl) > 0
    end
    local children = row_elem.children
    if #children ~= count_keys(tbl) then return true end
    for _, child in ipairs(children) do
      local key = child.name:match("^wdp_sigbar(.+)$")
      if not key or tbl[key] == nil then return true end
    end
    return false
  end

  local red_row   = inner.wdp_red_row
  local green_row = inner.wdp_green_row

  if row_needs_rebuild(red_row, red_tbl)
      or row_needs_rebuild(green_row, green_tbl) then
    rebuild_signal_bar(frame, panel, player_index)
    return
  end

  -- If same sets then update counts in-place.
  local function update_row(row_elem, tbl)
    if not (row_elem and row_elem.valid) then return end
    for _, child in ipairs(row_elem.children) do
      if child and child.valid then
        local key = child.name:match("^wdp_sigbar(.+)$")
        if key then
          local count = tbl[key] or 0
          child.number = count
          local _, signame = key:match("^([^:]+):([^:]+)")
          child.tooltip = (signame or key) .. ": " .. format_si_compact(count)
        end
      end
    end
  end

  update_row(red_row,   red_tbl)
  update_row(green_row, green_tbl)
end

local function get_active_segment_config(panel, player_index)
  local state = get_gui_state(player_index)
  if not state then return nil, nil end

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return nil, nil end

  local idx = math.max(1, math.min(state.active_tab or 1, pdata.segment_count))
  return pdata.segments[idx], idx
end

local function get_rule_from_state(panel, state)
  if not panel or not state then return nil, nil, nil end
  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return nil, nil, nil end

  local seg_idx = math.max(1, math.min(state.active_tab or 1, pdata.segment_count))
  local seg = pdata.segments[seg_idx]
  if not seg then return nil, nil, nil end

  local rule_idx = state.active_rule
  if not rule_idx or not seg.rules[rule_idx] then return nil, seg_idx, nil end
  return seg.rules[rule_idx], seg_idx, rule_idx
end

local function comparator_items()
  local items = {}
  for i = 1, #COMPARATORS do
    items[#items + 1] = COMPARATORS[i].caption
  end
  return items
end


local function safe_number_text(text)
  local n = tonumber(text)
  if n == nil then return nil end
  return n
end

local apply_gui_to_segment
local refresh_live_panel_preview
local rebuild_editor
local refresh_main_gui

local function add_rule(seg)
  seg.rules[#seg.rules + 1] = default_rule()
end

local function remove_rule(seg, idx)
  if #seg.rules <= 1 then
    seg.rules[1] = default_rule()
    return 1
  end
  table.remove(seg.rules, idx)
  if idx > #seg.rules then idx = #seg.rules end
  if idx < 1 then idx = 1 end
  return idx
end

local function move_rule_up(seg, idx)
  if idx <= 1 or idx > #seg.rules then return idx end
  seg.rules[idx - 1], seg.rules[idx] = seg.rules[idx], seg.rules[idx - 1]
  return idx - 1
end

local function move_rule_down(seg, idx)
  if idx < 1 or idx >= #seg.rules then return idx end
  seg.rules[idx + 1], seg.rules[idx] = seg.rules[idx], seg.rules[idx + 1]
  return idx + 1
end

local function render_rhs_count_for_rule(panel, rule, merged_tbl)
  if not panel or not rule or not rule.rhs then return "" end
  if rule.rhs.kind ~= "signal" or not rule.rhs.signal then return "" end
  local val = signal_value_from_table(merged_tbl, rule.rhs.signal)
  return tostring(val)
end

------------------------------------------------------------
-- Combinator config serialise / apply
-- (used by both segment and panel copy/paste)
------------------------------------------------------------

local function serialise_combinator_config(ent)
  if not (ent and ent.valid) then return nil end
  local cb = ent.get_or_create_control_behavior()
  if not cb then return nil end

  local kind
  if ent.name == "wdp-smart-arithmetic" then
    kind = "arithmetic"
  elseif ent.name == "wdp-smart-decider" then
    kind = "decider"
  else
    return nil
  end

  local ok, params = pcall(function()
    if kind == "arithmetic" then
      return cb.arithmetic_conditions
    else
      return cb.decider_conditions
    end
  end)

  if not ok or not params then return nil end
  return { kind = kind, params = deep_copy(params) }
end

local function apply_combinator_config(ent, config)
  if not (ent and ent.valid and config and config.params) then return end
  local cb = ent.get_or_create_control_behavior()
  if not cb then return end

  pcall(function()
    if config.kind == "arithmetic" then
      cb.arithmetic_conditions = config.params
    else
      cb.decider_conditions = config.params
    end
  end)
end

local function copy_active_segment(player)
  ensure_global()

  local state = get_gui_state(player.index)
  local panel = get_panel_from_gui_state(state)
  if not panel then return false end

  apply_gui_to_segment(player)

  local seg = get_active_segment_config(panel, player.index)
  if not seg then return false end

  -- Deep-copy the segment including smart state.
  -- entity_unit_numbers are excluded because they are runtime handles; paste will re-create entities as needed. 
  local seg_copy = deep_copy(seg)
  if seg_copy.smart then
    for _, kind in ipairs({ "arithmetic_a", "arithmetic_b", "decider" }) do
      local slot = seg_copy.smart[kind]
      if slot then
        -- Capture combinator config before stripping the unit number.
        local ref = seg.smart[kind] and seg.smart[kind].entity_unit_number
        local ent = ref and get_registered_smart_combinator(ref) or nil
        slot.config = serialise_combinator_config(ent)
        slot.entity_unit_number = nil
      end
    end
  end

  global.wdp.clipboard[player.index] = {
    kind = "segment",
    data = seg_copy,
  }

  return true
end

local function paste_active_segment(player)
  ensure_global()

  local clip = global.wdp.clipboard[player.index]
  if not clip or clip.kind ~= "segment" or not clip.data then
    return false
  end

  local state = get_gui_state(player.index)
  local panel = get_panel_from_gui_state(state)
  if not panel then return false end

  local seg, seg_idx = get_active_segment_config(panel, player.index)
  if not seg then return false end

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return false end

  local pasted = deep_copy(clip.data)

  seg.show_in_alt_mode = (pasted.show_in_alt_mode == true)
  seg.show_in_chart = (pasted.show_in_chart == true)
  seg.rules = pasted.rules or { default_rule() }

  if #seg.rules == 0 then
    seg.rules = { default_rule() }
  end

  for i = 1, #seg.rules do
    seg.rules[i] = ensure_rule_shape(seg.rules[i])
  end

  if seg.show_in_chart then
    for i = 1, pdata.segment_count do
      if i ~= seg_idx and pdata.segments[i] then
        pdata.segments[i].show_in_chart = false
      end
    end
  end

  -- Restore smart logic state.
  local src_smart = pasted.smart or {}
  seg.smart = seg.smart or {}
  seg.smart.enabled = (src_smart.enabled == true)

  for _, kind in ipairs({ "arithmetic_a", "arithmetic_b", "decider" }) do
    local src_slot = src_smart[kind] or {}
    seg.smart[kind] = seg.smart[kind] or {}
    local dst_slot = seg.smart[kind]

    local want_enabled = (src_slot.enabled == true) and seg.smart.enabled

    if want_enabled then
      local ref = dst_slot.entity_unit_number
      local ent = ref and get_registered_smart_combinator(ref) or nil
      if not ent then
        ent = create_smart_combinator(panel, seg_idx, kind)
        if ent and ent.valid then
          dst_slot.entity_unit_number = ent.unit_number
        else
          dst_slot.entity_unit_number = nil
        end
      end
      dst_slot.enabled = true
      if ent and src_slot.config then
        apply_combinator_config(ent, src_slot.config)
      end
    else
      if dst_slot.entity_unit_number then
        destroy_segment_smart_combinator(seg, kind)
      end
      dst_slot.enabled = false
    end
  end

  persist_panel_config(panel)
  global.wdp.last_render_hash[panel.unit_number] = nil
  global.wdp.chart_tag_hash[panel.unit_number] = nil

  mirror_and_cache(panel.unit_number)
  refresh_main_gui(player)
  return true
end


------------------------------------------------------------
-- Panel-wide copy / paste  (Ctrl-C / settings-paste tool)
------------------------------------------------------------

-- Serialise one smart combinator's behavior config so it can be stored in the clipboard and re-applied on paste.
-- Capture the full panel state into the player's panel clipboard.
local function copy_panel(player, panel)
  ensure_global()
  if not (panel and panel.valid) then return false end

  ensure_panel_runtime(panel)
  apply_gui_to_segment(player)

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return false end

  local segments = {}

  for seg_idx = 1, pdata.segment_count do
    local seg = pdata.segments[seg_idx]
    if not seg then break end

    local seg_copy = {
      show_in_alt_mode = seg.show_in_alt_mode,
      -- show_in_chart intentionally excluded
      rules = deep_copy(seg.rules),
      smart = {
        enabled = seg.smart and seg.smart.enabled or false,
        arithmetic_a = {
          enabled = seg.smart and seg.smart.arithmetic_a and seg.smart.arithmetic_a.enabled or false,
          config   = nil,
        },
        arithmetic_b = {
          enabled = seg.smart and seg.smart.arithmetic_b and seg.smart.arithmetic_b.enabled or false,
          config   = nil,
        },
        decider = {
          enabled = seg.smart and seg.smart.decider and seg.smart.decider.enabled or false,
          config   = nil,
        },
      },
    }

    -- Serialise combinator configs if entities exist.
    if seg.smart then
      for _, kind in ipairs({ "arithmetic_a", "arithmetic_b", "decider" }) do
        local slot = seg.smart[kind]
        if slot and slot.enabled and slot.entity_unit_number then
          local ent = get_registered_smart_combinator(slot.entity_unit_number)
          seg_copy.smart[kind].config = serialise_combinator_config(ent)
        end
      end
    end

    segments[seg_idx] = seg_copy
  end

  global.wdp.clipboard[player.index] = {
    kind     = "panel",
    segments = segments,
  }

  return true
end

-- Paste a panel clipboard onto a destination panel.
-- Segments are mapped 1-to-1; extras on the source are dropped, extras on the destination are left untouched.
local function paste_panel(player, src_panel, dst_panel)
  ensure_global()
  if not (dst_panel and dst_panel.valid) then return false end

  -- src_panel may be nil if we're pasting from clipboard rather
  -- than directly from a source entity.
  local clip
  if src_panel and src_panel.valid and src_panel ~= dst_panel then
    -- Called from on_entity_settings_pasted: build clip on the fly.
    copy_panel(player, src_panel)
  end
  clip = global.wdp.clipboard[player.index]

  if not clip or clip.kind ~= "panel" or not clip.segments then
    return false
  end

  ensure_panel_runtime(dst_panel)

  local pdata = ensure_panel_segment_data(dst_panel)
  if not pdata then return false end

  local n_src = #clip.segments
  local n_dst = pdata.segment_count

  for seg_idx = 1, math.min(n_src, n_dst) do
    local src_seg = clip.segments[seg_idx]
    local dst_seg = pdata.segments[seg_idx]
    if not (src_seg and dst_seg) then break end

    dst_seg.show_in_alt_mode = (src_seg.show_in_alt_mode == true)
    -- show_in_chart left untouched

    dst_seg.rules = deep_copy(src_seg.rules) or { default_rule() }
    if #dst_seg.rules == 0 then dst_seg.rules = { default_rule() } end
    for i = 1, #dst_seg.rules do
      dst_seg.rules[i] = ensure_rule_shape(dst_seg.rules[i])
    end

    -- Smart combinator state
    local src_smart = src_seg.smart or {}
    dst_seg.smart = dst_seg.smart or {}
    dst_seg.smart.enabled = (src_smart.enabled == true)

    for _, kind in ipairs({ "arithmetic_a", "arithmetic_b", "decider" }) do
      local src_slot = src_smart[kind] or {}
      dst_seg.smart[kind] = dst_seg.smart[kind] or {}
      local dst_slot = dst_seg.smart[kind]

      local want_enabled = (src_slot.enabled == true) and dst_seg.smart.enabled

      if want_enabled then
        -- Ensure the entity exists (create if missing).
        local ref = dst_slot.entity_unit_number
        local ent = ref and get_registered_smart_combinator(ref) or nil
        if not ent then
          ent = create_smart_combinator(dst_panel, seg_idx, kind)
          if ent and ent.valid then
            dst_slot.entity_unit_number = ent.unit_number
          else
            dst_slot.entity_unit_number = nil
          end
        end
        dst_slot.enabled = true
        -- Re-apply saved combinator config.
        if ent and src_slot.config then
          apply_combinator_config(ent, src_slot.config)
        end
      else
        -- Disable and destroy if it was running.
        if dst_slot.entity_unit_number then
          destroy_segment_smart_combinator(dst_seg, kind)
        end
        dst_slot.enabled = false
      end
    end
  end

  persist_panel_config(dst_panel)
  global.wdp.last_render_hash[dst_panel.unit_number] = nil
  global.wdp.chart_tag_hash[dst_panel.unit_number]   = nil
  mirror_and_cache(dst_panel.unit_number)

  -- Refresh GUI if the player has the destination panel open.
  local state = get_gui_state(player.index)
  if state and state.panel_unit == dst_panel.unit_number then
    refresh_main_gui(player)
  end

  return true
end

local function destroy_rhs_popup(player)
  local screen = player.gui.screen
  if screen.wdp_rhs_popup and screen.wdp_rhs_popup.valid then
    screen.wdp_rhs_popup.destroy()
  end
end

local function destroy_msg_icon_popup(player)
  local screen = player.gui.screen
  if screen.wdp_msg_icon_popup and screen.wdp_msg_icon_popup.valid then
    screen.wdp_msg_icon_popup.destroy()
  end
end

local function destroy_message_popup(player)
  destroy_msg_icon_popup(player)
  local screen = player.gui.screen
  if screen.wdp_msg_popup and screen.wdp_msg_popup.valid then
    screen.wdp_msg_popup.destroy()
  end
end

local function destroy_smart_popup(player)
  local popup = player.gui.screen.wdp_smart_popup
  if popup and popup.valid then popup.destroy() end
  -- Untoggle the titlebar button
  local main = player.gui.screen.wdp_main
  if main and main.valid and main.wdp_titlebar and main.wdp_titlebar.valid then
    local btn = main.wdp_titlebar.wdp_smart_toggle
    if btn and btn.valid then btn.toggled = false end
  end
end

local function destroy_main_gui(player)
  destroy_rhs_popup(player)
  destroy_message_popup(player)
  destroy_smart_popup(player)

  local screen = player.gui.screen
  if screen.wdp_main and screen.wdp_main.valid then
    screen.wdp_main.destroy()
  end

  ensure_global()
  global.wdp.gui[player.index] = nil
end

local function rebuild_connected_row(holder, panel)
  if holder.wdp_connected_row and holder.wdp_connected_row.valid then
    holder.wdp_connected_row.destroy()
  end

  local red_id, green_id = get_network_ids_by_color(panel)

  local conn = holder.add{
    type = "flow",
    name = "wdp_connected_row",
    direction = "horizontal"
  }
  conn.style.horizontally_stretchable = true
  conn.style.horizontal_spacing = 4
  conn.style.vertical_align = "center"
  conn.style.height = 24
  conn.style.top_margin = 2
  conn.style.bottom_margin = 2

  local label = conn.add{
    type = "label",
    caption = "Connected to:"
  }
  label.style.top_margin = 7

  local red = conn.add{
    type = "label",
    caption = tostring(red_id or 0)
  }
  red.style.font_color = { 1, 0.23, 0.19 }
  red.style.top_margin = 7

  local green = conn.add{
    type = "label",
    caption = tostring(green_id or 0)
  }
  green.style.font_color = { 0.25, 0.9, 0.25 }
  green.style.top_margin = 7

  local spacer = conn.add{ type = "empty-widget" }
  spacer.style.horizontally_stretchable = true
end

local function rebuild_alt_row(body, panel, player_index)
end

local function rebuild_chart_row(body, panel, player_index)
end

local function rebuild_segment_tabs(frame, panel, player_index)
  local body = frame.wdp_body
  if not (body and body.valid) then return end

  if body.wdp_top_controls and body.wdp_top_controls.valid then
    body.wdp_top_controls.destroy()
  end

  if body.wdp_tabs and body.wdp_tabs.valid then
    body.wdp_tabs.destroy()
  end

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return end

  local state = get_gui_state(player_index)
  local seg = get_active_segment_config(panel, player_index)
  if not seg then return end

  ------------------------------------------------------------
  -- Top controls root
  ------------------------------------------------------------
  
  local top = body.add{
    type = "flow",
    name = "wdp_top_controls",
    direction = "vertical"
  }
  top.style.horizontally_stretchable = true
  top.style.top_margin = 2
  top.style.bottom_margin = 6
  top.style.vertical_spacing = 6

  ------------------------------------------------------------
  -- Segment tabs + copy/paste row
  ------------------------------------------------------------
  
  local tabs_row = top.add{
    type = "flow",
    name = "wdp_tabs_row",
    direction = "horizontal"
  }
  tabs_row.style.horizontally_stretchable = true
  tabs_row.style.top_margin = 7
  tabs_row.style.vertical_align = "center"
  tabs_row.style.horizontal_spacing = 6

  local tabs_left = tabs_row.add{
    type = "flow",
    name = "wdp_segment_flow",
    direction = "horizontal"
  }
  tabs_left.style.horizontal_spacing = 4
  tabs_left.style.vertical_align = "center"

  for i = 1, pdata.segment_count do
    local b = tabs_left.add{
      type = "sprite-button",
      name = "wdp_tab" .. i,
      style = "frame_action_button",
      sprite = "virtual-signal/signal-" .. i,
      tooltip = "Select segment " .. i
    }
    b.style.width = 26
    b.style.height = 26

    if state and state.active_tab == i then
      b.enabled = false
    end
  end

  local tabs_spacer = tabs_row.add{ type = "empty-widget" }
  tabs_spacer.style.horizontally_stretchable = true

  local actions = tabs_row.add{
    type = "flow",
    name = "wdp_copy_paste_flow",
    direction = "horizontal"
  }
  actions.style.horizontal_spacing = 6
  actions.style.vertical_align = "center"

  local copy_btn = actions.add{
    type = "button",
    name = "wdp_copy_segment",
    caption = "Copy segment"
  }
  copy_btn.style.minimal_width = 92
  copy_btn.style.height = 28

  local paste_btn = actions.add{
    type = "button",
    name = "wdp_paste_segment",
    caption = "Paste segment"
  }
  paste_btn.enabled = not not (global.wdp.clipboard[player_index] and global.wdp.clipboard[player_index].kind == "segment")
  paste_btn.style.minimal_width = 92
  paste_btn.style.height = 28

  local lower = top.add{
    type = "flow",
    name = "wdp_top_lower",
    direction = "horizontal"
  }
  lower.style.horizontally_stretchable = true
  lower.style.horizontal_spacing = 8
  lower.style.vertical_align = "top"

  ------------------------------------------------------------
  -- Settings flow
  ------------------------------------------------------------
  
  local settings_frame = lower.add{
    type = "flow",
    name = "wdp_settings_frame",
    direction = "vertical"
  }
  settings_frame.style.horizontally_stretchable = true
  settings_frame.style.minimal_width = 0
  settings_frame.style.minimal_height = 60
  settings_frame.style.left_margin = 8
  settings_frame.style.right_margin = 8
  settings_frame.style.top_margin = 8
  settings_frame.style.bottom_margin = 8
  settings_frame.style.vertical_spacing = 0
  settings_frame.style.vertical_align = "center"

  local alt_row = settings_frame.add{
    type = "flow",
    name = "wdp_alt_row",
    direction = "horizontal"
  }
  alt_row.style.horizontal_spacing = 6
  alt_row.style.vertical_align = "center"
  alt_row.style.height = 22

  alt_row.add{
    type = "checkbox",
    name = "wdp_show_in_alt_mode",
    caption = 'Always show in "Alt-mode"',
    state = seg.show_in_alt_mode == true
  }

  local chart_row = settings_frame.add{
    type = "flow",
    name = "wdp_chart_row",
    direction = "horizontal"
  }
  chart_row.style.top_margin = 7
  chart_row.style.horizontal_spacing = 6
  chart_row.style.vertical_align = "center"
  chart_row.style.height = 22

  chart_row.add{
    type = "checkbox",
    name = "wdp_show_in_chart",
    caption = "Show this tag in chart",
    state = seg.show_in_chart == true
  }
end

------------------------------------------------------------
-- Smart logic pop-out window
------------------------------------------------------------

local function build_smart_popup(player, panel, seg, seg_idx)
  destroy_smart_popup(player)

  local popup = player.gui.screen.add{
    type = "frame",
    name = "wdp_smart_popup",
    direction = "vertical",
  }
  popup.auto_center = false
  popup.style.width = 196

  -- Position just to the right of the main frame
  local main = player.gui.screen.wdp_main
  if main and main.valid then
    popup.location = {
      x = main.location.x + 422,
      y = main.location.y
    }
  end
  
------------------------------------------------------------
  -- Titlebar
------------------------------------------------------------
  
  local titlebar = popup.add{ type = "flow", name = "wdp_smart_popup_titlebar", direction = "horizontal" }
  titlebar.drag_target = popup
  local title = titlebar.add{ type = "label", caption = "Smartscreen logic", style = "frame_title" }
  title.drag_target = popup
  local drag = titlebar.add{ type = "empty-widget", style = "draggable_space_header" }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = popup
  drag.ignored_by_interaction = true
  
  popup.add{ type = "line" }

  local body = popup.add{
    type = "frame",
    name = "wdp_smart_popup_body",
    direction = "vertical",
    style = "inside_shallow_frame"
  }
  body.style.top_padding = 10
  body.style.bottom_padding = 10
  body.style.left_padding = 10
  body.style.right_padding = 10

  local smart_enabled  = seg.smart and seg.smart.enabled == true
  local arith_b_enabled = smart_enabled and seg.smart.arithmetic_b and seg.smart.arithmetic_b.enabled == true
  local arith_a_enabled = arith_b_enabled and seg.smart.arithmetic_a and seg.smart.arithmetic_a.enabled == true

  local function make_row(name)
    local row = body.add{ type = "flow", name = name, direction = "horizontal" }
    row.style.vertical_align = "center"
    row.style.horizontal_spacing = 8
    row.style.top_margin = 4
    return row
  end
  
------------------------------------------------------------
  -- [enable/disable]
------------------------------------------------------------

  local enable_row = make_row("wdp_smart_enable_row")
  enable_row.add{
    type = "checkbox",
    name = "wdp_enable_smart_logic",
    caption = "Enable/disable",
    state = smart_enabled
  }
  local sep = body.add{ type = "line", direction = "horizontal" }
  sep.style.top_margin = 6
  sep.style.bottom_margin = 2

------------------------------------------------------------
  -- [decider]
------------------------------------------------------------
  
  local decider_row = make_row("wdp_smart_decider_group")
  local decider_check = decider_row.add{
    type = "checkbox", name = "wdp_smart_decider_check", caption = "",
    state = seg.smart and seg.smart.decider and seg.smart.decider.enabled == true
  }
  decider_check.enabled = smart_enabled
  local decider_btn = decider_row.add{
    type = "sprite-button", name = "wdp_smart_decider",
	style = "slot_button_in_shallow_frame", sprite = "item/decider-combinator",
    }
  decider_btn.style.width = 40
  decider_btn.style.height = 40
  decider_btn.enabled = smart_enabled and seg.smart.decider and seg.smart.decider.enabled == true
  
  local label = decider_row.add{
    type = "label",
    caption = "Decider logic",
	}
	
------------------------------------------------------------
  -- [arithmetic b]
------------------------------------------------------------
  
  local arith_b_row = make_row("wdp_smart_arithmetic_b_group")
  arith_b_row.style.top_margin = 8
  local arith_b_check = arith_b_row.add{
    type = "checkbox", name = "wdp_smart_arithmetic_b_check", caption = "",
    state = arith_b_enabled
  }
  arith_b_check.enabled = smart_enabled
  local arith_b_btn = arith_b_row.add{
    type = "sprite-button", name = "wdp_smart_arithmetic_b",
    style = "slot_button_in_shallow_frame", sprite = "item/arithmetic-combinator",
    }
  arith_b_btn.style.width = 40
  arith_b_btn.style.height = 40
  arith_b_btn.enabled = arith_b_enabled
  
  local label = arith_b_row.add{
    type = "label",
    caption = "Arithmetic logic",
	}
	
------------------------------------------------------------
  -- [up arrow]
------------------------------------------------------------
  
  local arrow_row = body.add{ type = "flow", direction = "horizontal" }
  arrow_row.style.horizontally_stretchable = true
  arrow_row.style.horizontal_align = "left"
  arrow_row.style.top_margin = 4
  arrow_row.style.bottom_margin = 2
  arrow_row.style.left_margin = 35
  arrow_row.add{ type = "label", caption = "↑" }
  
------------------------------------------------------------
  -- [arithmetic a]
------------------------------------------------------------

  local arith_a_row = make_row("wdp_smart_arithmetic_a_group")
  local arith_a_check = arith_a_row.add{
    type = "checkbox", name = "wdp_smart_arithmetic_a_check", caption = "",
    state = arith_a_enabled
  }
  arith_a_check.enabled = arith_b_enabled
  local arith_a_btn = arith_a_row.add{
    type = "sprite-button", name = "wdp_smart_arithmetic_a",
    style = "slot_button_in_shallow_frame", sprite = "item/arithmetic-combinator",
  }
  arith_a_btn.style.width = 40
  arith_a_btn.style.height = 40
  arith_a_btn.enabled = arith_a_enabled
  
    local label = arith_a_row.add{
    type = "label",
    caption = "Arithmetic logic",
	}
end

local function refresh_smart_popup(player, panel, seg, seg_idx)
  local popup = player.gui.screen.wdp_smart_popup
  if not (popup and popup.valid) then return end
  local loc = popup.location
  build_smart_popup(player, panel, seg, seg_idx)
  -- Restore position after rebuild
  local new_popup = player.gui.screen.wdp_smart_popup
  if new_popup and new_popup.valid and loc then
    new_popup.location = loc
  end
  -- Re-assert toggle button: build_smart_popup calls destroy_smart_popup which explicitly sets toggled = false: corrected it here.
  local main = player.gui.screen.wdp_main
  if main and main.valid and main.wdp_titlebar and main.wdp_titlebar.valid then
    local btn = main.wdp_titlebar.wdp_smart_toggle
    if btn and btn.valid then btn.toggled = true end
  end
end

local function smart_popup_is_open(player)
  local popup = player.gui.screen.wdp_smart_popup
  return popup and popup.valid
end

  ------------------------------------------------------------
  -- Rule rows
  ------------------------------------------------------------

local function build_rule_row(parent, panel, seg_idx, rule_idx, rule, merged_tbl, rule_count)
  local row = parent.add{
    type = "frame",
    name = "wdp_rule_" .. rule_idx,
    direction = "horizontal",
    style = "train_schedule_station_frame",
    tags = { rule_index = rule_idx, segment_index = seg_idx }
  }
  row.style.horizontally_stretchable = true
  row.style.top_padding = 3
  row.style.bottom_padding = 3
  row.style.left_padding = 6
  row.style.right_padding = 6
  row.style.bottom_margin = 4

  ------------------------------------------------------------
  -- [display icon]
  ------------------------------------------------------------
  
  local icon_pick = row.add{
    type = "choose-elem-button",
    name = "wdp_icon_signal",
	style = "train_schedule_item_select_button",
    elem_type = "signal",
    signal = clone_signal(rule.icon_signal)
  }
  icon_pick.style.width = 28
  icon_pick.style.height = 28
  icon_pick.style.minimal_width = 28
  icon_pick.style.minimal_height = 28
  icon_pick.style.maximal_width = 28
  icon_pick.style.maximal_height = 28

  ------------------------------------------------------------
  -- [message preview]
  ------------------------------------------------------------
  
  local preview = row.add{
    type = "label",
    name = "wdp_message_preview",
    caption = message_preview_text(rule.message)
  }
  preview.style.minimal_width = 53
  preview.style.maximal_width = 53
  preview.style.single_line = true
  preview.style.font_color = { 0.85, 0.85, 0.85 }

  ------------------------------------------------------------
  -- [edit message button]
  ------------------------------------------------------------
  
  local edit_btn = row.add{
    type = "sprite-button",
    style = "mini_button_aligned_to_text_vertically_when_centered",
    name = "wdp_gui_edit" .. rule_idx,
    sprite = "utility/rename_icon",
    tags = { rule_index = rule_idx, segment_index = seg_idx }
  }
  edit_btn.style.width = 17
  edit_btn.style.height = 17
  edit_btn.style.left_margin = -3

  ------------------------------------------------------------
  -- [space]
  ------------------------------------------------------------
  
  local gap1 = row.add{ type = "empty-widget" }
  gap1.style.width = 78
  gap1.style.height = 1

  ------------------------------------------------------------
  -- [first signal button]
  ------------------------------------------------------------
  
  local first_sig_count = rule.first_signal
    and format_si_compact(signal_value_from_table(merged_tbl, rule.first_signal))
    or nil
  local first_tooltip = first_sig_count
    and ("Current value: " .. first_sig_count)
    or "Choose condition signal"

  local first_pick = row.add{
    type = "choose-elem-button",
    name = "wdp_first_signal",
    style = "train_schedule_item_select_button",
    elem_type = "signal",
    signal = clone_signal(rule.first_signal),
    tooltip = first_tooltip,
  }
  first_pick.style.width = 28
  first_pick.style.height = 28
  first_pick.style.minimal_width = 28
  first_pick.style.minimal_height = 28
  first_pick.style.maximal_width = 28
  first_pick.style.maximal_height = 28

  ------------------------------------------------------------
  -- [comparator dropdown]
  ------------------------------------------------------------
  
  local dd = row.add{
    type = "drop-down",
    name = "wdp_comparator",
    style = "train_schedule_circuit_condition_comparator_dropdown"
  }
  dd.items = comparator_items()
  dd.selected_index = COMPARATOR_INDEX[rule.comparator] or 1
  dd.style.minimal_width = 41
  dd.style.height = 28

  ------------------------------------------------------------
  -- [rhs button]
  ------------------------------------------------------------
  
  if rule.rhs and rule.rhs.kind == "signal" and rule.rhs.signal then
    local rhs_sig_count = format_si_compact(signal_value_from_table(merged_tbl, rule.rhs.signal))
    local rhs_btn = row.add{
      type = "sprite-button",
      name = "wdp_rhs_open_" .. rule_idx,
      style = "train_schedule_item_select_button",
      sprite = sprite_path_from_signal(rule.rhs.signal),
      tooltip = "Current value: " .. rhs_sig_count .. "\nClick to change",
      tags = { rule_index = rule_idx, segment_index = seg_idx }
    }
    rhs_btn.style.width = 34
    rhs_btn.style.height = 34
    rhs_btn.style.minimal_width = 28
    rhs_btn.style.minimal_height = 28
    rhs_btn.style.maximal_width = 28
    rhs_btn.style.maximal_height = 28
  else
    local rhs_btn = row.add{
      type = "button",
      name = "wdp_rhs_open_" .. rule_idx,
      style = "train_schedule_item_select_button",
      caption = format_si_compact(rule.rhs and rule.rhs.constant),
      tooltip = "Constant value: " .. tostring(rule.rhs and rule.rhs.constant or 0) .. "\nClick to change",
      tags = { rule_index = rule_idx, segment_index = seg_idx }
    }
    rhs_btn.style.width = 28
    rhs_btn.style.height = 28
    rhs_btn.style.minimal_width = 28
    rhs_btn.style.minimal_height = 28
    rhs_btn.style.maximal_width = 28
    rhs_btn.style.maximal_height = 28
	rhs_btn.style.font = "default"
    rhs_btn.style.font_color = { 1, 1, 1 }
	rhs_btn.style.horizontal_align = "center"
  end

  ------------------------------------------------------------
  -- [space]
  ------------------------------------------------------------
  
  local gap2 = row.add{ type = "empty-widget" }
  gap2.style.width = 63
  gap2.style.height = 1

  ------------------------------------------------------------
  -- [up][down][delete]
  ------------------------------------------------------------
  
  local up = row.add{
    type = "sprite-button",
    name = "wdp_rule_up_" .. rule_idx,
    style = "frame_action_button",
    sprite = "wdp_gui_arrow_up",
    tooltip = "Move message up",
    tags = { rule_index = rule_idx, segment_index = seg_idx }
  }
  up.enabled = rule_idx > 1
  up.style.width = 28
  up.style.height = 28

  local down = row.add{
    type = "sprite-button",
    name = "wdp_rule_down_" .. rule_idx,
    style = "frame_action_button",
    sprite = "wdp_gui_arrow_down",
    tooltip = "Move message down",
    tags = { rule_index = rule_idx, segment_index = seg_idx }
  }
  down.enabled = rule_idx < rule_count
  down.style.width = 28
  down.style.height = 28

  local del = row.add{
    type = "sprite-button",
    name = "wdp_rule_delete_" .. rule_idx,
    style = "frame_action_button",
    sprite = "wdp_gui_remove",
    tooltip = "Delete message",
    tags = { rule_index = rule_idx, segment_index = seg_idx }
  }
  del.style.width = 28
  del.style.height = 28
end

rebuild_editor = function(frame, panel, player_index, merged_tbl)
  local body = frame.wdp_body
  if not (body and body.valid) then return end

  if body.wdp_editor and body.wdp_editor.valid then
    body.wdp_editor.destroy()
  end

  local seg, seg_idx = get_active_segment_config(panel, player_index)
  if not seg then return end

  -- Use the smart-effective signal table for the active segment so signal bar/tooltips show combinator output values, not raw panel input.
  local effective_tbl = merged_tbl
  if seg and seg.smart and seg.smart.enabled then
    effective_tbl = select(1, compute_smart_output_for_segment(panel, seg))
  end
  merged_tbl = effective_tbl

  local editor = body.add{
    type = "flow",
    name = "wdp_editor",
    direction = "vertical"
  }
  editor.style.horizontally_stretchable = true
  editor.style.top_margin = 4

  local list_frame = editor.add{
    type = "frame",
    name = "wdp_rule_list_frame",
    direction = "vertical",
    style = "deep_frame_in_shallow_frame"
  }
  list_frame.style.horizontally_stretchable = true
  list_frame.style.top_padding = 0
  list_frame.style.bottom_padding = 0
  list_frame.style.left_padding = 0
  list_frame.style.right_padding = 0
  list_frame.style.top_margin = 2
  list_frame.style.bottom_margin = 4

  local list = list_frame.add{
    type = "flow",
    name = "wdp_rule_list",
    direction = "vertical"
  }
  list.style.horizontally_stretchable = true
  list.style.vertical_spacing = 0

  for i = 1, #seg.rules do
    build_rule_row(list, panel, seg_idx, i, seg.rules[i], merged_tbl, #seg.rules)
  end

  local add_btn = list_frame.add{
    type = "button",
    name = "wdp_add_rule",
    caption = "Add new message"
  }
  add_btn.style.horizontally_stretchable = true
  add_btn.style.top_margin = 0
  add_btn.style.left_margin = 0
  add_btn.style.right_margin = 0
  add_btn.style.height = 28
end

apply_gui_to_segment = function(player)
  local frame = player.gui.screen.wdp_main
  if not (frame and frame.valid) then return end

  local state = get_gui_state(player.index)
  if not state then return end

  local panel = get_panel_from_gui_state(state)
  if not (panel and panel.valid) then return end

  ensure_panel_runtime(panel)

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return end

  local seg_idx = state.active_tab or 1
  local seg = pdata.segments[seg_idx]
  if not seg then return end

  local body = frame.wdp_body
  if not (body and body.valid and body.wdp_editor and body.wdp_editor.valid) then return end

  local settings_frame = nil
  if body.wdp_top_controls
    and body.wdp_top_controls.valid
    and body.wdp_top_controls.wdp_top_lower
    and body.wdp_top_controls.wdp_top_lower.valid
    and body.wdp_top_controls.wdp_top_lower.wdp_settings_frame
    and body.wdp_top_controls.wdp_top_lower.wdp_settings_frame.valid
  then
    settings_frame = body.wdp_top_controls.wdp_top_lower.wdp_settings_frame
  end

  if settings_frame
    and settings_frame.wdp_alt_row
    and settings_frame.wdp_alt_row.valid
    and settings_frame.wdp_alt_row.wdp_show_in_alt_mode
    and settings_frame.wdp_alt_row.wdp_show_in_alt_mode.valid
  then
    seg.show_in_alt_mode = (settings_frame.wdp_alt_row.wdp_show_in_alt_mode.state == true)
  end

  if settings_frame
    and settings_frame.wdp_chart_row
    and settings_frame.wdp_chart_row.valid
    and settings_frame.wdp_chart_row.wdp_show_in_chart
    and settings_frame.wdp_chart_row.wdp_show_in_chart.valid
  then
    local state_checked = (settings_frame.wdp_chart_row.wdp_show_in_chart.state == true)
    seg.show_in_chart = state_checked

    if state_checked then
      for i = 1, pdata.segment_count do
        if i ~= seg_idx and pdata.segments[i] then
          pdata.segments[i].show_in_chart = false
        end
      end
    end
  end

  local list_frame = body.wdp_editor.wdp_rule_list_frame
  if not (list_frame and list_frame.valid and list_frame.wdp_rule_list and list_frame.wdp_rule_list.valid) then return end

  local list = list_frame.wdp_rule_list
  if not (list and list.valid) then return end

  for _, child in ipairs(list.children) do
    if child and child.valid then
      local idx = tonumber(child.tags and child.tags.rule_index)
      if idx and seg.rules[idx] then
        local rule = seg.rules[idx]
        -- Rule controls now live directly on the row frame.
        local row = child

        if row.wdp_icon_signal and row.wdp_icon_signal.valid then
          rule.icon_signal = clone_signal(row.wdp_icon_signal.elem_value)
        end

        if row.wdp_first_signal and row.wdp_first_signal.valid then
          rule.first_signal = clone_signal(row.wdp_first_signal.elem_value)
        end

        if row.wdp_comparator and row.wdp_comparator.valid then
          local dd = row.wdp_comparator
          if dd.selected_index and COMPARATORS[dd.selected_index] then
            rule.comparator = COMPARATORS[dd.selected_index].key
          end
        end
      end
    end
  end

  persist_panel_config(panel)
  global.wdp.last_render_hash[panel.unit_number] = nil
  global.wdp.chart_tag_hash[panel.unit_number] = nil
end

refresh_main_gui = function(player)
  if not (player and player.valid) then return end

  local frame = player.gui.screen.wdp_main
  if not (frame and frame.valid) then return end

  local state = get_gui_state(player.index)
  if not state then return end

  local panel = get_panel_from_gui_state(state)
  if not (panel and panel.valid) then
    destroy_main_gui(player)
    return
  end

  ensure_panel_runtime(panel)
  local merged_tbl = compute_merged_for_panel(panel)
  local spec = PANEL_SPECS[panel.name]

  if frame.wdp_titlebar and frame.wdp_titlebar.valid and frame.wdp_titlebar.wdp_title and frame.wdp_titlebar.wdp_title.valid then
    frame.wdp_titlebar.wdp_title.caption = spec and spec.title or "Widescreen Display Panel"
  end

  if frame.wdp_body and frame.wdp_body.valid
      and frame.wdp_body.wdp_connected_holder
      and frame.wdp_body.wdp_connected_holder.valid then
    rebuild_connected_row(frame.wdp_body.wdp_connected_holder, panel)
  end

  if frame.wdp_body and frame.wdp_body.valid then
    rebuild_segment_tabs(frame, panel, player.index)
    rebuild_alt_row(frame.wdp_body, panel, player.index)
    rebuild_chart_row(frame.wdp_body, panel, player.index)
  end

  rebuild_editor(frame, panel, player.index, merged_tbl)
  rebuild_signal_bar(frame, panel, player.index)

  -- Re-assert smart toggle pressed state if popup is open.
  if frame.wdp_titlebar and frame.wdp_titlebar.valid then
    local btn = frame.wdp_titlebar.wdp_smart_toggle
    if btn and btn.valid then
      btn.toggled = smart_popup_is_open(player) == true
    end
  end
end

refresh_live_panel_preview = function(player, skip_gui_refresh)
  if not (player and player.valid) then return end

  local state = get_gui_state(player.index)
  if not state then return end

  local panel = get_panel_from_gui_state(state)
  if not (panel and panel.valid and panel.unit_number) then return end

  ensure_panel_runtime(panel)
  apply_gui_to_segment(player)
  persist_panel_config(panel)
  global.wdp.last_render_hash[panel.unit_number] = nil
  global.wdp.chart_tag_hash[panel.unit_number] = nil
  mirror_and_cache(panel.unit_number)

  if not skip_gui_refresh then
    refresh_main_gui(player)
  end
end

local function refresh_rhs_popup(player)
  local popup = player.gui.screen.wdp_rhs_popup
  if not (popup and popup.valid) then return end

  local state = get_gui_state(player.index)
  local panel = get_panel_from_gui_state(state)
  local rule = nil
  if panel and state then
    rule = get_rule_from_state(panel, state)
  end
  if not rule then
    destroy_rhs_popup(player)
    return
  end

  local content = popup.wdp_rhs_body
  if not (content and content.valid) then return end
  content.clear()

  local merged_tbl = compute_merged_for_panel(panel)

  local sig_row = content.add{ type = "flow", name = "wdp_rhs_signal_row", direction = "horizontal" }
  sig_row.style.horizontal_spacing = 8
  sig_row.style.vertical_align = "center"
  sig_row.add{ type = "label", caption = "Signal" }

  local sig_pick = sig_row.add{ type = "choose-elem-button", name = "wdp_rhs_signal_picker", elem_type = "signal", signal = clone_signal(rule.rhs.signal) }

  local sig_ok = sig_row.add{
    type = "sprite-button",
    style = "wdp_confirm_button",
    name = "wdp_rhs_signal_apply",
    sprite = "utility/confirm_slot",
    tooltip = "Use signal"
  }
  sig_ok.style.width = 28
  sig_ok.style.height = 28

  local sig_count = content.add{ type = "label", name = "wdp_rhs_signal_count", caption = rule.rhs.signal and ("Current count: " .. tostring(signal_value_from_table(merged_tbl, rule.rhs.signal))) or "" }
  sig_count.style.font = "default-small"
  sig_count.style.font_color = { 0.75, 0.75, 0.75 }
  sig_count.style.left_margin = 62
  sig_count.style.bottom_margin = 8

  content.add{ type = "line" }

  local const_row = content.add{ type = "flow", name = "wdp_rhs_constant_row", direction = "horizontal" }
  const_row.style.horizontal_spacing = 8
  const_row.style.vertical_align = "center"
  const_row.style.top_margin = 8
  const_row.add{ type = "label", caption = "Constant" }

  local tf = const_row.add{ type = "textfield", name = "wdp_rhs_constant_text", text = tostring(tonumber(rule.rhs.constant) or 0) }
  tf.style.width = 100

  local const_ok = const_row.add{
    type = "sprite-button",
    style = "wdp_confirm_button",
    name = "wdp_rhs_constant_apply",
    sprite = "utility/confirm_slot",
    tooltip = "Use constant"
  }
  const_ok.style.width = 28
  const_ok.style.height = 28
end

local function open_rhs_popup(player, seg_idx, rule_idx)
  destroy_rhs_popup(player)

  local state = get_gui_state(player.index)
  if not state then return end
  state.active_tab = seg_idx
  state.active_rule = rule_idx

  local popup = player.gui.screen.add{
    type = "frame",
    name = "wdp_rhs_popup",
    direction = "vertical"
  }
  popup.auto_center = true
  popup.style.width = 280

  local titlebar = popup.add{
    type = "flow",
    direction = "horizontal"
  }
  titlebar.drag_target = popup

  local title = titlebar.add{
    type = "label",
    caption = "Signal or constant",
    style = "frame_title"
  }
  title.drag_target = popup

  local drag = titlebar.add{
    type = "empty-widget",
    style = "draggable_space_header"
  }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = popup
  drag.ignored_by_interaction = true

  titlebar.add{
    type = "sprite-button",
    name = "wdp_rhs_close",
    style = "frame_action_button",
    sprite = "utility/close",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    tooltip = "Close (E or Escape)"
  }

  local body = popup.add{
    type = "frame",
    name = "wdp_rhs_body",
    direction = "vertical",
    style = "inside_shallow_frame"
  }
  body.style.top_padding = 8
  body.style.bottom_padding = 8
  body.style.left_padding = 10
  body.style.right_padding = 10

  refresh_rhs_popup(player)
end

local function refresh_rhs_popup(player)
  local popup = player.gui.screen.wdp_rhs_popup
  if not (popup and popup.valid) then return end

  local state = get_gui_state(player.index)
  local panel = get_panel_from_gui_state(state)
  local rule = nil
  if panel and state then
    rule = get_rule_from_state(panel, state)
  end
  if not rule then
    destroy_rhs_popup(player)
    return
  end

  local content = popup.wdp_rhs_body
  if not (content and content.valid) then return end
  content.clear()

  local merged_tbl = compute_merged_for_panel(panel)

  ------------------------------------------------------------
  -- Signal row
  ------------------------------------------------------------
  
  local sig_row = content.add{
    type = "flow",
    name = "wdp_rhs_signal_row",
    direction = "horizontal"
  }
  sig_row.style.horizontal_spacing = 6
  sig_row.style.vertical_align = "center"

  local sig_label = sig_row.add{
    type = "label",
    caption = "Signal"
  }
  sig_label.style.minimal_width = 52

  local sig_pick = sig_row.add{
    type = "choose-elem-button",
    name = "wdp_rhs_signal_picker",
    elem_type = "signal",
    signal = clone_signal(rule.rhs.signal)
  }
  sig_pick.style.width = 28
  sig_pick.style.height = 28

  local sig_ok = sig_row.add{
    type = "sprite-button",
    style = "wdp_confirm_button",
    name = "wdp_rhs_signal_apply",
    sprite = "utility/confirm_slot",
    tooltip = "Use signal"
  }
  sig_ok.style.width = 28
  sig_ok.style.height = 28

  local sig_count = content.add{
    type = "label",
    name = "wdp_rhs_signal_count",
    caption = rule.rhs.signal and ("Current count: " .. tostring(signal_value_from_table(merged_tbl, rule.rhs.signal))) or ""
  }
  sig_count.style.font = "default-small"
  sig_count.style.font_color = { 0.75, 0.75, 0.75 }
  sig_count.style.left_margin = 58
  sig_count.style.top_margin = 2
  sig_count.style.bottom_margin = 6

  ------------------------------------------------------------
  -- Constant row
  ------------------------------------------------------------
  
  local const_row = content.add{
    type = "flow",
    name = "wdp_rhs_constant_row",
    direction = "horizontal"
  }
  const_row.style.horizontal_spacing = 6
  const_row.style.vertical_align = "center"

  local const_label = const_row.add{
    type = "label",
    caption = "Constant"
  }
  const_label.style.minimal_width = 52

  local tf = const_row.add{
    type = "textfield",
    name = "wdp_rhs_constant_text",
    text = tostring(tonumber(rule.rhs.constant) or 0)
  }
  tf.style.width = 92

  local const_ok = const_row.add{
    type = "sprite-button",
    style = "wdp_confirm_button",
    name = "wdp_rhs_constant_apply",
    sprite = "utility/confirm_slot",
    tooltip = "Use constant"
  }
  const_ok.style.width = 28
  const_ok.style.height = 28
end

local function open_msg_icon_popup(player)
  destroy_msg_icon_popup(player)

  local anchor = nil
  local editor = player.gui.screen.wdp_msg_popup
  if editor
    and editor.valid
    and editor.wdp_msg_body
    and editor.wdp_msg_body.valid
    and editor.wdp_msg_body.wdp_msg_insert_row
    and editor.wdp_msg_body.wdp_msg_insert_row.valid
    and editor.wdp_msg_body.wdp_msg_insert_row.wdp_msg_icon_open
    and editor.wdp_msg_body.wdp_msg_insert_row.wdp_msg_icon_open.valid
  then
    anchor = editor.wdp_msg_body.wdp_msg_insert_row.wdp_msg_icon_open
  end

  local popup = player.gui.screen.add{
    type = "frame",
    name = "wdp_msg_icon_popup",
    direction = "vertical"
  }
  popup.style.width = 63
  popup.style.minimal_width = 63
  popup.style.maximal_width = 63

  local titlebar = popup.add{
    type = "flow",
    direction = "horizontal"
  }
  titlebar.drag_target = popup

  local drag = titlebar.add{
    type = "empty-widget",
    style = "draggable_space_header"
  }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = popup
  drag.ignored_by_interaction = true

  titlebar.add{
    type = "sprite-button",
    name = "wdp_msg_icon_close",
    style = "frame_action_button",
    sprite = "utility/close",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    tooltip = "Close (E or Escape)"
  }

  local body = popup.add{
    type = "frame",
    name = "wdp_msg_icon_body",
    direction = "vertical",
    style = "inside_shallow_frame"
  }
  body.style.top_padding = 6
  body.style.bottom_padding = 6
  body.style.left_padding = 6
  body.style.right_padding = 6

    local picker = body.add{
    type = "choose-elem-button",
    name = "wdp_msg_icon_picker",
    elem_type = "signal"
  }
  picker.style.width = 28
  picker.style.height = 28

  local editor = player.gui.screen.wdp_msg_popup
  if editor and editor.valid and editor.location then
    popup.location = {
      x = editor.location.x + 5,
      y = editor.location.y + 5
    }
  else
    popup.auto_center = true
  end
end

local function open_message_popup(player, seg_idx, rule_idx)
  destroy_message_popup(player)

  local state = get_gui_state(player.index)
  if not state then return end
  state.active_tab = seg_idx
  state.active_rule = rule_idx

  local panel = get_panel_from_gui_state(state)
  local rule = get_rule_from_state(panel, state)
  if not rule then return end

  local popup = player.gui.screen.add{
    type = "frame",
    name = "wdp_msg_popup",
    direction = "vertical"
  }
  popup.auto_center = true
  popup.style.width = 430

  local titlebar = popup.add{
    type = "flow",
    direction = "horizontal"
  }
  titlebar.drag_target = popup

  local title = titlebar.add{
    type = "label",
    caption = "Edit message",
    style = "frame_title"
  }
  title.drag_target = popup

  local drag = titlebar.add{
    type = "empty-widget",
    style = "draggable_space_header"
  }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = popup
  drag.ignored_by_interaction = true

  titlebar.add{
    type = "sprite-button",
    name = "wdp_msg_close",
    style = "frame_action_button",
    sprite = "utility/close",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    tooltip = "Close (E or Escape)"
  }

  local body = popup.add{
    type = "frame",
    name = "wdp_msg_body",
    direction = "vertical",
    style = "inside_shallow_frame"
  }
  body.style.top_padding = 8
  body.style.bottom_padding = 8
  body.style.left_padding = 10
  body.style.right_padding = 10

  local icon_row = body.add{
    type = "flow",
    name = "wdp_msg_insert_row",
    direction = "horizontal"
  }
  icon_row.style.horizontal_spacing = 6
  icon_row.style.bottom_margin = 6
  icon_row.style.vertical_align = "center"

  local open_btn = icon_row.add{
    type = "sprite-button",
    style = "choose_chat_icon_in_textbox_button",
    name = "wdp_msg_icon_open",
    sprite = "wdp_gui_insert",
    hovered_sprite = "wdp_gui_insert_hover",
    tooltip = "Insert icon"
  }
  open_btn.style.width = 26
  open_btn.style.height = 26
  
  local text = body.add{
    type = "text-box",
    name = "wdp_msg_text",
    text = rule.message or ""
  }
  text.style.width = 390
  text.style.height = 110

  local footer = popup.add{
    type = "flow",
    direction = "horizontal"
  }
  footer.style.top_margin = 6

  local footer_spacer = footer.add{ type = "empty-widget" }
  footer_spacer.style.horizontally_stretchable = true

  local ok_btn = footer.add{
    type = "sprite-button",
    style = "wdp_confirm_button",
    name = "wdp_msg_apply",
    sprite = "utility/confirm_slot",
    tooltip = "Apply message"
  }
  ok_btn.style.width = 28
  ok_btn.style.height = 28
end

local function apply_message_popup(player)
  local popup = player.gui.screen.wdp_msg_popup
  if not (popup and popup.valid and popup.wdp_msg_body and popup.wdp_msg_body.valid) then return end
  local box = popup.wdp_msg_body.wdp_msg_text
  if not (box and box.valid) then return end

  local state = get_gui_state(player.index)
  local panel = get_panel_from_gui_state(state)
  local rule = get_rule_from_state(panel, state)
  if not rule then return end

  rule.message = box.text or ""
  if panel then persist_panel_config(panel) end
end

local function open_panel_gui(player, panel)
  destroy_main_gui(player)
  ensure_global()
  ensure_panel_runtime(panel)

  global.wdp.gui[player.index] = {
    panel_unit = panel.unit_number,
    active_tab = 1,
    active_rule = nil,
  }

  local spec = PANEL_SPECS[panel.name]
  local frame = player.gui.screen.add{ type = "frame", name = "wdp_main", direction = "vertical" }
  frame.auto_center = true
  frame.style.width = 563

    local titlebar = frame.add{ type = "flow", name = "wdp_titlebar", direction = "horizontal" }
  titlebar.drag_target = frame

  local title = titlebar.add{
    type = "label",
    name = "wdp_title",
    caption = spec and spec.title or "Widescreen Display Panel",
    style = "frame_title"
  }
  title.drag_target = frame
  title.style.single_line = true

  local drag = titlebar.add{
    type = "empty-widget",
    name = "wdp_drag_handle",
    style = "draggable_space_header"
  }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = frame
  drag.ignored_by_interaction = true

  local smart_btn = titlebar.add{
    type = "sprite-button",
    name = "wdp_smart_toggle",
    style = "frame_action_button",
    sprite = "wdp_circuit_connection",
    hovered_sprite = "wdp_circuit_connection",
    clicked_sprite = "wdp_circuit_connection",
    tooltip = "Smartscreen logic"
  }
  smart_btn.style.size = 24

  local close_btn = titlebar.add{
    type = "sprite-button",
    name = "wdp_close",
    style = "frame_action_button",
    sprite = "utility/close",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    tooltip = "Close (E or Escape)"
  }

  frame.add{ type = "line" }

  local body = frame.add{
    type = "frame",
    name = "wdp_body",
    direction = "vertical",
    style = "inside_shallow_frame"
  }
  body.style.horizontally_stretchable = true
  body.style.top_padding = 0
  body.style.bottom_padding = 8
  body.style.left_padding = 10
  body.style.right_padding = 10

  local connected_holder = body.add{
    type = "frame",
    name = "wdp_connected_holder",
    direction = "vertical",
    style = "subheader_frame"
  }
  connected_holder.style.horizontally_stretchable = true
  connected_holder.style.top_padding = 0
  connected_holder.style.bottom_padding = 0
  connected_holder.style.left_padding = 6
  connected_holder.style.right_padding = 6
  connected_holder.style.top_margin = 0
  connected_holder.style.bottom_margin = 0
  connected_holder.style.left_margin = -10
  connected_holder.style.right_margin = -10

  refresh_main_gui(player)

  player.opened = frame
end

------------------------------------------------------------
-- GUI events
------------------------------------------------------------

script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type ~= defines.gui_type.entity then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  local ent = event.entity
  if not (ent and ent.valid) then return end

  if is_port(ent) then
    player.opened = nil
    return
  end

  if is_panel(ent) then
    open_panel_gui(player, ent)
  end
end)

script.on_event(defines.events.on_gui_location_changed, function(event)
  if not (event.element and event.element.valid) then return end
  if event.element.name ~= "wdp_main" then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local popup = player.gui.screen.wdp_smart_popup
  if not (popup and popup.valid) then return end
  local main = event.element
  popup.location = {
    x = main.location.x + 422,
    y = main.location.y
  }
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local el = event.element
  if not (el and el.valid) then return end

  local name = el.name

  if name == "wdp_icon_signal" or name == "wdp_first_signal" then
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    local state = get_gui_state(player.index)
    if not state then return end

    local panel = get_panel_from_gui_state(state)
    if not (panel and panel.valid) then return end

    local tags = event.element.tags or {}
    local seg_idx = tonumber(tags.segment_index)
    local rule_idx = tonumber(tags.rule_index)
    if not (seg_idx and rule_idx) then return end

    open_signal_picker(player, panel, seg_idx, rule_idx, name)
    return
  end

  if name == "wdp_signal_picker_close" or name == "wdp_signal_picker_clear" then
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    local state = get_gui_state(player.index)
    if not state or not state.signal_picker then
      destroy_signal_picker(player)
      return
    end

    if name == "wdp_signal_picker_clear" then
      local panel = get_panel_from_gui_state(state)
      if panel and panel.valid then
        local pdata = ensure_panel_segment_data(panel)
        if pdata then
          local sp = state.signal_picker
          local seg = pdata.segments[sp.segment_index]
          local rule = seg and seg.rules[sp.rule_index]
          if rule then
            rule[sp.field_name] = nil
            persist_panel_config(panel)
            global.wdp.last_render_hash[panel.unit_number] = nil
            global.wdp.chart_tag_hash[panel.unit_number] = nil
            refresh_live_panel_preview(player)
          end
        end
      end
    end

    destroy_signal_picker(player)
    return
  end

  if name == "wdp_close" then
    apply_gui_to_segment(player)
    destroy_smart_popup(player)
    destroy_main_gui(player)
    return
  end

  if name == "wdp_smart_toggle" then
    if smart_popup_is_open(player) then
      destroy_smart_popup(player)
    else
      local state = get_gui_state(player.index)
      local panel = get_panel_from_gui_state(state)
      if panel and panel.valid then
        local pdata = ensure_panel_segment_data(panel)
        local seg_idx = state and state.active_tab or 1
        local seg = pdata and pdata.segments and pdata.segments[seg_idx]
        if seg then
          build_smart_popup(player, panel, seg, seg_idx)
          -- Keep button in pressed state while popup is open
          local frame = player.gui.screen.wdp_main
          if frame and frame.valid and frame.wdp_titlebar and frame.wdp_titlebar.valid then
            local btn = frame.wdp_titlebar.wdp_smart_toggle
            if btn and btn.valid then btn.toggled = true end
          end
        end
      end
    end
    return
  end

  if name == "wdp_confirm" then
    apply_gui_to_segment(player)
    destroy_main_gui(player)
    return
  end
  
    if name == "wdp_smart_arithmetic_a"
      or name == "wdp_smart_arithmetic_b"
      or name == "wdp_smart_decider" then
    local state = get_gui_state(player.index)
    if not state then return end

    local panel = get_panel_from_gui_state(state)
    if not (panel and panel.valid) then return end

    local pdata = ensure_panel_segment_data(panel)
    if not pdata then return end

    local seg_idx = state.active_tab or 1
    local seg = pdata.segments[seg_idx]
    if not seg then return end

    local kind
    if name == "wdp_smart_arithmetic_a" then kind = "arithmetic_a"
    elseif name == "wdp_smart_arithmetic_b" then kind = "arithmetic_b"
    else kind = "decider" end

    local ref = get_segment_smart_ref(seg, kind)

    if not ref then return end

    local ent = get_registered_smart_combinator(ref)
    if ent and ent.valid then
      state.opening_smart_combinator = true
      player.opened = ent
    end
    return
  end

  if name == "wdp_rhs_close" then
    destroy_rhs_popup(player)
    return
  end

  if name == "wdp_msg_close" then
    destroy_message_popup(player)
    return
  end

  if name == "wdp_msg_icon_close" then
    destroy_msg_icon_popup(player)
    return
  end

  if name == "wdp_msg_icon_open" then
    open_msg_icon_popup(player)
    return
  end

  if name == "wdp_msg_apply" then
    apply_message_popup(player)
    refresh_live_panel_preview(player, true)
    destroy_message_popup(player)
    refresh_main_gui(player)
    return
  end

  if name == "wdp_copy_segment" then
    copy_active_segment(player)
    refresh_main_gui(player)
    return
  end

  if name == "wdp_paste_segment" then
    paste_active_segment(player)
    return
  end


  if name == "wdp_add_rule" then
    local state = get_gui_state(player.index)
    local panel = get_panel_from_gui_state(state)
    if not panel then return end
    apply_gui_to_segment(player)
    local seg = get_active_segment_config(panel, player.index)
    if not seg then return end
    add_rule(seg)
    refresh_main_gui(player)
    return
  end

  local tab_idx = name:match("^wdp_tab(%d+)$")
  if tab_idx then
    local state = get_gui_state(player.index)
    if not state then return end
    apply_gui_to_segment(player)
    state.active_tab = tonumber(tab_idx) or 1
    state.active_rule = nil
    destroy_rhs_popup(player)
    destroy_message_popup(player)
    refresh_main_gui(player)
    -- Refresh smart popup for the new segment if open
    if smart_popup_is_open(player) then
      local panel = get_panel_from_gui_state(state)
      if panel and panel.valid then
        local pdata = ensure_panel_segment_data(panel)
        local seg_idx = state.active_tab
        local seg = pdata and pdata.segments and pdata.segments[seg_idx]
        if seg then refresh_smart_popup(player, panel, seg, seg_idx) end
      end
    end
    return
  end

  local open_idx = name:match("^wdp_rhs_open_(%d+)$")
  if open_idx then
    local state = get_gui_state(player.index)
    local panel = get_panel_from_gui_state(state)
    if not panel then return end
    apply_gui_to_segment(player)
    open_rhs_popup(player, state.active_tab or 1, tonumber(open_idx))
    return
  end

  local msg_idx = name:match("^wdp_gui_edit(%d+)$")
  if msg_idx then
    local state = get_gui_state(player.index)
    local panel = get_panel_from_gui_state(state)
    if not panel then return end
    apply_gui_to_segment(player)
    open_message_popup(player, state.active_tab or 1, tonumber(msg_idx))
    return
  end

  local up_idx = name:match("^wdp_rule_up_(%d+)$")
  if up_idx then
    local state = get_gui_state(player.index)
    local panel = get_panel_from_gui_state(state)
    if not panel then return end
    apply_gui_to_segment(player)
    local seg = get_active_segment_config(panel, player.index)
    if not seg then return end
    state.active_rule = move_rule_up(seg, tonumber(up_idx))
    refresh_main_gui(player)
    return
  end

  local down_idx = name:match("^wdp_rule_down_(%d+)$")
  if down_idx then
    local state = get_gui_state(player.index)
    local panel = get_panel_from_gui_state(state)
    if not panel then return end
    apply_gui_to_segment(player)
    local seg = get_active_segment_config(panel, player.index)
    if not seg then return end
    state.active_rule = move_rule_down(seg, tonumber(down_idx))
    refresh_main_gui(player)
    return
  end

  local del_idx = name:match("^wdp_rule_delete_(%d+)$")
  if del_idx then
    local state = get_gui_state(player.index)
    local panel = get_panel_from_gui_state(state)
    if not panel then return end
    apply_gui_to_segment(player)
    local seg = get_active_segment_config(panel, player.index)
    if not seg then return end
    state.active_rule = remove_rule(seg, tonumber(del_idx))
    refresh_main_gui(player)
    return
  end

  if name == "wdp_rhs_signal_apply" then
    local state = get_gui_state(player.index)
    local panel = get_panel_from_gui_state(state)
    local rule = get_rule_from_state(panel, state)
    if not rule then return end

    local popup = player.gui.screen.wdp_rhs_popup
    if not (popup and popup.valid and popup.wdp_rhs_body and popup.wdp_rhs_body.valid) then return end
    local row = popup.wdp_rhs_body.wdp_rhs_signal_row
    if not (row and row.valid and row.wdp_rhs_signal_picker and row.wdp_rhs_signal_picker.valid) then return end
    local picker = row.wdp_rhs_signal_picker
    if not picker.elem_value then return end

    rule.rhs.kind = "signal"
    rule.rhs.signal = clone_signal(picker.elem_value)
    if panel then persist_panel_config(panel) end

    destroy_rhs_popup(player)
    refresh_main_gui(player)
    return
  end

  if name == "wdp_rhs_constant_apply" then
    local state = get_gui_state(player.index)
    local panel = get_panel_from_gui_state(state)
    local rule = get_rule_from_state(panel, state)
    if not rule then return end

    local popup = player.gui.screen.wdp_rhs_popup
    if not (popup and popup.valid and popup.wdp_rhs_body and popup.wdp_rhs_body.valid) then return end
    local row = popup.wdp_rhs_body.wdp_rhs_constant_row
    if not (row and row.valid and row.wdp_rhs_constant_text and row.wdp_rhs_constant_text.valid) then return end
    local tf = row.wdp_rhs_constant_text

    local n = safe_number_text(tf.text)
    if n == nil then return end

    rule.rhs.kind = "constant"
    rule.rhs.constant = n
    if panel then persist_panel_config(panel) end

    destroy_rhs_popup(player)
    refresh_main_gui(player)
    return
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local el = event.element
  if not (el and el.valid) then return end

  if el.name == "wdp_rhs_signal_picker" then
    local popup = player.gui.screen.wdp_rhs_popup
    if not (popup and popup.valid and popup.wdp_rhs_body and popup.wdp_rhs_body.valid) then return end

    local row = popup.wdp_rhs_body.wdp_rhs_signal_row
    if row and row.valid and row.wdp_rhs_signal_apply and row.wdp_rhs_signal_apply.valid then
      row.wdp_rhs_signal_apply.enabled = el.elem_value ~= nil
    end

    local lbl = popup.wdp_rhs_body.wdp_rhs_signal_count
    if lbl and lbl.valid then
      local state = get_gui_state(player.index)
      local panel = get_panel_from_gui_state(state)

      if el.elem_value and panel then
        local merged_tbl = compute_merged_for_panel(panel)
        lbl.caption = "Current count: " .. tostring(signal_value_from_table(merged_tbl, el.elem_value))
      else
        lbl.caption = ""
      end
    end
    return
  end

  if el.name == "wdp_msg_icon_picker" then
    local token = rich_text_token_for_signal(el.elem_value)
    local popup = player.gui.screen.wdp_msg_popup
    if token and popup and popup.valid and popup.wdp_msg_body and popup.wdp_msg_body.valid and popup.wdp_msg_body.wdp_msg_text and popup.wdp_msg_body.wdp_msg_text.valid then
      local box = popup.wdp_msg_body.wdp_msg_text
      local existing = box.text or ""
      box.text = existing .. token
      apply_message_popup(player)
      refresh_live_panel_preview(player, true)
    end
    destroy_msg_icon_popup(player)
    return
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local el = event.element
  if not (el and el.valid) then return end

  local name = el.name

  if name == "wdp_show_in_chart" or name == "wdp_show_in_alt_mode" then
    apply_gui_to_segment(player)
    refresh_live_panel_preview(player)
    refresh_main_gui(player)
    return
  end

  if name ~= "wdp_enable_smart_logic"
    and name ~= "wdp_smart_arithmetic_a_check"
    and name ~= "wdp_smart_arithmetic_b_check"
    and name ~= "wdp_smart_decider_check"
  then
    return
  end

  local state = get_gui_state(player.index)
  if not state then return end

  local panel = get_panel_from_gui_state(state)
  if not (panel and panel.valid) then return end

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return end

  local seg_idx = state.active_tab or 1
  local seg = pdata.segments[seg_idx]
  if not seg then return end

  if name == "wdp_enable_smart_logic" then
    seg.smart.enabled = (el.state == true)

    if not seg.smart.enabled then
      seg.smart.arithmetic_a.enabled = false
      seg.smart.arithmetic_b.enabled = false
      seg.smart.decider.enabled = false
      destroy_segment_smart_combinator(seg, "arithmetic_a")
      destroy_segment_smart_combinator(seg, "arithmetic_b")
      destroy_segment_smart_combinator(seg, "decider")
    end

    persist_panel_config(panel)
    refresh_main_gui(player)
    -- Refresh popup if open
    if smart_popup_is_open(player) then
      refresh_smart_popup(player, panel, seg, seg_idx)
    end
    return
  end

  if name == "wdp_smart_arithmetic_a_check"
      or name == "wdp_smart_arithmetic_b_check"
      or name == "wdp_smart_decider_check" then
    local kind
    if name == "wdp_smart_arithmetic_a_check" then kind = "arithmetic_a"
    elseif name == "wdp_smart_arithmetic_b_check" then kind = "arithmetic_b"
    else kind = "decider" end

    local enabled = (el.state == true)

    if not seg.smart.enabled and enabled then
      seg.smart.enabled = true
    end

    seg.smart[kind].enabled = enabled

    -- When arithmetic_b is unchecked, also disable arithmetic_a since it has no path to the segment without arithmetic_b. 
    if kind == "arithmetic_b" and not enabled then
      seg.smart.arithmetic_a.enabled = false
      local ref_a = get_segment_smart_ref(seg, "arithmetic_a")
      local ent_a = ref_a and get_registered_smart_combinator(ref_a) or nil
      if ent_a and ent_a.valid then ent_a.active = false end
    end

    -- Create entity if first enable; leave alive on disable to preserve config.
    local ref = get_segment_smart_ref(seg, kind)
    local ent = ref and get_registered_smart_combinator(ref) or nil
    if not ent then
      ent = create_smart_combinator(panel, seg_idx, kind)
      if ent and ent.valid then
        set_segment_smart_ref(seg, kind, ent.unit_number)
      end
    end

    if ent and ent.valid then
      ent.active = enabled
    end

    persist_panel_config(panel)
    refresh_main_gui(player)
    if smart_popup_is_open(player) then
      refresh_smart_popup(player, panel, seg, seg_idx)
    end
    return
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local state = get_gui_state(player.index)

  -- A smart combinator GUI was closed while wdp_main is still open.
  -- Re-focus the main panel GUI so the player isn't left with nothing.
  if event.entity and event.entity.valid
      and (event.entity.name == "wdp-smart-arithmetic"
           or event.entity.name == "wdp-smart-decider")
  then
    if state then
      state.opening_smart_combinator = nil
      local panel = get_panel_from_gui_state(state)
      if panel and panel.valid then
        local frame = player.gui.screen.wdp_main
        if frame and frame.valid then
          player.opened = frame
        end
      end
    end
    return
  end

  if event.element and event.element.valid then
    if event.element.name == "wdp_rhs_popup" then
      destroy_rhs_popup(player)
      return
    end

    if event.element.name == "wdp_smart_popup" then
      destroy_smart_popup(player)
      return
    end

    if event.element.name == "wdp_msg_icon_popup" then
      destroy_msg_icon_popup(player)
      return
    end

    if event.element.name == "wdp_msg_popup" then
      destroy_message_popup(player)
      return
    end

    if event.element.name == "wdp_main" then
      -- If in the middle of opening a smart combinator, main GUI close is triggered by Factorio swapping player.opened, don't destroy it.
      if state and state.opening_smart_combinator then
        return
      end

      apply_gui_to_segment(player)
      refresh_live_panel_preview(player)
      destroy_main_gui(player)
      return
    end
  end
end)

script.on_event(defines.events.on_selected_entity_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  update_hover_render_for_player(player)
end)

------------------------------------------------------------
-- Scan / build / remove / rotation stop
------------------------------------------------------------

local function panel_names_list()
  local names = {}

  local entity_prototypes = prototypes and prototypes.entity

  for name, _ in pairs(PANEL_SPECS) do
    if not entity_prototypes or entity_prototypes[name] then
      names[#names + 1] = name
    end
  end

  return names
end

local function scan_all_existing()
  ensure_global()
  local names = panel_names_list()

  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered { name = names }) do
      if e.direction ~= defines.direction.north then
        e.direction = defines.direction.north
      end
      ensure_panel_runtime(e)
      mirror_and_cache(e.unit_number)
    end
  end
end

local function on_built(event)
  local ent = event.created_entity or event.entity or event.destination
  if is_panel(ent) then
    if ent.direction ~= defines.direction.north then
      ent.direction = defines.direction.north
    end
    attach_ports(ent)
    mirror_and_cache(ent.unit_number)
  end
end

local function on_pre_removed(event)
  local ent = event.entity
  if not is_panel(ent) then return end

  local unit_number = ent.unit_number

  -- Destroy port before mining completes (entity.destroy() called from on_player_mined_entity can silently fail in Factorio 2.0).
  local ports = global.wdp.ports and global.wdp.ports[unit_number]
  if ports and ports.output and ports.output.valid then
    ports.output.destroy()
  end

  if ent.valid then
    destroy_ports_for_removed_panel(ent)
  end
end

local function on_removed(event)
  local ent = event.entity
  if not is_panel(ent) then return end
  detach_ports_by_unit(ent.unit_number)
end

script.on_init(function()
  get_or_create_hidden_surface()
  scan_all_existing()
end)

script.on_configuration_changed(function(_event)
  scan_all_existing()
end)

script.on_event(defines.events.on_pre_player_mined_item,   on_pre_removed)
script.on_event(defines.events.on_robot_pre_mined,         on_pre_removed)
script.on_event(defines.events.on_space_platform_pre_mined, on_pre_removed)

script.on_event(defines.events.on_built_entity,       on_built)
script.on_event(defines.events.on_robot_built_entity, on_built)
script.on_event(defines.events.script_raised_built,   on_built)
script.on_event(defines.events.script_raised_revive,  on_built)

script.on_event(defines.events.on_player_mined_entity,        on_removed)
script.on_event(defines.events.on_robot_mined_entity,         on_removed)
script.on_event(defines.events.on_space_platform_mined_entity, on_removed)
script.on_event(defines.events.on_entity_died,                on_removed)
script.on_event(defines.events.script_raised_destroy,         on_removed)

script.on_event(defines.events.on_player_rotated_entity, function(event)
  local ent = event.entity
  if is_panel(ent) then
    ent.direction = defines.direction.north
    attach_ports(ent)
    mirror_and_cache(ent.unit_number)
  end
end)

script.on_nth_tick(2, tick_merge)

------------------------------------------------------------
-- Native settings copy/paste  (Ctrl-C pipette → Ctrl-V)
------------------------------------------------------------

-- on_pre_entity_settings_pasted fires when the player picks
-- up settings from a source entity (Ctrl-C with the tool).
-- Use it to capture the panel state and play a sound so
-- the player gets feedback, matching vanilla combinator feel.

script.on_event(defines.events.on_pre_entity_settings_pasted, function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local src = event.entity
  if not is_panel(src) then return end

  copy_panel(player, src)

  -- Audio cue: same sound vanilla uses for entity copy.
  player.play_sound{ path = "utility/copied" }
end)

-- on_entity_settings_pasted fires when the player pastes onto a destination entity (Ctrl-V with the tool).
script.on_event(defines.events.on_entity_settings_pasted, function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local src = event.source
  local dst = event.destination

  -- Both entities must be widescreen display panels.
  if not (is_panel(src) and is_panel(dst)) then return end

  -- paste_panel with a live source rebuilds the clip from the source entity, ensuring the freshest state is captured. 
  paste_panel(player, src, dst)
end)

------------------------------------------------------------
-- Remote interface for DSC/Signal Display
------------------------------------------------------------

remote.add_interface("WidescreenDisplayPanels", {
  get_merged_signals = function(entity)
    ensure_global()
    if not (entity and entity.valid and entity.unit_number) then return {} end

    ensure_panel_runtime(entity)

    local _merged_tbl, merged_arr = compute_merged_for_panel(entity)
    global.wdp.cache[entity.unit_number] = merged_arr
    return merged_arr or {}
  end,

  get_segment_templates = function(entity)
    ensure_global()
    if not (entity and entity.valid and entity.unit_number) then return {} end

    ensure_panel_runtime(entity)

    local pdata = ensure_panel_segment_data(entity)
    if not pdata then return {} end

    local out = {}

    for seg_idx = 1, pdata.segment_count do
      local seg = pdata.segments[seg_idx]
      out[seg_idx] = {}

      if seg and seg.rules then
        for rule_idx = 1, #seg.rules do
          local rule = seg.rules[rule_idx]
          out[seg_idx][rule_idx] = {
            message = rule.message or "",
            first_signal = clone_signal(rule.first_signal),
            icon_signal = clone_signal(rule.icon_signal),
            rhs = rule.rhs and {
              kind = rule.rhs.kind,
              constant = rule.rhs.constant,
              signal = clone_signal(rule.rhs.signal),
            } or nil,
            comparator = rule.comparator or ">",
          }
        end
      end
    end

    return out
  end,

  set_rule_message = function(entity, seg_idx, rule_idx, text)
    ensure_global()
    if not (entity and entity.valid and entity.unit_number) then return false end

    ensure_panel_runtime(entity)

    local pdata = ensure_panel_segment_data(entity)
    if not pdata then return false end

    seg_idx = tonumber(seg_idx)
    rule_idx = tonumber(rule_idx)
    if not seg_idx or not rule_idx then return false end

    local seg = pdata.segments[seg_idx]
    if not seg or not seg.rules or not seg.rules[rule_idx] then return false end

    seg.rules[rule_idx].message = text or ""

    persist_panel_config(entity)
    global.wdp.last_render_hash[entity.unit_number] = nil
    global.wdp.chart_tag_hash[entity.unit_number] = nil
    mirror_and_cache(entity.unit_number)

    return true
  end,
})