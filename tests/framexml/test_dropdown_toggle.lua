-- UIDropDownMenu fake: which list a Toggle or Initialize opens or fills, and the errors they raise or record.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local function addItem(text, fields, level)
  local info = _G.UIDropDownMenu_CreateInfo()
  info.text = text
  for k, v in pairs(fields or {}) do
    info[k] = v
  end
  _G.UIDropDownMenu_AddButton(info, level)
end

-- A dropdown whose level-1 init adds More (a submenu) and whose level-2 init runs submenu(); returns the frame.
local function newDropdown(name, submenu)
  local frame = _G.CreateFrame("Frame", name, _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(frame, function(_, level)
    if level == 2 then
      submenu()
      return
    end
    addItem("More", { notCheckable = true, hasArrow = true }, 1)
  end, "MENU")
  return frame
end

-- Records the error a level-2 init raises when More is entered.
local function recordedSubmenuError(submenu)
  local message
  withFrameXML("retail", function(w)
    _G.ToggleDropDownMenu(1, nil, newDropdown("SubErrorDD", submenu))
    Input.enter(w, w.menus[1].entries[1].frame)
    A.eq(#w.errors, 1)
    message = w.errors[1].message
  end)
  return message
end

-- Only the kit's own position-less ToggleDropDownMenu errors get the entry's name; an addon's error, with or without
-- a position, is recorded as the client records it.
local function test_an_addon_error_without_a_position_in_a_submenu_init_is_recorded_unchanged()
  A.eq(
    recordedSubmenuError(function()
      error("x", 0)
    end),
    "x"
  )
end

local function test_an_addon_error_with_a_position_in_a_submenu_init_is_recorded_unchanged()
  local message = recordedSubmenuError(function()
    error("x")
  end)
  A.truthy(message:find("^tests[/\\]framexml[/\\]test_dropdown_toggle%.lua:%d+: x$"), message)
end

-- S1 closes only when the open menu is the toggled frame (Mainline :1069, Classic :1008): a Toggle on another frame
-- while list 1 is shown reopens list 1 for that frame.
local function test_toggle_on_another_frame_while_list_one_is_shown_opens_it_for_that_frame()
  withFrameXML("retail", function(w)
    local first = newDropdown("FirstToggleDD")
    local second = _G.CreateFrame("Frame", "SecondToggleDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(second, function(_, level)
      addItem("Second", { notCheckable = true }, level)
    end, "MENU")
    _G.ToggleDropDownMenu(1, nil, first)
    _G.ToggleDropDownMenu(1, nil, second)
    A.eq(_G.DropDownList1:IsShown(), true)
    A.eq(w.menus[1].owner, second)
    A.eq(w.menus[1].entries[1].text, "Second")
  end)
end

-- After a submenu Toggle, Initialize on the open menu's frame hides only lists 2 and deeper (Mainline :54, Classic
-- :55), and AddButton appends to the still-shown list 1 (Mainline :426, Classic :385), not to the build.
local function test_initialize_on_the_open_frame_after_a_submenu_adds_to_the_shown_list_one()
  withFrameXML("retail", function(w)
    local frame = newDropdown("ShownListDD", function()
      addItem("Nested", { notCheckable = true }, 2)
    end)
    _G.ToggleDropDownMenu(1, nil, frame)
    Input.enter(w, w.menus[1].entries[1].frame)
    _G.UIDropDownMenu_Initialize(frame, function()
      addItem("New", { notCheckable = true }, 1)
    end)
    A.eq(_G.DropDownList2:IsShown(), false)
    A.eq(w.menus[1].entries[1].text, "More")
    A.eq(w.menus[1].entries[2] and w.menus[1].entries[2].text, "New")
  end)
end

-- hooksecurefunc's wrapper (luaext.lua) sits between the caller and the fake; the error still names the caller.
local function test_a_hooked_toggle_misuse_error_names_the_caller()
  withFrameXML("retail", function()
    _G.hooksecurefunc("ToggleDropDownMenu", function() end)
    local message = A.errors(function()
      _G.ToggleDropDownMenu(1)
    end, "no dropdown frame")
    A.truthy(message:find("^tests[/\\]framexml[/\\]test_dropdown_toggle%.lua:%d+: ToggleDropDownMenu: "), message)
  end)
end

-- C_Timer calls the callback from C in the client, so no Lua line called the fake; the kit's timer closure is in
-- luaext.lua, which callsite.lua skips whole, so the walk ends past every Lua caller and the message has no position.
local function test_a_toggle_misuse_error_from_a_timer_has_no_position_assumed() -- (S22)
  withFrameXML("retail", function(w)
    _G.C_Timer.After(0, _G.ToggleDropDownMenu)
    w:advance(0)
    A.eq(#w.errors, 1)
    A.eq(w.errors[1].message, "ToggleDropDownMenu: no dropdown frame")
  end)
end

-- The client indexes DropDownList<level> after init (Mainline :93-94, Classic :92-93), so a level past
-- UIDROPDOWNMENU_MAXLEVELS whose init made no list errors there; the message and its caller line are the kit's.
local function test_initialize_at_a_level_with_no_list_names_the_caller_assumed()
  withFrameXML("retail", function()
    local frame = _G.CreateFrame("Frame", "NoListDD", _G.UIParent, "UIDropDownMenuTemplate")
    local message = A.errors(function()
      _G.UIDropDownMenu_Initialize(frame, nil, nil, 4)
    end, "UIDropDownMenu_Initialize: no DropDownList4")
    A.truthy(message:find("^tests[/\\]framexml[/\\]test_dropdown_toggle%.lua:%d+: "), message)
    _G.UIDropDownMenu_Initialize(frame, function(_, level)
      addItem("Five", { notCheckable = true }, level)
    end, nil, 5)
    A.eq(_G.DropDownList5.dropdown, frame)
  end)
end

return function()
  test_initialize_at_a_level_with_no_list_names_the_caller_assumed()
  test_a_hooked_toggle_misuse_error_names_the_caller()
  test_a_toggle_misuse_error_from_a_timer_has_no_position_assumed()
  test_initialize_on_the_open_frame_after_a_submenu_adds_to_the_shown_list_one()
  test_toggle_on_another_frame_while_list_one_is_shown_opens_it_for_that_frame()
  test_an_addon_error_without_a_position_in_a_submenu_init_is_recorded_unchanged()
  test_an_addon_error_with_a_position_in_a_submenu_init_is_recorded_unchanged()
end
