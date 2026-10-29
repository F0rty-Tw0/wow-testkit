-- UIDropDownMenu fake: Toggle and a hasArrow entry open, replace and close levels.
-- Split from test_dropdown.lua (size).
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local newDropdown = HM.newSpecDropdown
local openMenu = HM.openSpecMenu
local texts = HM.openTexts

local function test_toggle_opens_level_one_owned_by_the_frame()
  withFrameXML("retail", function(w)
    local frame = openMenu({ { "One" } })
    A.eq(w.menus[1].owner, frame)
    A.eq(w.menus[1].namePrefix, "DropDownList1")
    A.eq(_G.DropDownList1:IsShown(), true)
  end)
end

local function test_toggle_again_on_the_owning_frame_closes_the_menu()
  withFrameXML("retail", function(w)
    local frame = openMenu({ { "One" } })
    _G.ToggleDropDownMenu(1, nil, frame)
    A.same(w.menus, {})
    A.eq(_G.DropDownList1:IsShown(), false)
  end)
end

local function test_toggle_on_another_frame_replaces_the_open_menu()
  withFrameXML("retail", function(w)
    openMenu({ { "One" } })
    local other = newDropdown({ { "Other" } }, "OtherDD")
    _G.ToggleDropDownMenu(1, nil, other)
    A.eq(#w.menus, 1)
    A.eq(w.menus[1].owner, other)
    A.same(texts(w), { "Other" })
  end)
end

local function test_toggle_without_a_frame_uses_the_owner_of_level_one()
  withFrameXML("retail", function(w)
    local frame = openMenu({ { "More", { hasArrow = true } } })
    _G.ToggleDropDownMenu(2, "v", nil, nil, nil, nil, { { "Nested" } }, _G.DropDownList1Button1)
    A.eq(#w.menus, 2)
    A.eq(w.menus[2].owner, frame)
    A.same(texts(w, 2), { "Nested" })
  end)
end

-- S1, S16 (Mainline UIDropDownMenu.lua:1065 and :1168, Classic :1004 and :1107): the client indexes button when no
-- frame is passed and when it opens a level past 1, so a nil one raises at the caller and opens nothing.
local function test_toggle_past_level_one_without_a_button_errors()
  withFrameXML("retail", function(w)
    local frame = openMenu({ { "More", { hasArrow = true } } })
    local where = "^tests[/\\]framexml[/\\]test_dropdown_open%.lua:%d+: ToggleDropDownMenu: "
    local message = A.errors(function()
      _G.ToggleDropDownMenu(2, "v", nil, nil, nil, nil, { { "Nested" } })
    end, "no button")
    A.truthy(message:find(where), message)
    A.errors(function()
      _G.ToggleDropDownMenu(2, "v", frame, nil, nil, nil, { { "Nested" } })
    end, "no button")
    A.same({ #w.menus, _G.DropDownList2:IsShown() }, { 1, false })
  end)
end

local function test_toggle_on_a_frame_without_initialize_errors()
  withFrameXML("retail", function()
    local frame = _G.CreateFrame("Frame", "BareDD", _G.UIParent, "UIDropDownMenuTemplate")
    A.errors(function()
      _G.ToggleDropDownMenu(1, nil, frame)
    end, "UIDropDownMenu_Initialize")
  end)
end

local function test_entering_has_arrow_entry_calls_toggle_with_value_menu_list_and_entry()
  withFrameXML("retail", function(w)
    local menuList = { { "Nested" } }
    openMenu({ { "More", { hasArrow = true, value = "v", menuList = menuList } } })
    local real, got = _G.ToggleDropDownMenu, nil
    _G.ToggleDropDownMenu = function(...)
      got = { n = select("#", ...), ... }
      return real(...)
    end
    local entry = w.menus[1].entries[1].frame
    Input.enter(w, entry)
    A.eq(got.n, 10) -- Mainline passes menuList, the entry frame, nil, menuListDisplayMode (UIDropDownMenu.lua:187)
    A.eq(got[1], 2)
    A.eq(got[2], "v")
    A.eq(got[3], nil)
    A.eq(got[7], menuList)
    A.eq(got[8], entry)
  end)
end

local function test_entering_has_arrow_entry_without_value_passes_its_text()
  withFrameXML("vanilla", function(w)
    openMenu({ { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    local real, got = _G.ToggleDropDownMenu, nil
    _G.ToggleDropDownMenu = function(...)
      got = { n = select("#", ...), ... }
      return real(...)
    end
    Input.enter(w, w.menus[1].entries[1].frame)
    A.eq(got.n, 8) -- Classic stops at the entry frame (UIDropDownMenu.lua:214)
    A.eq(got[2], "More")
  end)
end

local function test_entering_has_arrow_entry_opens_level_two_under_that_entry()
  withFrameXML("retail", function(w)
    openMenu({ { "A" }, { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    Input.enter(w, w.menus[1].entries[2].frame)
    A.eq(#w.menus, 2)
    A.eq(w.menus[2].parentIndex, 2)
    A.same(texts(w, 2), { "Nested" })
  end)
end

local function test_entering_the_same_entry_again_keeps_its_submenu_open()
  withFrameXML("retail", function(w)
    openMenu({ { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    local frame = w.menus[1].entries[1].frame
    Input.enter(w, frame)
    local sub = w.menus[2]
    Input.enter(w, frame)
    A.eq(#w.menus, 2)
    A.eq(w.menus[2], sub)
  end)
end

local function test_close_drop_down_menus_closes_from_the_given_level()
  withFrameXML("retail", function(w)
    openMenu({ { "More", { hasArrow = true, menuList = { { "Nested" } } } } })
    Input.enter(w, w.menus[1].entries[1].frame)
    _G.CloseDropDownMenus(2)
    A.eq(#w.menus, 1)
    _G.CloseDropDownMenus()
    A.same(w.menus, {})
  end)
end

-- UIDropDownMenuButtonTemplate sets OnClick and OnEnter once (Mainline UIDropDownMenuTemplates.xml:89-97, Classic
-- :148-151); AddButton and Toggle never set a list button's scripts, so an addon's SetScript lasts across reopening.
local function test_an_addon_script_on_a_list_button_survives_reopening()
  withFrameXML("retail", function(w)
    local picks, clicks, enters = 0, 0, 0
    local frame = openMenu({
      { "One", {
        notCheckable = true,
        func = function()
          picks = picks + 1
        end,
      } },
    })
    _G.DropDownList1Button1:SetScript("OnClick", function()
      clicks = clicks + 1
    end)
    _G.DropDownList1Button1:SetScript("OnEnter", function()
      enters = enters + 1
    end)
    _G.ToggleDropDownMenu(1, nil, frame)
    _G.ToggleDropDownMenu(1, nil, frame)
    A.eq(_G.DropDownList1Button1:IsShown(), true)
    Input.enter(w, _G.DropDownList1Button1)
    Input.click(w, _G.DropDownList1Button1, "LeftButton")
    A.same({ picks, clicks, enters }, { 0, 1, 1 })
  end)
end

-- A not-checkable spec whose func records text in picks; fields are extra info fields.
local function picked(picks, text, fields)
  local info = {
    notCheckable = true,
    func = function()
      picks[#picks + 1] = text
    end,
  }
  for k, v in pairs(fields or {}) do
    info[k] = v
  end
  return { text, info }
end

-- S21: the kit sets a list Button's scripts once, so they must act on the entry the Button shows now: a list refilled
-- for another dropdown picks the new entry.
local function test_a_list_refilled_for_another_dropdown_picks_the_new_entry()
  withFrameXML("retail", function(w)
    local picks = {}
    local first = newDropdown({ picked(picks, "A") }, "FirstBoundDD")
    local second = newDropdown({ picked(picks, "B") }, "SecondBoundDD")
    _G.ToggleDropDownMenu(1, nil, first)
    _G.ToggleDropDownMenu(1, nil, second)
    Input.click(w, _G.DropDownList1Button1, "LeftButton")
    A.same(picks, { "B" })
  end)
end

-- S21 at level 2: DropDownList2 reopened under another entry picks that entry's submenu item.
local function test_a_submenu_list_reopened_under_another_entry_picks_the_new_entry()
  withFrameXML("retail", function(w)
    local picks = {}
    openMenu({
      picked(picks, "X", { hasArrow = true, menuList = { picked(picks, "X1") } }),
      picked(picks, "Y", { hasArrow = true, menuList = { picked(picks, "Y1") } }),
    })
    Input.enter(w, w.menus[1].entries[1].frame)
    Input.enter(w, w.menus[1].entries[2].frame)
    A.same(texts(w, 2), { "Y1" })
    Input.click(w, _G.DropDownList2Button1, "LeftButton")
    A.same(picks, { "Y1" })
  end)
end

return function()
  test_a_list_refilled_for_another_dropdown_picks_the_new_entry()
  test_a_submenu_list_reopened_under_another_entry_picks_the_new_entry()
  test_an_addon_script_on_a_list_button_survives_reopening()
  test_toggle_opens_level_one_owned_by_the_frame()
  test_toggle_again_on_the_owning_frame_closes_the_menu()
  test_toggle_on_another_frame_replaces_the_open_menu()
  test_toggle_without_a_frame_uses_the_owner_of_level_one()
  test_toggle_past_level_one_without_a_button_errors()
  test_toggle_on_a_frame_without_initialize_errors()
  test_entering_has_arrow_entry_calls_toggle_with_value_menu_list_and_entry()
  test_entering_has_arrow_entry_without_value_passes_its_text()
  test_entering_has_arrow_entry_opens_level_two_under_that_entry()
  test_entering_the_same_entry_again_keeps_its_submenu_open()
  test_close_drop_down_menus_closes_from_the_given_level()
end
