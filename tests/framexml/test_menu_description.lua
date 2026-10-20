-- Menu description tree: builders, children, recorded settings.
local A = require("assert")
local Description = require("framexml.fakes.menu_description")

local function noop() end

local function test_builders_append_children_in_order_and_return_the_child()
  local root = Description.newRoot()
  local button = root:CreateButton("A", noop, "d")
  local title = root:CreateTitle("T")
  root:CreateDivider()
  A.eq(root.kind, "root")
  A.eq(root.children[1], button)
  A.eq(root.children[2], title)
  A.same({ button.kind, title.kind, root.children[3].kind }, { "button", "title", "divider" })
  A.same({ button.text, button.callback, button.data }, { "A", noop, "d" })
end

local function test_checkbox_and_radio_keep_is_selected_set_selected_and_data()
  local root = Description.newRoot()
  local check = root:CreateCheckbox("C", noop, noop, 1)
  local radio = root:CreateRadio("R", noop, noop, 2)
  A.same({ check.kind, check.isSelected, check.setSelected, check.data }, { "checkbox", noop, noop, 1 })
  A.same({ radio.kind, radio.data }, { "radio", 2 })
end

local function test_an_element_with_children_is_a_submenu()
  local more = Description.newRoot():CreateButton("More")
  local deep = more:CreateButton("Deep", noop)
  A.eq(more.children[1], deep)
end

local function test_set_enabled_keeps_a_boolean_or_a_function_and_returns_nothing()
  local button = Description.newRoot():CreateButton("A", noop)
  A.eq(button.enabled, true)
  A.eq(select("#", button:SetEnabled(false)), 0)
  A.eq(button.enabled, false)
  button:SetEnabled(noop)
  A.eq(button.enabled, noop)
end

local function test_tooltip_scroll_mode_and_tag_are_recorded()
  local root = Description.newRoot()
  root:SetScrollMode(200)
  root:SetTooltip(noop)
  root:SetTag("MENU_X", { a = 1 })
  A.same({ root.scrollHeight, root.tooltip, root.tag, root.contextData.a }, { 200, noop, "MENU_X", 1 })
end

-- Menu.lua:595-598 (SetTag), MenuUtil.lua:287-292 (SetTooltip): neither returns a value.
local function test_set_tooltip_and_set_tag_return_nothing()
  local root = Description.newRoot()
  A.eq(select("#", root:SetTooltip(noop)), 0)
  A.eq(select("#", root:SetTag("MENU_X")), 0)
end

return function()
  test_builders_append_children_in_order_and_return_the_child()
  test_checkbox_and_radio_keep_is_selected_set_selected_and_data()
  test_an_element_with_children_is_a_submenu()
  test_set_enabled_keeps_a_boolean_or_a_function_and_returns_nothing()
  test_tooltip_scroll_mode_and_tag_are_recorded()
  test_set_tooltip_and_set_tag_return_nothing()
end
