-- Menu steps when a UIDropDownMenu list is shown above a closed level 1.
local A = require("assert")
local Scenario = require("scenario")

local MENU_ADDONS_DIR = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or ".") .. "/fixtures/addons"

local function withMenuScenario(fn)
  local s = Scenario.new({ addon = "Hover", root = MENU_ADDONS_DIR .. "/Hover", flavor = "retail" })
  local ok, err = pcall(fn, s)
  s.w:destroy()
  if not ok then
    error(err, 0)
  end
end

-- Opens levels 1 and 2, closes them, then toggles level 2 alone (Mainline UIDropDownMenu.lua:1049-1202), so w.menus
-- has a hole at 1 in an array part that once held two levels.
local function openLevelTwoAlone(w)
  local dd = _G.CreateFrame("Frame", "GapDD", _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(dd, function(_, level)
    local info = _G.UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable, info.hasArrow = "L" .. (level or 1), true, level == 1
    _G.UIDropDownMenu_AddButton(info, level)
  end, "MENU")
  _G.ToggleDropDownMenu(1, nil, dd)
  _G.ToggleDropDownMenu(2, nil, nil, nil, nil, nil, nil, w.menus[1].entries[1].frame)
  _G.CloseDropDownMenus()
  _G.ToggleDropDownMenu(2, nil, dd, nil, nil, nil, nil, _G.CreateFrame("Button", "GapAnchor", dd))
end

-- A pick path starts at level 1, so with level 1 closed there is no menu to walk.
local function test_pick_with_only_a_deeper_level_open_throws_no_menu_is_open()
  withMenuScenario(function(s)
    openLevelTwoAlone(s.w)
    A.eq(_G.DropDownList2:IsShown(), true)
    A.errors(function()
      s:pick("L2")
    end, "pick: no menu is open")
  end)
end

return function()
  test_pick_with_only_a_deeper_level_open_throws_no_menu_is_open()
end
