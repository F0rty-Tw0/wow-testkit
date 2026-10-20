-- DropdownButton value text: default, override and set text, and the text that follows the selection.
-- Split from test_menu_dropdown.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML
local TEXT_KEY = "Text"

local function noop() end

local function newDropdown(generator)
  local dd = _G.CreateFrame("DropdownButton", nil, _G.UIParent, "WowStyle1DropdownTemplate")
  if generator then
    dd:SetupMenu(generator)
  end
  return dd
end

local function twoEntries(_, root)
  root:CreateButton("One", noop)
  root:CreateRadio("Two", noop, noop)
end

-- Radios "One" and "Two" over a `chosen` index the test can also change from outside.
local function radios(choice)
  return function(_, root)
    for i, text in ipairs({ "One", "Two" }) do
      root:CreateRadio(text, function()
        return choice.value == i
      end, function()
        choice.value = i
      end)
    end
  end
end

local function test_override_text_wins_over_default_text() -- (D6)
  withFrameXML("retail", function()
    local dd = newDropdown()
    dd:SetDefaultText("Pick")
    A.eq(dd[TEXT_KEY]:GetText(), "Pick")
    dd:OverrideText("Chosen")
    A.eq(dd[TEXT_KEY]:GetText(), "Chosen")
    dd:SetDefaultText("Other")
    A.eq(dd[TEXT_KEY]:GetText(), "Chosen")
  end)
end

local function test_override_text_with_nil_does_nothing() -- (D6)
  withFrameXML("retail", function()
    local dd = newDropdown()
    dd:SetDefaultText("Pick")
    dd:OverrideText(nil)
    A.eq(dd[TEXT_KEY]:GetText(), "Pick")
  end)
end

local function test_set_text_and_get_text_store_and_show_the_value_text() -- (D6)
  withFrameXML("retail", function()
    local dd = newDropdown()
    dd:SetText("Shown")
    A.eq(dd:GetText(), "Shown")
    A.eq(dd[TEXT_KEY]:GetText(), "Shown")
  end)
end

local function test_value_text_follows_the_selected_radio_and_falls_back_to_the_default() -- (D6)
  withFrameXML("retail", function()
    local choice = {}
    local dd = _G.CreateFrame("DropdownButton", nil, _G.UIParent, "WowStyle1DropdownTemplate")
    dd:SetDefaultText("Pick")
    dd:SetupMenu(radios(choice))
    A.eq(dd[TEXT_KEY]:GetText(), "Pick")
    choice.value = 2
    dd:GenerateMenu()
    A.eq(dd[TEXT_KEY]:GetText(), "Two")
  end)
end

local function test_picking_a_radio_updates_the_value_text_when_the_menu_closes() -- (D6)
  withFrameXML("retail", function(w)
    local choice = {}
    local dd = newDropdown()
    dd:SetDefaultText("Pick")
    dd:SetupMenu(radios(choice))
    Input.click(w, dd, "LeftButton")
    Input.click(w, w.menus[1].entries[2].frame, "LeftButton")
    A.eq(dd:IsMenuOpen(), false)
    A.eq(dd[TEXT_KEY]:GetText(), "Two")
    A.eq(dd:GetText(), "Two")
  end)
end

local function test_checkbox_pick_updates_the_value_text_and_keeps_the_menu_open() -- (D6)
  withFrameXML("retail", function(w)
    local on = { a = false, b = false }
    local dd = newDropdown()
    dd:SetDefaultText("None")
    dd:SetupMenu(function(_, root)
      for _, key in ipairs({ "a", "b" }) do
        root:CreateCheckbox("Box " .. key, function()
          return on[key]
        end, function()
          on[key] = not on[key]
        end)
      end
    end)
    Input.click(w, dd, "LeftButton")
    Input.click(w, w.menus[1].entries[1].frame, "LeftButton")
    Input.click(w, w.menus[1].entries[2].frame, "LeftButton")
    A.eq(dd:IsMenuOpen(), true)
    A.eq(dd[TEXT_KEY]:GetText(), "Box a, Box b")
    Input.click(w, w.menus[1].entries[1].frame, "LeftButton")
    A.eq(dd[TEXT_KEY]:GetText(), "Box b")
  end)
end

local function test_close_menu_updates_the_value_text()
  withFrameXML("retail", function()
    local choice = {}
    local dd = newDropdown()
    dd:SetDefaultText("Pick")
    dd:SetupMenu(radios(choice))
    dd:OpenMenu()
    choice.value = 1
    dd:CloseMenu()
    A.eq(dd[TEXT_KEY]:GetText(), "One")
  end)
end

local function test_override_text_stops_the_value_text_following_the_selection() -- (D6)
  withFrameXML("retail", function()
    local choice = { value = 1 }
    local dd = newDropdown()
    dd:OverrideText("Fixed")
    dd:SetupMenu(radios(choice))
    dd:GenerateMenu()
    A.eq(dd[TEXT_KEY]:GetText(), "Fixed")
  end)
end

local function test_frame_without_the_template_has_no_value_text_and_still_works() -- (D10)
  withFrameXML("retail", function(w)
    local dd = _G.CreateFrame("DropdownButton", nil, _G.UIParent)
    dd:SetupMenu(twoEntries)
    A.eq(dd.SetDefaultText, nil)
    Input.click(w, dd, "LeftButton")
    A.eq(dd:IsMenuOpen(), true)
  end)
end

return function()
  test_override_text_wins_over_default_text()
  test_override_text_with_nil_does_nothing()
  test_set_text_and_get_text_store_and_show_the_value_text()
  test_value_text_follows_the_selected_radio_and_falls_back_to_the_default()
  test_picking_a_radio_updates_the_value_text_when_the_menu_closes()
  test_checkbox_pick_updates_the_value_text_and_keeps_the_menu_open()
  test_close_menu_updates_the_value_text()
  test_override_text_stops_the_value_text_following_the_selection()
  test_frame_without_the_template_has_no_value_text_and_still_works()
end
