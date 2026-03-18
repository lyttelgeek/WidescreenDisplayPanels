local PANEL_SPECS = {
  ["widescreen-display-panel-2x1"] = { tiles_w = 2, segments = 2, port_suffix = "2x1", title = "Widescreen Display Panel 2x1" },
  ["widescreen-display-panel-3x1"] = { tiles_w = 3, segments = 3, port_suffix = "3x1", title = "Widescreen Display Panel 3x1" },
  ["widescreen-display-panel-4x1"] = { tiles_w = 4, segments = 4, port_suffix = "4x1", title = "Widescreen Display Panel 4x1" },
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

local DEBUG = false
local function dlog(msg) if DEBUG then log("WDP: " .. msg) end end
local function px_to_tiles(px) return px / 32 end

local function port_right_name_for(panel_name)
  local spec = PANEL_SPECS[panel_name]
  if not spec then return nil end
  return "widescreen-display-panel-connector-right-" .. spec.port_suffix
end

local PORT_NAME_SET = {}
for _, spec in pairs(PANEL_SPECS) do
  PORT_NAME_SET["widescreen-display-panel-connector-right-" .. spec.port_suffix] = true
end

--[[
  Runtime responsibilities:
  - Attach and maintain helper connector entities for widescreen panels
  - Merge panel circuit-network signals and mirror them to the hidden helper port
  - Evaluate per-segment rule stacks and render icon/message output
  - Provide chart-tag, hover-preview, and GUI editing behaviour
  - Expose merged signals for Display Signal Counts compatibility
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
end

------------------------------------------------------------
-- Entity / panel helpers
------------------------------------------------------------

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

local function normalize_signal(sig)
  if not sig then return nil end
  local t = normalize_signal_type_internal(sig.type)
  if not sig.name then return nil end
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

local function expected_right_port_position(panel)
  local spec = PANEL_SPECS[panel.name]
  if not spec then return nil end

  local p = panel.position
  local half_width_px = (spec.tiles_w * 32) / 2
  local end_x_px = (half_width_px - CAP_INSET_PX) + PORT_X_OUTSET_PX

  local y_px = BASELINE_PX + MAIN_SHIFT_PY
  local dx_right = end_x_px + MAIN_SHIFT_PX

  return {
    x = p.x + px_to_tiles(dx_right),
    y = p.y + px_to_tiles(y_px),
  }
end

local function destroy_right_ports_at_expected_pos(panel)
  if not (panel and panel.valid) then return end

  local rname = port_right_name_for(panel.name)
  local pos = expected_right_port_position(panel)
  if not rname or not pos then return end

  local eps_x = 0.30
  local eps_y = 0.30

  local found = panel.surface.find_entities_filtered{
    area = {
      { pos.x - eps_x, pos.y - eps_y },
      { pos.x + eps_x, pos.y + eps_y },
    },
    name = rname,
    force = panel.force,
  }

  for i = 1, #found do
    local e = found[i]
    if e and e.valid then e.destroy() end
  end
end

local function destroy_right_ports_for_removed_panel(panel)
  if not (panel and panel.valid) then return end

  local spec = PANEL_SPECS[panel.name]
  local rname = port_right_name_for(panel.name)
  if not spec or not rname then return end

  local half_w = spec.tiles_w / 2
  local area = {
    { panel.position.x,                 panel.position.y - 1.5 },
    { panel.position.x + half_w + 1.5, panel.position.y + 1.5 },
  }

  local found = panel.surface.find_entities_filtered{
    area = area,
    name = rname,
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

local function detach_ports_by_unit(unit_number, keep_settings)
  ensure_global()

  local ports = global.wdp.ports[unit_number]
  if ports then
    destroy_if_valid(ports.right)
    global.wdp.ports[unit_number] = nil
  end

  clear_all_panel_render(unit_number)
  clear_panel_chart_tag(unit_number)

  global.wdp.panels[unit_number] = nil
  global.wdp.cache[unit_number] = nil
  global.wdp.last_output_hash[unit_number] = nil

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

  local rname = port_right_name_for(panel.name)
  if not rname then return nil end

  local pos = expected_right_port_position(panel)
  if not pos then return nil end

  local right = panel.surface.create_entity{
    name = rname,
    position = pos,
    force = panel.force,
    create_build_effect_smoke = false,
    raise_built = false,
  }

  if not (right and right.valid) then
    destroy_if_valid(right)
    return nil
  end

  return { right = right }
end

local function attach_ports(panel)
  if not is_panel(panel) or not panel.unit_number then return end

  ensure_global()

  local unit = panel.unit_number
  local old_ports = global.wdp.ports[unit]

  if old_ports then
    destroy_if_valid(old_ports.right)
    global.wdp.ports[unit] = nil
  end

  destroy_right_ports_at_expected_pos(panel)

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
  if not ports or not ports.right or not ports.right.valid then
    attach_ports(panel)
    return true
  end

  return true
end

------------------------------------------------------------
-- Signal helpers
------------------------------------------------------------

local function add_signals(dst, sigs)
  if not sigs then return end
  for _, s in ipairs(sigs) do
    if s.signal and s.signal.name and s.signal.type then
      local stype = normalize_signal_type_internal(s.signal.type)
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
  if not sig or not sig.name or not sig.type then return nil end
  return normalize_signal_type_internal(sig.type) .. ":" .. sig.name .. ":" .. (sig.quality or "normal")
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

local function sprite_path_from_signal(sig)
  if not sig or not sig.type or not sig.name then return nil end
  local t = normalize_signal_type_internal(sig.type)
  if t == "virtual" then
    t = "virtual-signal"
  end
  return t .. "/" .. sig.name
end

local function rich_text_token_for_signal(sig)
  if not sig or not sig.name or not sig.type then return nil end

  local t = normalize_signal_type_internal(sig.type)
  local path = nil

  if t == "virtual" then
    path = "virtual-signal/" .. sig.name
  elseif t == "item" then
    path = "item/" .. sig.name
  elseif t == "fluid" then
    path = "fluid/" .. sig.name
  else
    return nil
  end

  return "[img=" .. path .. "]"
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

local function make_render_hash(seg_cfg, merged_tbl)
  local match = evaluate_segment_rules(seg_cfg, merged_tbl)
  if not match then return "hidden" end

  local rule = match.rule
  local rhs_sig_key = signal_key_from_signal(rule.rhs and rule.rhs.signal) or "nil"
  local icon_key = signal_key_from_signal(rule.icon_signal) or "nil"
  local first_key = signal_key_from_signal(rule.first_signal) or "nil"

  return table.concat({
    "rule=" .. tostring(match.rule_index),
    "lhs=" .. tostring(match.lhs_value),
    "rhs=" .. tostring(match.rhs_value),
    "rhs_kind=" .. tostring(rule.rhs and rule.rhs.kind or "constant"),
    "rhs_sig=" .. rhs_sig_key,
    "icon=" .. icon_key,
    "first=" .. first_key,
    "op=" .. tostring(rule.comparator or ">"),
    "msg=" .. tostring(rule.message or ""),
    "alt=" .. tostring(seg_cfg and seg_cfg.show_in_alt_mode == true),
  }, "|")
end

local function get_panel_networks(panel)
  local networks = {}
  local ids = {}

  local behavior = panel.get_or_create_control_behavior()
  if behavior then
    local ok_r, net_r = pcall(function()
      return behavior.get_circuit_network(defines.wire_connector_id.circuit_red)
    end)
    if ok_r and net_r and net_r.valid and net_r.network_id ~= nil and not ids[net_r.network_id] then
      ids[net_r.network_id] = true
      networks[#networks + 1] = net_r
    end

    local ok_g, net_g = pcall(function()
      return behavior.get_circuit_network(defines.wire_connector_id.circuit_green)
    end)
    if ok_g and net_g and net_g.valid and net_g.network_id ~= nil and not ids[net_g.network_id] then
      ids[net_g.network_id] = true
      networks[#networks + 1] = net_g
    end
  end

  local ok_er, ent_r = pcall(function()
    return panel.get_circuit_network(defines.wire_connector_id.circuit_red)
  end)
  if ok_er and ent_r and ent_r.valid and ent_r.network_id ~= nil and not ids[ent_r.network_id] then
    ids[ent_r.network_id] = true
    networks[#networks + 1] = ent_r
  end

  local ok_eg, ent_g = pcall(function()
    return panel.get_circuit_network(defines.wire_connector_id.circuit_green)
  end)
  if ok_eg and ent_g and ent_g.valid and ent_g.network_id ~= nil and not ids[ent_g.network_id] then
    ids[ent_g.network_id] = true
    networks[#networks + 1] = ent_g
  end

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

local function compute_merged_for_panel(panel)
  if not (panel and panel.valid and panel.unit_number) then
    return {}, {}
  end

  local networks = get_panel_networks(panel)
  local merged_tbl = read_networks_to_table(networks)
  local merged_arr = table_to_signal_array(merged_tbl)

  return merged_tbl, merged_arr
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
  local red_id = nil
  local green_id = nil

  local behavior = panel.get_or_create_control_behavior()
  if behavior then
    local ok_r, net_r = pcall(function()
      return behavior.get_circuit_network(defines.wire_connector_id.circuit_red)
    end)
    if ok_r and net_r and net_r.valid and net_r.network_id ~= nil then
      red_id = net_r.network_id
    end

    local ok_g, net_g = pcall(function()
      return behavior.get_circuit_network(defines.wire_connector_id.circuit_green)
    end)
    if ok_g and net_g and net_g.valid and net_g.network_id ~= nil then
      green_id = net_g.network_id
    end
  end

  local ok_er, ent_r = pcall(function()
    return panel.get_circuit_network(defines.wire_connector_id.circuit_red)
  end)
  if ok_er and ent_r and ent_r.valid and ent_r.network_id ~= nil and red_id == nil then
    red_id = ent_r.network_id
  end

  local ok_eg, ent_g = pcall(function()
    return panel.get_circuit_network(defines.wire_connector_id.circuit_green)
  end)
  if ok_eg and ent_g and ent_g.valid and ent_g.network_id ~= nil and green_id == nil then
    green_id = ent_g.network_id
  end

  return red_id, green_id
end

local function message_preview_text(message)
  local msg = message or ""
  msg = string.gsub(msg, string.char(13), " ")
  msg = string.gsub(msg, string.char(10), " ")

  if msg == "" then
    return "(no message)"
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

local function render_segment(panel, panel_unit, seg_idx, seg_cfg, merged_tbl, segment_count)
  local bucket, hash_bucket = ensure_render_bucket(panel_unit)

  local new_hash = make_render_hash(seg_cfg or {}, merged_tbl)
  local old_hash = hash_bucket[seg_idx]

  if new_hash == old_hash then return end

  clear_segment_render(panel_unit, seg_idx)

  local match = evaluate_segment_rules(seg_cfg, merged_tbl)
  if not match then
    hash_bucket[seg_idx] = new_hash
    return
  end

  local offsets = segment_offsets_for_count(segment_count)
  local adjusts = segment_render_adjust_for_count(segment_count)
  if not offsets or not offsets[seg_idx] then
    hash_bucket[seg_idx] = new_hash
    return
  end

  local render_x = offsets[seg_idx] + ((adjusts and adjusts[seg_idx]) or 0)
  local rule = match.rule
  local sprite = sprite_path_from_signal(rule.icon_signal)
  local message = rule.message or ""
  local always_visible_message = (seg_cfg and seg_cfg.show_in_alt_mode == true)

  local seg_bucket = {}

  -- Display icon is always shown when the rule condition passes.
  if sprite then
    local obj = rendering.draw_sprite{
      sprite = sprite,
      surface = panel.surface,
      target = { entity = panel, offset = { render_x, ICON_Y_OFFSET } },
      x_scale = ICON_SCALE,
      y_scale = ICON_SCALE,
      forces = panel.force,
    }
    seg_bucket.icon = obj and obj.id or nil
  end

  -- Message backer/text obey the checkbox.
  if always_visible_message and BACKER_ENABLED and message ~= "" then
    local width = estimated_backer_width_for_message(message)
    local half_width = width / 2
    local rect = rendering.draw_rectangle{
      color = BACKER_COLOR,
      filled = true,
      surface = panel.surface,
      left_top = { entity = panel, offset = { render_x - half_width, BACKER_Y_OFFSET - BACKER_HALF_HEIGHT } },
      right_bottom = { entity = panel, offset = { render_x + half_width, BACKER_Y_OFFSET + BACKER_HALF_HEIGHT } },
      forces = panel.force,
    }
    seg_bucket.backer = rect and rect.id or nil
  end

  if always_visible_message and message ~= "" then
    local txt = rendering.draw_text{
      text = message,
      surface = panel.surface,
      target = { entity = panel, offset = { render_x, TEXT_Y_OFFSET } },
      color = {1, 1, 1},
      scale = TEXT_SCALE,
      scale_with_zoom = true,
      alignment = "center",
      vertical_alignment = "middle",
      forces = panel.force,
      use_rich_text = true
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
        local offsets = segment_offsets_for_count(pdata.segment_count)
        local adjusts = segment_render_adjust_for_count(pdata.segment_count)
        if offsets and offsets[seg_idx] then
          local render_x = offsets[seg_idx] + ((adjusts and adjusts[seg_idx]) or 0)
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
              left_top = { entity = panel, offset = { render_x - half_width, BACKER_Y_OFFSET - BACKER_HALF_HEIGHT } },
              right_bottom = { entity = panel, offset = { render_x + half_width, BACKER_Y_OFFSET + BACKER_HALF_HEIGHT } },
              players = { player },
            }
            seg_bucket.backer = rect and rect.id or nil
          end

          if message ~= "" then
            local txt = rendering.draw_text{
              text = message,
              surface = panel.surface,
              target = { entity = panel, offset = { render_x, TEXT_Y_OFFSET } },
              color = {1, 1, 1},
              scale = TEXT_SCALE,
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

  for seg_idx = 1, pdata.segment_count do
    render_segment(panel, panel_unit, seg_idx, pdata.segments[seg_idx], merged_tbl, pdata.segment_count)
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

local function mirror_and_cache(panel_unit)
  ensure_global()

  local panel = get_panel_by_unit(panel_unit)
  local ports = global.wdp.ports[panel_unit]

  if not panel then
    global.wdp.cache[panel_unit] = {}
    clear_all_panel_render(panel_unit)
    clear_panel_chart_tag(panel_unit)

    if ports and ports.right and ports.right.valid then
      local prev_hash = global.wdp.last_output_hash[panel_unit]
      if prev_hash ~= "" then
        write_const(ports.right, {})
        global.wdp.last_output_hash[panel_unit] = ""
      end
    end
    return
  end

  local merged_tbl, merged_arr = compute_merged_for_panel(panel)
  global.wdp.cache[panel_unit] = merged_arr

  update_panel_render(panel, panel_unit, merged_tbl)
  update_panel_chart_tag(panel, panel_unit, merged_tbl)

  if not ports or not ports.right or not ports.right.valid then return end

  local new_hash = hash_signal_table(merged_tbl)
  local old_hash = global.wdp.last_output_hash[panel_unit]
  if new_hash == old_hash then return end

  write_const(ports.right, merged_tbl)
  global.wdp.last_output_hash[panel_unit] = new_hash
end

local function tick_merge()
  ensure_global()
  for panel_unit, _ports in pairs(global.wdp.ports) do
    mirror_and_cache(panel_unit)
  end

  for _, player in pairs(game.connected_players) do
    update_hover_render_for_player(player)
  end
end

------------------------------------------------------------
-- GUI helpers
------------------------------------------------------------

-- GUI state is intentionally lightweight:
--   panel_unit : currently edited panel
--   active_tab : active segment index
--   active_rule: active rule index for popups / reorder actions

local function get_gui_state(player_index)
  ensure_global()
  return global.wdp.gui[player_index]
end

local function get_panel_from_gui_state(state)
  if not state then return nil end
  return get_panel_by_unit(state.panel_unit)
end

local function get_active_segment_config(panel, player_index)
  local state = get_gui_state(player_index)
  if not state then return nil, nil end

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return nil, nil end

  local idx = state.active_tab or 1
  idx = math.max(1, math.min(idx, pdata.segment_count))
  state.active_tab = idx

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

local function copy_active_segment(player)
  ensure_global()

  local state = get_gui_state(player.index)
  local panel = get_panel_from_gui_state(state)
  if not panel then return false end

  apply_gui_to_segment(player)

  local seg = get_active_segment_config(panel, player.index)
  if not seg then return false end

  global.wdp.clipboard[player.index] = {
    kind = "segment",
    data = deep_copy(seg),
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

  persist_panel_config(panel)
  global.wdp.last_render_hash[panel.unit_number] = nil
  global.wdp.chart_tag_hash[panel.unit_number] = nil

  mirror_and_cache(panel.unit_number)
  refresh_main_gui(player)
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

local function destroy_main_gui(player)
  destroy_rhs_popup(player)
  destroy_message_popup(player)

  local screen = player.gui.screen
  if screen.wdp_main and screen.wdp_main.valid then
    screen.wdp_main.destroy()
  end

  ensure_global()
  global.wdp.gui[player.index] = nil
end

local function rebuild_connected_row(body, panel)
  if body.wdp_connected_row and body.wdp_connected_row.valid then
    body.wdp_connected_row.destroy()
  end

  local red_id, green_id = get_network_ids_by_color(panel)

  local conn = body.add{ type = "flow", name = "wdp_connected_row", direction = "horizontal" }
  conn.style.bottom_margin = 6
  conn.style.horizontal_spacing = 4

  conn.add{ type = "label", caption = "Connected to:" }

  local red = conn.add{ type = "label", caption = tostring(red_id or 0) }
  red.style.font_color = { 1, 0.23, 0.19 }

  local green = conn.add{ type = "label", caption = tostring(green_id or 0) }
  green.style.font_color = { 0.25, 0.9, 0.25 }
end

local function rebuild_alt_row(body, panel, player_index)
  if body.wdp_alt_row and body.wdp_alt_row.valid then
    body.wdp_alt_row.destroy()
  end

  local seg = get_active_segment_config(panel, player_index)
  if not seg then return end

  local row = body.add{ type = "flow", name = "wdp_alt_row", direction = "horizontal" }
  row.style.bottom_margin = 6

  row.add{
    type = "checkbox",
    name = "wdp_show_in_alt_mode",
    caption = "Show in alt mode",
    state = seg.show_in_alt_mode == true
  }
end

local function rebuild_chart_row(body, panel, player_index)
  if body.wdp_chart_row and body.wdp_chart_row.valid then
    body.wdp_chart_row.destroy()
  end

  local seg = get_active_segment_config(panel, player_index)
  if not seg then return end

  local row = body.add{ type = "flow", name = "wdp_chart_row", direction = "horizontal" }
  row.style.bottom_margin = 6

  row.add{
    type = "checkbox",
    name = "wdp_show_in_chart",
    caption = "Show this tag in chart",
    state = seg.show_in_chart == true
  }
end

local function rebuild_segment_tabs(frame, panel, player_index)
  local body = frame.wdp_body
  if not (body and body.valid) then return end

  if body.wdp_tabs then body.wdp_tabs.destroy() end

  local pdata = ensure_panel_segment_data(panel)
  if not pdata then return end

  local tabs = body.add{ type = "flow", name = "wdp_tabs", direction = "horizontal" }
  tabs.style.horizontal_spacing = 4
  tabs.style.top_margin = 4
  tabs.style.bottom_margin = 6

  for i = 1, pdata.segment_count do
    local b = tabs.add{ type = "button", name = "wdp_tab_" .. i, caption = tostring(i) }
    b.style.minimal_width = 40
    if get_gui_state(player_index).active_tab == i then
      b.enabled = false
    end
  end
end

local function build_rule_row(parent, panel, seg_idx, rule_idx, rule, merged_tbl, rule_count)
  local row = parent.add{
    type = "frame",
    name = "wdp_rule_" .. rule_idx,
    direction = "vertical",
    tags = { rule_index = rule_idx, segment_index = seg_idx }
  }
  row.style.horizontally_stretchable = true
  row.style.top_padding = 6
  row.style.bottom_padding = 6
  row.style.left_padding = 8
  row.style.right_padding = 8
  row.style.bottom_margin = 6

  local line = row.add{ type = "flow", name = "wdp_line", direction = "horizontal" }
  line.style.horizontal_spacing = 6
  line.style.vertical_align = "center"

  line.add{ type = "choose-elem-button", name = "wdp_icon_signal", elem_type = "signal", signal = clone_signal(rule.icon_signal) }

  local edit_btn = line.add{
    type = "sprite-button",
    name = "wdp_msg_edit_" .. rule_idx,
    sprite = "wdp_gui_edit",
    hovered_sprite = "wdp_gui_edit_hover",
    clicked_sprite = "wdp_gui_edit_onclick",
    tooltip = "Edit message",
    tags = { rule_index = rule_idx, segment_index = seg_idx }
  }
  edit_btn.style.width = 28
  edit_btn.style.height = 28

  local preview = line.add{ type = "label", name = "wdp_message_preview", caption = message_preview_text(rule.message) }
  preview.style.minimal_width = 160
  preview.style.maximal_width = 160
  preview.style.single_line = true
  preview.style.font_color = { 0.85, 0.85, 0.85 }

  local gap1 = line.add{ type = "empty-widget" }
  gap1.style.width = 18
  gap1.style.height = 1

  line.add{ type = "choose-elem-button", name = "wdp_first_signal", elem_type = "signal", signal = clone_signal(rule.first_signal) }

  local dd = line.add{ type = "drop-down", name = "wdp_comparator" }
  dd.items = comparator_items()
  dd.selected_index = COMPARATOR_INDEX[rule.comparator] or 1
  dd.style.width = 80

  if rule.rhs and rule.rhs.kind == "signal" and rule.rhs.signal then
    local rhs_sprite = sprite_path_from_signal(rule.rhs.signal)
    local rhs_btn = line.add{ type = "sprite-button", name = "wdp_rhs_open_" .. rule_idx, sprite = rhs_sprite, tooltip = "Set RHS", tags = { rule_index = rule_idx, segment_index = seg_idx } }
    rhs_btn.style.width = 40
    rhs_btn.style.height = 40
  else
    local rhs_btn = line.add{ type = "button", name = "wdp_rhs_open_" .. rule_idx, caption = tostring(tonumber(rule.rhs and rule.rhs.constant) or 0), tooltip = "Set RHS", tags = { rule_index = rule_idx, segment_index = seg_idx } }
    rhs_btn.style.minimal_width = 72
  end

  local rhs_count = line.add{ type = "label", name = "wdp_rhs_count", caption = render_rhs_count_for_rule(panel, rule, merged_tbl) }
  rhs_count.style.minimal_width = 36
  rhs_count.style.font = "default-small"
  rhs_count.style.font_color = { 0.75, 0.75, 0.75 }

  local spacer = line.add{ type = "empty-widget" }
  spacer.style.horizontally_stretchable = true
  spacer.style.width = 8

  local up = line.add{ type = "button", name = "wdp_rule_up_" .. rule_idx, caption = "↑", tooltip = "Move rule up", tags = { rule_index = rule_idx, segment_index = seg_idx } }
  up.enabled = rule_idx > 1
  up.style.minimal_width = 32

  local down = line.add{ type = "button", name = "wdp_rule_down_" .. rule_idx, caption = "↓", tooltip = "Move rule down", tags = { rule_index = rule_idx, segment_index = seg_idx } }
  down.enabled = rule_idx < rule_count
  down.style.minimal_width = 32

  local del = line.add{ type = "button", name = "wdp_rule_delete_" .. rule_idx, caption = "X", tooltip = "Delete rule", tags = { rule_index = rule_idx, segment_index = seg_idx } }
  del.style.minimal_width = 32
end

local function rebuild_editor(frame, panel, player_index, merged_tbl)
  local body = frame.wdp_body
  if not (body and body.valid) then return end

  if body.wdp_editor then body.wdp_editor.destroy() end

  local seg, seg_idx = get_active_segment_config(panel, player_index)
  if not seg then return end

  local editor = body.add{ type = "frame", name = "wdp_editor", direction = "vertical" }
  editor.style.top_padding = 8
  editor.style.bottom_padding = 8
  editor.style.left_padding = 10
  editor.style.right_padding = 10
  editor.style.horizontally_stretchable = true

  local top = editor.add{ type = "flow", direction = "horizontal" }
  top.style.vertical_align = "center"

  local spacer = top.add{ type = "empty-widget" }
  spacer.style.horizontally_stretchable = true

  top.add{ type = "button", name = "wdp_copy_segment", caption = "Copy segment" }

  local paste_btn = top.add{ type = "button", name = "wdp_paste_segment", caption = "Paste segment" }
  paste_btn.enabled = not not (global.wdp.clipboard[player_index] and global.wdp.clipboard[player_index].kind == "segment")

  top.add{ type = "button", name = "wdp_add_rule", caption = "Add rule" }

  editor.add{ type = "line" }

  local scroll = editor.add{ type = "scroll-pane", name = "wdp_rule_scroll", direction = "vertical" }
  scroll.style.minimal_height = 220
  scroll.style.maximal_height = 420
  scroll.style.horizontally_stretchable = true
  scroll.style.vertically_stretchable = true
  scroll.horizontal_scroll_policy = "auto"
  scroll.vertical_scroll_policy = "auto"

  local list = scroll.add{ type = "flow", name = "wdp_rule_list", direction = "vertical" }
  list.style.horizontally_stretchable = true
  list.style.vertical_spacing = 0

  for i = 1, #seg.rules do
    build_rule_row(list, panel, seg_idx, i, seg.rules[i], merged_tbl, #seg.rules)
  end
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

  if body.wdp_alt_row and body.wdp_alt_row.valid and body.wdp_alt_row.wdp_show_in_alt_mode and body.wdp_alt_row.wdp_show_in_alt_mode.valid then
    seg.show_in_alt_mode = (body.wdp_alt_row.wdp_show_in_alt_mode.state == true)
  end

  if body.wdp_chart_row and body.wdp_chart_row.valid and body.wdp_chart_row.wdp_show_in_chart then
    local state_checked = body.wdp_chart_row.wdp_show_in_chart.state == true
    seg.show_in_chart = state_checked
    if state_checked then
      for i = 1, pdata.segment_count do
        if i ~= seg_idx and pdata.segments[i] then
          pdata.segments[i].show_in_chart = false
        end
      end
    end
  end

  local scroll = body.wdp_editor.wdp_rule_scroll
  if not (scroll and scroll.valid and scroll.wdp_rule_list and scroll.wdp_rule_list.valid) then return end

  for _, child in ipairs(scroll.wdp_rule_list.children) do
    if child and child.valid then
      local idx = tonumber(child.tags and child.tags.rule_index)
      if idx and seg.rules[idx] then
        local rule = seg.rules[idx]
        local line = child.wdp_line
        if line and line.valid then
          if line.wdp_icon_signal and line.wdp_icon_signal.valid then
            rule.icon_signal = clone_signal(line.wdp_icon_signal.elem_value)
          end
          if line.wdp_first_signal and line.wdp_first_signal.valid then
            rule.first_signal = clone_signal(line.wdp_first_signal.elem_value)
          end
          if line.wdp_comparator and line.wdp_comparator.valid then
            local dd = line.wdp_comparator
            if dd.selected_index and COMPARATORS[dd.selected_index] then
              rule.comparator = COMPARATORS[dd.selected_index].key
            end
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

  if frame.wdp_body and frame.wdp_body.valid then
    rebuild_connected_row(frame.wdp_body, panel)
    rebuild_alt_row(frame.wdp_body, panel, player.index)
    rebuild_chart_row(frame.wdp_body, panel, player.index)
  end

  rebuild_segment_tabs(frame, panel, player.index)
  rebuild_editor(frame, panel, player.index, merged_tbl)
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
    name = "wdp_rhs_signal_apply",
    sprite = "wdp_gui_confirm",
    hovered_sprite = "wdp_gui_confirm_hover",
    clicked_sprite = "wdp_gui_confirm_onclick",
    disabled_sprite = "wdp_gui_confirm_disabled",
    tooltip = "Use selected signal"
  }
  sig_ok.enabled = sig_pick.elem_value ~= nil
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
    name = "wdp_rhs_constant_apply",
    sprite = "wdp_gui_confirm",
    hovered_sprite = "wdp_gui_confirm_hover",
    clicked_sprite = "wdp_gui_confirm_onclick",
    disabled_sprite = "wdp_gui_confirm_disabled",
    tooltip = "Use constant"
  }
  const_ok.enabled = safe_number_text(tf.text) ~= nil
  const_ok.style.width = 28
  const_ok.style.height = 28
end

local function open_rhs_popup(player, seg_idx, rule_idx)
  destroy_rhs_popup(player)

  local state = get_gui_state(player.index)
  if not state then return end
  state.active_tab = seg_idx
  state.active_rule = rule_idx

  local popup = player.gui.screen.add{ type = "frame", name = "wdp_rhs_popup", direction = "vertical" }
  popup.auto_center = true
  popup.style.width = 320

  local titlebar = popup.add{ type = "flow", direction = "horizontal" }
  titlebar.drag_target = popup
  local title = titlebar.add{ type = "label", caption = "Set RHS" }
  title.drag_target = popup
  local spacer = titlebar.add{ type = "empty-widget" }
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  spacer.drag_target = popup
  local close_btn = titlebar.add{ type = "sprite-button", name = "wdp_rhs_close", sprite = "utility/close", tooltip = "Close" }
  close_btn.style.width = 28
  close_btn.style.height = 28

  popup.add{ type = "line" }

  local body = popup.add{ type = "frame", name = "wdp_rhs_body", direction = "vertical" }
  body.style.top_padding = 10
  body.style.bottom_padding = 10
  body.style.left_padding = 10
  body.style.right_padding = 10

  refresh_rhs_popup(player)
end

local function open_msg_icon_popup(player)
  destroy_msg_icon_popup(player)

  local popup = player.gui.screen.add{ type = "frame", name = "wdp_msg_icon_popup", direction = "vertical" }
  popup.auto_center = true
  popup.style.width = 220

  local titlebar = popup.add{ type = "flow", direction = "horizontal" }
  titlebar.drag_target = popup
  local title = titlebar.add{ type = "label", caption = "Insert icon" }
  title.drag_target = popup
  local spacer = titlebar.add{ type = "empty-widget" }
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  spacer.drag_target = popup
  local close_btn = titlebar.add{ type = "sprite-button", name = "wdp_msg_icon_close", sprite = "utility/close", tooltip = "Close" }
  close_btn.style.width = 28
  close_btn.style.height = 28

  popup.add{ type = "line" }
  local body = popup.add{ type = "frame", name = "wdp_msg_icon_body", direction = "vertical" }
  body.style.top_padding = 10
  body.style.bottom_padding = 10
  body.style.left_padding = 10
  body.style.right_padding = 10
  body.add{ type = "choose-elem-button", name = "wdp_msg_icon_picker", elem_type = "signal" }
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

  local popup = player.gui.screen.add{ type = "frame", name = "wdp_msg_popup", direction = "vertical" }
  popup.auto_center = true
  popup.style.width = 520

  local titlebar = popup.add{ type = "flow", direction = "horizontal" }
  titlebar.drag_target = popup
  local title = titlebar.add{ type = "label", caption = "Edit message" }
  title.drag_target = popup
  local spacer = titlebar.add{ type = "empty-widget" }
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  spacer.drag_target = popup
  local close_btn = titlebar.add{ type = "sprite-button", name = "wdp_msg_close", sprite = "utility/close", tooltip = "Close" }
  close_btn.style.width = 28
  close_btn.style.height = 28

  popup.add{ type = "line" }

  local body = popup.add{ type = "frame", name = "wdp_msg_body", direction = "vertical" }
  body.style.top_padding = 10
  body.style.bottom_padding = 10
  body.style.left_padding = 10
  body.style.right_padding = 10

  local icon_row = body.add{ type = "flow", name = "wdp_msg_insert_row", direction = "horizontal" }
  icon_row.style.horizontal_spacing = 8
  icon_row.style.bottom_margin = 8
  icon_row.style.vertical_align = "center"

  local open_btn = icon_row.add{ type = "sprite-button", name = "wdp_msg_icon_open", sprite = "wdp_gui_insert", hovered_sprite = "wdp_gui_insert_hover", tooltip = "Insert icon into message" }
  open_btn.style.width = 28
  open_btn.style.height = 28

  local text = body.add{ type = "text-box", name = "wdp_msg_text", text = rule.message or "" }
  text.style.width = 480
  text.style.height = 140

  local footer = popup.add{ type = "flow", direction = "horizontal" }
  footer.style.top_margin = 6
  local footer_spacer = footer.add{ type = "empty-widget" }
  footer_spacer.style.horizontally_stretchable = true
  local ok_btn = footer.add{ type = "sprite-button", name = "wdp_msg_apply", sprite = "wdp_gui_confirm", hovered_sprite = "wdp_gui_confirm_hover", clicked_sprite = "wdp_gui_confirm_onclick", disabled_sprite = "wdp_gui_confirm_disabled", tooltip = "Apply message" }
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
  frame.style.width = 860

  local titlebar = frame.add{ type = "flow", name = "wdp_titlebar", direction = "horizontal" }
  titlebar.drag_target = frame
  local title = titlebar.add{ type = "label", name = "wdp_title", caption = spec and spec.title or "Widescreen Display Panel" }
  title.style.single_line = true
  title.style.right_margin = 8
  title.drag_target = frame
  local spacer = titlebar.add{ type = "empty-widget" }
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  spacer.drag_target = frame
  local close_btn = titlebar.add{ type = "sprite-button", name = "wdp_close", sprite = "utility/close", tooltip = "Close" }
  close_btn.style.width = 28
  close_btn.style.height = 28

  frame.add{ type = "line" }

  local body = frame.add{ type = "frame", name = "wdp_body", direction = "vertical" }
  body.style.top_padding = 8
  body.style.bottom_padding = 8
  body.style.left_padding = 10
  body.style.right_padding = 10

  local footer = frame.add{ type = "flow", name = "wdp_footer", direction = "horizontal" }
  footer.style.top_margin = 6
  local footer_spacer = footer.add{ type = "empty-widget" }
  footer_spacer.style.horizontally_stretchable = true
  local confirm_btn = footer.add{ type = "sprite-button", name = "wdp_confirm", sprite = "wdp_gui_confirm", hovered_sprite = "wdp_gui_confirm_hover", clicked_sprite = "wdp_gui_confirm_onclick", disabled_sprite = "wdp_gui_confirm_disabled", tooltip = "Apply and close" }
  confirm_btn.style.width = 28
  confirm_btn.style.height = 28

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

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local el = event.element
  if not (el and el.valid) then return end

  local name = el.name

  if name == "wdp_close" then
    apply_gui_to_segment(player)
    destroy_main_gui(player)
    return
  end

  if name == "wdp_confirm" then
    apply_gui_to_segment(player)
    destroy_main_gui(player)
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

  local tab_idx = name:match("^wdp_tab_(%d+)$")
  if tab_idx then
    local state = get_gui_state(player.index)
    if not state then return end
    apply_gui_to_segment(player)
    state.active_tab = tonumber(tab_idx) or 1
    state.active_rule = nil
    destroy_rhs_popup(player)
    destroy_message_popup(player)
    refresh_main_gui(player)
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

  local msg_idx = name:match("^wdp_msg_edit_(%d+)$")
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

script.on_event(defines.events.on_gui_text_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local el = event.element
  if not (el and el.valid) then return end

  if el.name == "wdp_rhs_constant_text" then
    local popup = player.gui.screen.wdp_rhs_popup
    if popup and popup.valid and popup.wdp_rhs_body and popup.wdp_rhs_body.valid then
      local row = popup.wdp_rhs_body.wdp_rhs_constant_row
      if row and row.valid and row.wdp_rhs_constant_apply and row.wdp_rhs_constant_apply.valid then
        row.wdp_rhs_constant_apply.enabled = safe_number_text(el.text) ~= nil
      end
    end
    return
  end

  if el.name == "wdp_msg_text" then
    apply_message_popup(player)
    refresh_live_panel_preview(player, true)
    return
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local el = event.element
  if not (el and el.valid) then return end

  if el.name == "wdp_comparator" then
    apply_gui_to_segment(player)
    refresh_main_gui(player)
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local el = event.element
  if not (el and el.valid) then return end

  if el.name == "wdp_show_in_chart" or el.name == "wdp_show_in_alt_mode" then
    apply_gui_to_segment(player)
    refresh_live_panel_preview(player)
    refresh_main_gui(player)
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if event.element and event.element.valid then
    if event.element.name == "wdp_rhs_popup" then
      destroy_rhs_popup(player)
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

local function scan_all_existing()
  ensure_global()
  for _, surface in pairs(game.surfaces) do
    for name, _ in pairs(PANEL_SPECS) do
      for _, e in pairs(surface.find_entities_filtered { name = name }) do
        if e.direction ~= defines.direction.north then
          e.direction = defines.direction.north
        end
        ensure_panel_runtime(e)
        mirror_and_cache(e.unit_number)
      end
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

local function on_removed(event)
  local ent = event.entity
  if is_panel(ent) then
    destroy_right_ports_for_removed_panel(ent)
    detach_ports(ent)
  end
end

script.on_init(function()
  scan_all_existing()
end)

script.on_configuration_changed(function(_event)
  scan_all_existing()
end)

script.on_event(defines.events.on_built_entity, on_built)
script.on_event(defines.events.on_robot_built_entity, on_built)
script.on_event(defines.events.script_raised_built, on_built)
script.on_event(defines.events.script_raised_revive, on_built)

script.on_event(defines.events.on_player_mined_entity, on_removed)
script.on_event(defines.events.on_robot_mined_entity, on_removed)
script.on_event(defines.events.on_entity_died, on_removed)
script.on_event(defines.events.script_raised_destroy, on_removed)

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
-- Remote interface for DSC
------------------------------------------------------------

------------------------------------------------------------
-- Remote interface for Display Signal Counts
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
