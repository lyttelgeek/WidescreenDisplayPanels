-- Custom sprite definitions for WDP GUI buttons.
data:extend({

{
    type = "sprite",
    name = "wdp_circuit_connection",
    filename = "__core__/graphics/icons/mip/circuit-connection.png",
    size = 32,
    mipmap_count = 4,
    flags = { "gui-icon" }
},
{
    type = "sprite",
    name = "wdp_gui_arrow_up",
    filename = "__base__/graphics/icons/arrows/up-arrow.png",
    size = 64
},
{
    type = "sprite",
    name = "wdp_gui_arrow_down",
    filename = "__base__/graphics/icons/arrows/down-arrow.png",
    size = 64
},
{
    type = "sprite",
    name = "wdp_gui_remove",
    filename = "__base__/graphics/icons/signal/signal-trash-bin.png",
    size = 64
},
{
    type = "sprite",
    name = "wdp_gui_insert",
    filename = "__WidescreenDisplayPanels__/graphics/icons/wdp_gui_insert.png",
    size = 21
},
{
    type = "sprite",
    name = "wdp_gui_insert_hover",
    filename = "__WidescreenDisplayPanels__/graphics/icons/wdp_gui_insert_hover.png",
    size = 21
},

})

data.raw["gui-style"].default["wdp_confirm_button"] = {
  type = "button_style",
  parent = "green_button",
  size = 28,
  padding = 2,
}
