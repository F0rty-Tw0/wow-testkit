-- DropdownButton: generator changes on an open menu, the template's OnShow, and the mixin methods past the basics.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function noop() end

local function newDropdown(generator)
  local dd = _G.CreateFrame("DropdownButton", nil, _G.UIParent, "WowStyle1DropdownTemplate")
  if generator then
    dd:SetupMenu(generator)
  end
  return dd
end

local function oneButton(text)
  return function(_, root)
    root:CreateButton(text, noop)
  end
end

local function texts(level)
  local out = {}
  for i, entry in ipairs(level.entries) do
    out[i] = entry.text
  end
  return out
end

local function test_setup_menu_on_an_open_menu_shows_the_new_generators_entries() -- (D5)
  withFrameXML("retail", function(w)
    local dd = newDropdown(oneButton("Old"))
    dd:OpenMenu()
    dd:SetupMenu(oneButton("New"))
    A.eq(dd:IsMenuOpen(), true)
    A.same(texts(w.menus[1]), { "New" })
    dd:CloseMenu()
    dd:OpenMenu()
    A.same(texts(w.menus[1]), { "New" })
  end)
end

-- Radios "One" and "Two" over choice.value, counting generator runs in choice.runs.
local function radios(choice)
  return function(_, root)
    choice.runs = (choice.runs or 0) + 1
    for i, text in ipairs({ "One", "Two" }) do
      root:CreateRadio(text, function()
        return choice.value == i
      end, noop)
    end
  end
end

local function test_template_on_show_generates_the_menu_set_up_while_hidden() -- (D5)
  withFrameXML("retail", function()
    local choice = { value = 2 }
    local dd = newDropdown()
    dd:Hide()
    dd:SetDefaultText("Pick")
    dd:SetupMenu(radios(choice))
    A.eq(choice.runs, nil)
    A.eq(dd.Text:GetText(), "Pick")
    dd:Show()
    A.eq(choice.runs, 1)
    A.eq(dd.Text:GetText(), "Two")
  end)
end

local function test_template_on_show_runs_when_a_hidden_parent_is_shown() -- (D5)
  withFrameXML("retail", function()
    local choice = { value = 1 }
    local parent = _G.CreateFrame("Frame", nil, _G.UIParent)
    local dd = _G.CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetupMenu(radios(choice))
    parent:Hide()
    parent:Show()
    A.eq(choice.runs, 2)
  end)
end

local function test_template_on_show_is_a_replaceable_script_and_runs_before_hooks() -- (D5)
  withFrameXML("retail", function()
    local choice = { value = 1 }
    local dd = newDropdown(radios(choice))
    local seen
    dd:HookScript("OnShow", function()
      seen = choice.runs
    end)
    dd:Hide()
    dd:Show()
    A.eq(seen, 2)
    A.eq(type(dd:GetScript("OnShow")), "function")
    dd:SetScript("OnShow", nil)
    dd:Hide()
    dd:Show()
    A.eq(choice.runs, 2)
  end)
end

local function test_plain_dropdown_button_has_no_on_show_generate() -- (D5)
  withFrameXML("retail", function()
    local choice = {}
    local dd = _G.CreateFrame("DropdownButton", nil, _G.UIParent)
    dd:Hide()
    dd:SetupMenu(radios(choice))
    dd:Show()
    A.eq(choice.runs, nil)
    A.eq(dd:GetScript("OnShow"), nil)
  end)
end

return function()
  test_setup_menu_on_an_open_menu_shows_the_new_generators_entries()
  test_template_on_show_generates_the_menu_set_up_while_hidden()
  test_template_on_show_runs_when_a_hidden_parent_is_shown()
  test_template_on_show_is_a_replaceable_script_and_runs_before_hooks()
  test_plain_dropdown_button_has_no_on_show_generate()
end
