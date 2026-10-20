-- Menu steps: menu, pick, closeMenus and openMenu on the UIDropDownMenu and Menu API fakes.
local A = require("assert")
local HMS = require("tests.helpers.menu_scenario")

local withMenuScenario = HMS.withMenuScenario

-- Opens a UIDropDownMenu menu: a colored title, Open, Locked (disabled), More (submenu with Nested). picks records func calls.
local function openMenuFixture(picks)
  local dd = _G.CreateFrame("Frame", "MenuStepDD", _G.UIParent, "UIDropDownMenuTemplate")
  local function add(text, fields, level)
    local info = _G.UIDropDownMenu_CreateInfo()
    info.text = text
    for k, v in pairs(fields) do
      info[k] = v
    end
    _G.UIDropDownMenu_AddButton(info, level)
  end
  local function record(name)
    return function()
      picks[#picks + 1] = name
    end
  end
  _G.UIDropDownMenu_Initialize(dd, function(_, level, menuList)
    if level == 2 then
      add(menuList[1], { notCheckable = true, func = record(menuList[1]) }, 2)
      return
    end
    add("|cff00ff00Head|r", { isTitle = true, notCheckable = true })
    add("Open", { notCheckable = true, func = record("Open") })
    add("Locked", { notCheckable = true, disabled = true })
    add("More", { notCheckable = true, hasArrow = true, value = "more", menuList = { "Nested" } })
  end, "MENU")
  _G.ToggleDropDownMenu(1, nil, dd)
end

local function test_menu_is_nil_when_no_menu_is_open()
  withMenuScenario(function(s)
    A.eq(s:menu(), nil)
  end)
end

local function test_menu_returns_levels_with_copied_entries_and_the_same_frames()
  withMenuScenario(function(s)
    openMenuFixture({})
    local menu = s:menu()
    A.eq(menu.kind, "menu")
    A.eq(#menu.levels, 1)
    A.eq(menu.levels[1].entries[2].text, "Open")
    A.eq(menu.levels[1].entries[2].frame, _G.DropDownList1Button2)
    A.eq(menu.levels[1].pick, nil)
    A.eq(menu.levels[1].rebuild, nil)
    menu.levels[1].entries[2].text = "Changed"
    A.eq(s:menu().levels[1].entries[2].text, "Open")
  end)
end

local function test_pick_clicks_the_matching_level_one_entry()
  withMenuScenario(function(s)
    local picks = {}
    openMenuFixture(picks)
    s:pick("Open")
    A.same(picks, { "Open" })
    A.eq(s:menu(), nil)
  end)
end

local function test_pick_path_enters_the_submenu_then_clicks_the_last()
  withMenuScenario(function(s)
    local picks = {}
    openMenuFixture(picks)
    s:pick({ "More", "Nested" })
    A.same(picks, { "Nested" })
    -- A pick closes only its own level and deeper (the client's UIDropDownMenu_OnClick), so level 1 stays open.
    A.eq(#s:menu().levels, 1)
  end)
end

local function test_pick_unknown_text_throws_listing_the_entries()
  withMenuScenario(function(s)
    openMenuFixture({})
    local message = A.errors(function()
      s:pick("Nope")
    end, 'pick: no entry "Nope" in level 1')
    A.contains(message, "Open")
    A.contains(message, "Head")
  end)
end

local function test_pick_ambiguous_text_throws()
  withMenuScenario(function(s)
    local dd = _G.CreateFrame("Frame", "AmbigDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(dd, function(_, level)
      for _ = 1, 2 do
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = "Twin", true
        _G.UIDropDownMenu_AddButton(info, level)
      end
    end, "MENU")
    _G.ToggleDropDownMenu(1, nil, dd)
    A.errors(function()
      s:pick("Twin")
    end, 'pick: 2 entries match "Twin"')
  end)
end

-- The title's text is "|cff00ff00Head|r": matching "Head" proves the color escapes are stripped, and the error proves
-- it matched. A UIDropDownMenu title is a disabled Button (Mainline UIDropDownMenu.lua:466-475).
local function test_pick_title_throws_disabled()
  withMenuScenario(function(s)
    openMenuFixture({})
    A.errors(function()
      s:pick("Head")
    end, "pick: disabled")
  end)
end

-- A hand-built level holding a disabled divider, as the dropdown fake makes one (S2, S13); the text only lets pick
-- find it.
local function test_pick_divider_throws_disabled()
  withMenuScenario(function(s)
    local MenuFrames = require("framexml.fakes.menu_frames")
    local level = {
      namePrefix = "DropDownList1",
      entries = { { kind = "divider", text = "sep", enabled = false, checked = false, hasSubmenu = false } },
      pick = function() end,
      openSubmenu = function() end,
    }
    MenuFrames.open(s.w, 1, level)
    A.errors(function()
      s:pick("sep")
    end, "pick: disabled")
  end)
end

-- A Menu API title is a Frame with no OnClick (M18), so a click on it does nothing; pick says so instead of passing.
local function test_pick_menu_api_title_throws_no_click()
  withMenuScenario(function(s)
    _G.MenuUtil.CreateContextMenu(_G.UIParent, function(_, root)
      root:CreateTitle("Head")
    end)
    A.errors(function()
      s:pick("Head")
    end, 'pick: "Head" has no click')
  end)
end

local function test_pick_disabled_entry_throws_disabled()
  withMenuScenario(function(s)
    openMenuFixture({})
    local message = A.errors(function()
      s:pick("Locked")
    end, "pick: ")
    A.contains(message, "disabled")
  end)
end

local function test_pick_with_no_menu_open_throws()
  withMenuScenario(function(s)
    A.errors(function()
      s:pick("Open")
    end, "pick: no menu is open")
  end)
end

local function test_pick_path_through_an_entry_without_a_submenu_throws()
  withMenuScenario(function(s)
    openMenuFixture({})
    A.errors(function()
      s:pick({ "Open", "Nested" })
    end, '"Open" has no submenu')
  end)
end

local function test_pick_path_through_a_disabled_entry_with_a_submenu_throws()
  withMenuScenario(function(s)
    local dd = _G.CreateFrame("Frame", "DisabledArrowDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(dd, function(_, level, menuList)
      local info = _G.UIDropDownMenu_CreateInfo()
      info.text, info.notCheckable = level == 2 and menuList[1] or "Gone", true
      info.disabled, info.hasArrow, info.menuList = level ~= 2, level ~= 2, { "x" }
      _G.UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    _G.ToggleDropDownMenu(1, nil, dd)
    A.errors(function()
      s:pick({ "Gone", "x" })
    end, '"Gone" has no submenu')
  end)
end

-- B's own OnEnter is replaced, so C's submenu stays open; the path must not reach into a submenu B did not open.
local function test_pick_path_does_not_use_a_submenu_another_entry_opened()
  withMenuScenario(function(s)
    local picks = {}
    local dd = _G.CreateFrame("Frame", "OtherSubDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(dd, function(_, level, menuList)
      for _, text in ipairs(level == 2 and menuList or { "B", "C" }) do
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable, info.hasArrow, info.menuList = text, true, text == "C", { "x" }
        info.func = function()
          picks[#picks + 1] = text
        end
        _G.UIDropDownMenu_AddButton(info, level)
      end
    end, "MENU")
    _G.ToggleDropDownMenu(1, nil, dd)
    local entries = s:menu().levels[1].entries
    s:enter(entries[2].frame)
    entries[1].frame:SetScript("OnEnter", function() end)
    A.errors(function()
      s:pick({ "B", "x" })
    end, '"B" has no submenu')
    A.same(picks, {})
  end)
end

local function test_close_menus_hides_every_level()
  withMenuScenario(function(s)
    openMenuFixture({})
    s:enter(s:menu().levels[1].entries[4].frame)
    A.eq(#s:menu().levels, 2)
    s:closeMenus()
    A.eq(s:menu(), nil)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

local function test_pick_without_a_text_or_path_throws_at_the_caller()
  withMenuScenario(function(s)
    openMenuFixture({})
    local message = A.errors(function()
      s:pick(nil)
    end, "pick: expected an entry text or a path table, got nil")
    A.contains(message, "test_scenario_menu.lua:")
  end)
end

local function test_pick_with_an_empty_path_throws()
  withMenuScenario(function(s)
    openMenuFixture({})
    A.errors(function()
      s:pick({})
    end, "pick: empty path")
  end)
end

local function test_open_menu_runs_the_hook_for_the_tag_and_shows_its_entries()
  withMenuScenario(function(s)
    _G.Menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, contextData)
      root:CreateButton("Hi " .. contextData.name, function() end)
    end)
    s:openMenu("FRIEND", { name = "Bob" })
    A.eq(s:menu().levels[1].entries[1].text, "Hi Bob")
  end)
end

local function test_open_menu_adds_the_blizzard_entries_note_to_the_report()
  withMenuScenario(function(s)
    s:openMenu("FRIEND", {})
    A.contains(s:report().notes, "Blizzard's own entries are not simulated")
  end)
end

local function test_open_menu_throws_when_unit_popup_open_menu_is_missing()
  withMenuScenario(function(s)
    rawset(_G, "UnitPopup_OpenMenu", nil)
    A.errors(function()
      s:openMenu("FRIEND", {})
    end, "openMenu: UnitPopup_OpenMenu is not on retail")
  end)
end

return function()
  test_pick_with_an_empty_path_throws()
  test_pick_without_a_text_or_path_throws_at_the_caller()
  test_menu_is_nil_when_no_menu_is_open()
  test_menu_returns_levels_with_copied_entries_and_the_same_frames()
  test_pick_clicks_the_matching_level_one_entry()
  test_pick_path_enters_the_submenu_then_clicks_the_last()
  test_pick_unknown_text_throws_listing_the_entries()
  test_pick_ambiguous_text_throws()
  test_pick_title_throws_disabled()
  test_pick_menu_api_title_throws_no_click()
  test_pick_divider_throws_disabled()
  test_pick_disabled_entry_throws_disabled()
  test_pick_with_no_menu_open_throws()
  test_pick_path_through_an_entry_without_a_submenu_throws()
  test_pick_path_through_a_disabled_entry_with_a_submenu_throws()
  test_pick_path_does_not_use_a_submenu_another_entry_opened()
  test_close_menus_hides_every_level()
  test_open_menu_runs_the_hook_for_the_tag_and_shows_its_entries()
  test_open_menu_adds_the_blizzard_entries_note_to_the_report()
  test_open_menu_throws_when_unit_popup_open_menu_is_missing()
end
