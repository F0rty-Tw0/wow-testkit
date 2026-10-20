-- UIDropDownMenu fake levels: which DropDownList an AddButton lands in.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function addItem(text, level)
  local info = _G.UIDropDownMenu_CreateInfo()
  info.text, info.notCheckable = text, true
  _G.UIDropDownMenu_AddButton(info, level)
end

local function texts(level)
  local out = {}
  for i, e in ipairs(level.entries) do
    out[i] = e.text
  end
  return out
end

-- A dropdown whose init calls add(level) at every level; returns the frame.
local function newDropdown(add)
  local frame = _G.CreateFrame("Frame", "LevelsDD", _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(frame, function(_, level)
    add(level or 1)
  end, "MENU")
  return frame
end

-- AddButton appends to DropDownList<level or 1> (Mainline UIDropDownMenu.lua:421-439, Classic :380-396): a level-2
-- init that leaves out the level adds to the shown list 1, and list 2 stays empty, so no submenu opens (S10).
local function test_add_button_without_a_level_in_a_submenu_init_joins_level_one()
  withFrameXML("retail", function(w)
    local frame = newDropdown(function(level)
      if level == 2 then
        addItem("Stray")
        return
      end
      local info = _G.UIDropDownMenu_CreateInfo()
      info.text, info.notCheckable, info.hasArrow = "More", true, true
      _G.UIDropDownMenu_AddButton(info, 1)
    end)
    _G.ToggleDropDownMenu(1, nil, frame)
    Input.enter(w, w.menus[1].entries[1].frame)
    A.eq(#w.menus, 1)
    A.same(texts(w.menus[1]), { "More", "Stray" })
    A.eq(_G.DropDownList1Button2:IsShown(), true)
  end)
end

-- Toggle hid list 2 (S12), and its own Toggle clears it before init (S4), so the entry never shows.
local function test_add_button_to_a_deeper_level_during_a_level_one_build_is_dropped()
  withFrameXML("retail", function(w)
    local frame = newDropdown(function(level)
      if level == 1 then
        addItem("One", 1)
        addItem("Two", 2)
      end
    end)
    _G.ToggleDropDownMenu(1, nil, frame)
    A.eq(#w.menus, 1)
    A.same(texts(w.menus[1]), { "One" })
  end)
end

-- S5: with no build running the entry still joins the list for its level when that list is shown.
local function test_add_button_outside_a_build_joins_the_shown_list()
  withFrameXML("retail", function(w)
    local frame = newDropdown(function(level)
      addItem("One", level)
    end)
    _G.ToggleDropDownMenu(1, nil, frame)
    addItem("Late", 1)
    A.same(texts(w.menus[1]), { "One", "Late" })
    A.eq(w.menus[1].entries[2].frame, _G.DropDownList1Button2)
    A.eq(_G.DropDownList1Button2:IsShown(), true)
  end)
end

-- Mainline UIDropDownMenu.lua:4, Classic :5.
local function test_max_levels_starts_at_the_client_value()
  for flavor, levels in pairs({ retail = 3, forever = 3, mists = 2, vanilla = 2, tbc = 2 }) do
    withFrameXML(flavor, function()
      A.eq(rawget(_G, "UIDROPDOWNMENU_MAXLEVELS"), levels, flavor)
    end)
  end
end

-- Opens a chain of submenus down to depth; each level has one entry "L<level>" with an arrow above depth.
local function openChain(w, depth)
  local frame = newDropdown(function(level)
    local info = _G.UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable, info.hasArrow = "L" .. level, true, level < depth
    _G.UIDropDownMenu_AddButton(info, level)
  end)
  _G.ToggleDropDownMenu(1, nil, frame)
  for level = 1, depth - 1 do
    Input.enter(w, w.menus[level].entries[1].frame)
  end
end

-- UIDropDownMenu_CreateFrames (Mainline :342-356, Classic :301-315), called by ToggleDropDownMenu (Mainline
-- :1053-1055, Classic :994-996), raises UIDROPDOWNMENU_MAXLEVELS and creates DropDownList<n> for a deeper level.
local function test_toggle_past_the_last_list_creates_it()
  withFrameXML("retail", function(w)
    openChain(w, 4)
    A.eq(#w.menus, 4)
    A.eq(w.menus[4].frame, _G.DropDownList4)
    A.eq(_G.DropDownList4:GetObjectType(), "Button")
    A.eq(_G.DropDownList4:IsShown(), true)
    A.eq(rawget(_G, "UIDROPDOWNMENU_MAXLEVELS"), 4)
  end)
end

local function test_classic_toggle_to_level_three_raises_max_levels()
  withFrameXML("vanilla", function(w)
    openChain(w, 3)
    A.eq(#w.menus, 3)
    A.eq(rawget(_G, "UIDROPDOWNMENU_MAXLEVELS"), 3)
  end)
end

-- A Button under frame, the 8th ToggleDropDownMenu argument the client needs past level 1 (Mainline :1168).
local function anchorOn(frame)
  return _G.CreateFrame("Button", "LevelsAnchor", frame)
end

-- ToggleDropDownMenu does not look at the lower lists (Mainline :1049-1202, Classic :990-1139): list 2 shows alone.
local function test_toggle_to_level_two_with_level_one_closed_shows_list_two_alone()
  withFrameXML("retail", function(w)
    local frame = newDropdown(function(level)
      addItem("L" .. level, level)
    end)
    _G.ToggleDropDownMenu(2, nil, frame, nil, nil, nil, nil, anchorOn(frame))
    A.eq(w.menus[1], nil)
    A.same(texts(w.menus[2]), { "L2" })
    A.eq(_G.DropDownList1:IsShown(), false)
    A.eq(_G.DropDownList2:IsShown(), true)
    _G.CloseDropDownMenus()
    A.eq(next(w.menus), nil)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

-- A level-1 Toggle sets UIDROPDOWNMENU_OPEN_MENU before init (Mainline :1095) and an empty list never shows, so
-- OPEN_MENU stays; a level-2 Toggle without a frame then uses it (Mainline :1163-1165, Classic :1102-1104).
local function test_toggle_without_a_frame_uses_the_open_menu_when_level_one_is_closed()
  withFrameXML("retail", function(w)
    local frame = newDropdown(function(level)
      if level == 2 then
        addItem("Deep", 2)
      end
    end)
    _G.ToggleDropDownMenu(1, nil, frame)
    _G.ToggleDropDownMenu(2, nil, nil, nil, nil, nil, nil, anchorOn(frame))
    A.eq(w.menus[2].owner, frame)
    A.same(texts(w.menus[2]), { "Deep" })
  end)
end

-- The Initialize helper hides every DropDownList for a frame that is not the open menu (Mainline :41-65).
local function test_initialize_hides_a_list_shown_above_a_closed_level()
  withFrameXML("retail", function(w)
    local frame = newDropdown(function(level)
      addItem("L" .. level, level)
    end)
    _G.ToggleDropDownMenu(2, nil, frame, nil, nil, nil, nil, anchorOn(frame))
    _G.UIDropDownMenu_Initialize(frame, nil, "MENU")
    A.eq(next(w.menus), nil)
    A.eq(_G.DropDownList2:IsShown(), false)
  end)
end

return function()
  test_toggle_to_level_two_with_level_one_closed_shows_list_two_alone()
  test_toggle_without_a_frame_uses_the_open_menu_when_level_one_is_closed()
  test_initialize_hides_a_list_shown_above_a_closed_level()
  test_max_levels_starts_at_the_client_value()
  test_toggle_past_the_last_list_creates_it()
  test_classic_toggle_to_level_three_raises_max_levels()
  test_add_button_without_a_level_in_a_submenu_init_joins_level_one()
  test_add_button_to_a_deeper_level_during_a_level_one_build_is_dropped()
  test_add_button_outside_a_build_joins_the_shown_list()
end
