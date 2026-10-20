-- DropdownButton: the per-world widget type from the Menu API fake, its menu and toggle.
local A = require("assert")
local Flavors = require("tools.flavors")
local HF = require("tests.helpers.framexml")
local HW = require("tests.helpers.widgets")
local Input = require("input")
local Rec = require("tests.helpers.input")
local Templates = require("ui.templates")

local withFrameXML = HF.withFrameXML

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

local function texts(level)
  local out = {}
  for i, entry in ipairs(level.entries) do
    out[i] = entry.text
  end
  return out
end

local function test_dropdown_button_exists_on_every_flavor_with_the_menu_api_assumed()
  for _, flavor in ipairs(Flavors.list) do
    withFrameXML(flavor, function()
      local dd = newDropdown()
      A.eq(dd:GetObjectType(), "Button", flavor) -- D8 (assumed): an intrinsic reports its base type
      A.eq(dd.intrinsic, "DropdownButton", flavor)
      A.eq(dd:IsObjectType("Button"), true, flavor)
      A.eq(dd:HasScript("OnClick"), true, flavor)
      for _, child in ipairs(Templates.TEMPLATES.WowStyle1DropdownTemplate.children) do
        A.eq(dd[child.key]:GetObjectType(), child.type, flavor .. " " .. child.key)
      end
    end)
  end
end

local function test_dropdown_button_sets_the_intrinsic_key_values()
  withFrameXML("retail", function()
    local dd = _G.CreateFrame("DropdownButton")
    A.same({ dd.intrinsic, dd.menuPoint, dd.menuPointX, dd.menuPointY, dd.menuRelativePoint }, { "DropdownButton", "TOPLEFT", 0, 0, "BOTTOMLEFT" })
  end)
end

local function test_world_without_the_menu_api_rejects_it_even_after_another_world_had_it()
  withFrameXML("retail", function()
    newDropdown()
  end)
  HW.withWidgets("retail", function()
    A.errors(function()
      _G.CreateFrame("DropdownButton")
    end, "unknown frame type 'DropdownButton'")
  end)
end

local function test_open_menu_runs_the_generator_with_the_dropdown_and_the_root() -- (D4)
  withFrameXML("retail", function(w)
    local seen
    local dd = newDropdown(function(owner, root)
      seen = owner
      twoEntries(owner, root)
    end)
    dd:OpenMenu()
    A.eq(seen, dd)
    A.eq(w.menus[1].owner, dd)
    A.same(texts(w.menus[1]), { "One", "Two" })
  end)
end

