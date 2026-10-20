-- Menu steps: menu, pick, closeMenus, openMenu and the Clicky menus, on the UIDropDownMenu and Menu API fakes.
local A = require("assert")
local Scenario = require("scenario")

local MENU_ADDONS_DIR = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or ".") .. "/fixtures/addons"

-- A retail scenario world (no login), always destroyed.
local function withMenuScenario(fn)
  local s = Scenario.new({ addon = "Hover", root = MENU_ADDONS_DIR .. "/Hover", flavor = "retail" })
  local ok, err = pcall(fn, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

-- Opens a UIDropDownMenu menu: a colored title, Open, Locked (disabled), More (submenu with Nested). picks records func calls.
local function openMenuFixture(picks)
  local dd = _G.CreateFrame("Frame", "MenuStepDD", _G.UIParent, "UIDropDownMenuTemplate")
  local function add(text, fields)
    local info = _G.UIDropDownMenu_CreateInfo()
    info.text = text
    for k, v in pairs(fields) do
      info[k] = v
    end
    _G.UIDropDownMenu_AddButton(info, 1)
  end
  local function record(name)
    return function()
      picks[#picks + 1] = name
    end
  end
  _G.UIDropDownMenu_Initialize(dd, function(_, level, menuList)
    if level == 2 then
      add(menuList[1], { notCheckable = true, func = record(menuList[1]) })
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

-- The title's text is "|cff00ff00Head|r": matching "Head" proves the color escapes are stripped, and the error proves it matched.
local function test_pick_title_throws_mouse_disabled()
  withMenuScenario(function(s)
    openMenuFixture({})
    A.errors(function()
      s:pick("Head")
    end, "pick: mouse disabled")
  end)
end

local function test_pick_divider_throws_mouse_disabled()
  withMenuScenario(function(s)
    local MenuFrames = require("framexml.fakes.menu_frames")
    local level = {
      namePrefix = "DropDownList1",
      entries = { { kind = "divider", text = "sep", enabled = true, checked = false, hasSubmenu = false } },
      pick = function() end,
      openSubmenu = function() end,
    }
    MenuFrames.open(s.w, 1, level)
    A.errors(function()
      s:pick("sep")
    end, "pick: mouse disabled")
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

local function test_pick_with_an_empty_path_throws()
  withMenuScenario(function(s)
    openMenuFixture({})
    A.errors(function()
      s:pick({})
    end, "pick: empty path")
  end)
end

return function()
  test_pick_with_an_empty_path_throws()
  test_menu_is_nil_when_no_menu_is_open()
  test_menu_returns_levels_with_copied_entries_and_the_same_frames()
  test_pick_clicks_the_matching_level_one_entry()
  test_pick_path_enters_the_submenu_then_clicks_the_last()
  test_pick_unknown_text_throws_listing_the_entries()
  test_pick_ambiguous_text_throws()
  test_pick_title_throws_mouse_disabled()
  test_pick_divider_throws_mouse_disabled()
  test_pick_disabled_entry_throws_disabled()
  test_pick_with_no_menu_open_throws()
  test_pick_path_through_an_entry_without_a_submenu_throws()
  test_close_menus_hides_every_level()
end
