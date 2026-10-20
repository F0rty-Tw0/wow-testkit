-- UIDropDownMenu fake globals: UIDROPDOWNMENU_OPEN_MENU, _INIT_MENU, _MENU_LEVEL and _MENU_VALUE as the client sets them.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function global(name)
  return rawget(_G, name)
end

local function addItem(text, fields, level)
  local info = _G.UIDropDownMenu_CreateInfo()
  info.text = text
  for k, v in pairs(fields or {}) do
    info[k] = v
  end
  _G.UIDropDownMenu_AddButton(info, level)
end

-- A dropdown with More (submenu, value "more") at level 1 and Nested at level 2; seen[level] records the globals
-- each init call saw.
local function newDropdown(seen, name)
  local frame = _G.CreateFrame("Frame", name or "GlobalsDD", _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(frame, function(_, level)
    seen[level or 1] = {
      open = global("UIDROPDOWNMENU_OPEN_MENU"),
      init = global("UIDROPDOWNMENU_INIT_MENU"),
      level = global("UIDROPDOWNMENU_MENU_LEVEL"),
      value = global("UIDROPDOWNMENU_MENU_VALUE"),
    }
    if level == 2 then
      addItem("Nested", { notCheckable = true }, 2)
      return
    end
    addItem("More", { notCheckable = true, hasArrow = true, value = "more" }, 1)
  end, "MENU")
  return frame
end

-- Mainline UIDropDownMenu.lua:8-14, Classic :9-15.
local function test_globals_start_at_the_client_values()
  withFrameXML("retail", function()
    A.eq(global("UIDROPDOWNMENU_MENU_LEVEL"), 1)
    A.eq(global("UIDROPDOWNMENU_OPEN_MENU"), nil)
    A.eq(global("UIDROPDOWNMENU_INIT_MENU"), nil)
    A.eq(global("UIDROPDOWNMENU_MENU_VALUE"), nil)
  end)
end

-- Toggle sets the level and value before init (Mainline :1056-1057, Classic :997-998); a level-1 Toggle makes its
-- frame the open menu (Mainline :1095, Classic :1034). Toggle runs init through UIDropDownMenu_Initialize (Mainline
-- :1193, Classic :1132), whose helper names the frame being initialized (Mainline :48, Classic :49), so INIT_MENU
-- is the toggled frame even after another frame's Initialize.
local function test_init_sees_the_globals_of_its_toggle()
  for _, flavor in ipairs({ "retail", "vanilla" }) do
    withFrameXML(flavor, function(w)
      local seen = {}
      local frame = newDropdown(seen)
      local other = _G.CreateFrame("Frame", "OtherGlobalsDD", _G.UIParent, "UIDropDownMenuTemplate")
      _G.UIDropDownMenu_Initialize(other, nil, "MENU")
      _G.ToggleDropDownMenu(1, nil, frame)
      rawset(_G, "UIDROPDOWNMENU_INIT_MENU", other)
      Input.enter(w, w.menus[1].entries[1].frame)
      A.same(seen[1], { open = frame, init = frame, level = 1 }, flavor)
      A.same(seen[2], { open = frame, init = frame, level = 2, value = "more" }, flavor)
    end)
  end
end

-- UIDropDownMenu_OnHide clears the open menu when list 1 hides (Mainline :1347-1349, Classic :1249-1251).
local function test_closing_level_one_clears_the_open_menu()
  withFrameXML("retail", function(w)
    local frame = newDropdown({})
    _G.ToggleDropDownMenu(1, nil, frame)
    Input.enter(w, w.menus[1].entries[1].frame)
    _G.CloseDropDownMenus(2)
    A.eq(global("UIDROPDOWNMENU_OPEN_MENU"), frame)
    _G.CloseDropDownMenus()
    A.eq(global("UIDROPDOWNMENU_OPEN_MENU"), nil)
  end)
end

-- InitializeHelper resets the level to 1 for a frame that is not the open menu (Mainline :43-45, Classic :44-46).
local function test_initialize_on_another_frame_resets_the_menu_level()
  withFrameXML("retail", function(w)
    local frame = newDropdown({})
    _G.ToggleDropDownMenu(1, nil, frame)
    Input.enter(w, w.menus[1].entries[1].frame)
    A.eq(global("UIDROPDOWNMENU_MENU_LEVEL"), 2)
    local other = _G.CreateFrame("Frame", "OtherGlobalsDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(other, nil, "MENU")
    A.eq(global("UIDROPDOWNMENU_MENU_LEVEL"), 1)
    A.eq(global("UIDROPDOWNMENU_INIT_MENU"), other)
    A.eq(global("UIDROPDOWNMENU_OPEN_MENU"), nil)
  end)
end

-- Opens open's list 1, then Toggles level 2 on frame (not the open menu); during records what frame's init saw.
local function toggleAnotherFrameAtLevelTwo()
  local during
  local frame = _G.CreateFrame("Frame", "DeepGlobalsDD", _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(frame, function(_, level)
    during = { level = global("UIDROPDOWNMENU_MENU_LEVEL"), list1 = _G.DropDownList1:IsShown() }
    addItem("Deep", { notCheckable = true }, level)
  end, "MENU")
  _G.ToggleDropDownMenu(1, nil, newDropdown({}, "OpenGlobalsDD"))
  during = nil
  _G.ToggleDropDownMenu(2, "v", frame, nil, nil, nil, nil, _G.CreateFrame("Button", "DeepGlobalsAnchor", frame))
  return during
end

-- Toggle runs the helper through UIDropDownMenu_Initialize (Mainline :1193, Classic :1132): for a frame that is not
-- the open menu it resets the level to 1 and hides every list before init (Mainline :43-45, :52-63; Classic :44-46,
-- :53-64).
local function test_toggle_on_another_frame_at_level_two_runs_init_at_menu_level_one()
  withFrameXML("retail", function(w)
    A.same(toggleAnotherFrameAtLevelTwo(), { level = 1, list1 = false })
    A.eq(w.menus[2].entries[1].text, "Deep")
  end)
end

-- The same helper hides the open menu's list 1, whose OnHide clears UIDROPDOWNMENU_OPEN_MENU (S14).
local function test_toggle_on_another_frame_at_level_two_closes_the_open_menu()
  withFrameXML("retail", function(w)
    toggleAnotherFrameAtLevelTwo()
    A.eq(w.menus[1], nil)
    A.eq(_G.DropDownList1:IsShown(), false)
    A.eq(global("UIDROPDOWNMENU_OPEN_MENU"), nil)
  end)
end

return function()
  test_globals_start_at_the_client_values()
  test_init_sees_the_globals_of_its_toggle()
  test_toggle_on_another_frame_at_level_two_runs_init_at_menu_level_one()
  test_toggle_on_another_frame_at_level_two_closes_the_open_menu()
  test_closing_level_one_clears_the_open_menu()
  test_initialize_on_another_frame_resets_the_menu_level()
end