local function test_setup_menu_on_a_shown_dropdown_runs_the_generator_once_without_opening() -- (D5)
  withFrameXML("retail", function(w)
    local runs = 0
    newDropdown(function()
      runs = runs + 1
    end)
    A.eq(runs, 1)
    A.eq(#w.menus, 0)
  end)
end

local function test_open_menu_on_a_disabled_dropdown_opens_nothing() -- (D5)
  withFrameXML("retail", function(w)
    local dd = newDropdown(twoEntries)
    dd:Disable()
    dd:OpenMenu()
    A.eq(#w.menus, 0)
  end)
end

local function test_open_menu_without_a_generator_opens_nothing()
  withFrameXML("retail", function(w)
    newDropdown():OpenMenu()
    A.eq(#w.menus, 0)
  end)
end

local function test_open_menu_on_an_open_dropdown_does_not_run_the_generator_again() -- (D5)
  withFrameXML("retail", function()
    local runs = 0
    local dd = newDropdown(function(owner, root)
      runs = runs + 1
      twoEntries(owner, root)
    end)
    dd:OpenMenu()
    local opened = runs
    dd:OpenMenu()
    A.eq(runs, opened)
  end)
end

local function test_is_menu_open_follows_the_menu()
  withFrameXML("retail", function(w)
    local dd, other = newDropdown(twoEntries), newDropdown(twoEntries)
    A.eq(dd:IsMenuOpen(), false)
    dd:OpenMenu()
    A.eq(dd:IsMenuOpen(), true)
    A.eq(other:IsMenuOpen(), false)
    other:OpenMenu()
    A.eq(dd:IsMenuOpen(), false)
    other:CloseMenu()
    A.eq(other:IsMenuOpen(), false)
    A.eq(#w.menus, 0)
  end)
end

local function test_mouse_down_opens_the_menu_and_the_click_does_not_toggle_it() -- (D1)
  withFrameXML("retail", function(w)
    local dd = newDropdown(twoEntries)
    local log = Rec.record(dd, { "OnClick" })
    Input.click(w, dd, "LeftButton")
    A.eq(dd:IsMenuOpen(), true)
    A.eq(#log, 1)
  end)
end

local function test_mouse_down_on_an_open_dropdown_closes_it() -- (D2)
  withFrameXML("retail", function(w)
    local dd = newDropdown(twoEntries)
    Input.click(w, dd, "LeftButton")
    Input.click(w, dd, "LeftButton")
    A.eq(#w.menus, 0)
    Input.click(w, dd, "LeftButton")
    A.eq(dd:IsMenuOpen(), true)
  end)
end

local function test_mouse_down_with_another_button_does_not_open_the_menu() -- (D3)
  withFrameXML("retail", function(w)
    local dd = newDropdown(twoEntries)
    dd:RegisterForClicks("AnyUp")
    Input.click(w, dd, "RightButton")
    A.eq(#w.menus, 0)
  end)
end

local function test_addon_on_mouse_down_handler_does_not_remove_the_toggle()
  withFrameXML("retail", function(w)
    local dd = newDropdown(twoEntries)
    local openInHandler
    dd:SetScript("OnMouseDown", function(self)
      openInHandler = self:IsMenuOpen()
    end)
    Input.click(w, dd, "LeftButton")
    A.eq(dd:IsMenuOpen(), true)
    A.eq(openInHandler, true) -- the intrinsic toggle runs before the frame's own handler
  end)
end

local function test_second_dropdown_replaces_the_first_menu()
  withFrameXML("retail", function(w)
    local a, b = newDropdown(twoEntries), newDropdown(twoEntries)
    Input.click(w, a, "LeftButton")
    Input.click(w, b, "LeftButton")
    A.eq(w.menus[1].owner, b)
    A.eq(a:IsMenuOpen(), false)
  end)
end

local function test_picking_an_entry_closes_the_menu_and_the_next_click_reopens_it()
  withFrameXML("retail", function(w)
    local dd = newDropdown(twoEntries)
    Input.click(w, dd, "LeftButton")
    Input.click(w, w.menus[1].entries[1].frame, "LeftButton")
    A.eq(dd:IsMenuOpen(), false)
    Input.click(w, dd, "LeftButton")
    A.eq(dd:IsMenuOpen(), true)
  end)
end

local function test_generate_menu_runs_the_generator_and_rebuilds_an_open_menu_in_place() -- (D5)
  withFrameXML("retail", function(w)
    local runs = 0
    local dd = newDropdown(function(_, root)
      runs = runs + 1
      root:CreateButton("Run " .. runs, noop)
    end)
    A.eq(runs, 1) -- SetupMenu on a shown frame
    dd:GenerateMenu()
    A.eq(runs, 2)
    A.eq(#w.menus, 0)
    dd:OpenMenu()
    A.eq(runs, 3)
    local frame = w.menus[1].entries[1].frame
    dd:GenerateMenu()
    A.eq(runs, 4)
    A.same(texts(w.menus[1]), { "Run 4" })
    A.eq(w.menus[1].entries[1].frame, frame)
    A.eq(#w.menus, 1)
  end)
end

return function()
  test_dropdown_button_exists_on_every_flavor_with_the_menu_api_assumed()
  test_dropdown_button_sets_the_intrinsic_key_values()
  test_world_without_the_menu_api_rejects_it_even_after_another_world_had_it()
  test_open_menu_runs_the_generator_with_the_dropdown_and_the_root()
  test_setup_menu_on_a_shown_dropdown_runs_the_generator_once_without_opening()
  test_open_menu_on_a_disabled_dropdown_opens_nothing()
  test_open_menu_without_a_generator_opens_nothing()
  test_open_menu_on_an_open_dropdown_does_not_run_the_generator_again()
  test_is_menu_open_follows_the_menu()
  test_mouse_down_opens_the_menu_and_the_click_does_not_toggle_it()
  test_mouse_down_on_an_open_dropdown_closes_it()
  test_mouse_down_with_another_button_does_not_open_the_menu()
  test_addon_on_mouse_down_handler_does_not_remove_the_toggle()
  test_second_dropdown_replaces_the_first_menu()
  test_picking_an_entry_closes_the_menu_and_the_next_click_reopens_it()
  test_generate_menu_runs_the_generator_and_rebuilds_an_open_menu_in_place()
end
