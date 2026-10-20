-- UIDropDownMenu fake: which list a Toggle or Initialize opens or fills, and the errors they raise or record.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HM = require("tests.helpers.menu")
local Input = require("input")

local withFrameXML = HF.withFrameXML

local addItem = HM.addFields

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

-- A misuse error that already names the init's line is not the kit's position-less one, so the entry's name is not
-- added in front of it.
local function test_a_toggle_misuse_in_a_submenu_init_keeps_its_caller_line()
  local message = recordedSubmenuError(function()
    _G.ToggleDropDownMenu(1)
  end)
  A.truthy(message:find("^tests[/\\]framexml[/\\]test_dropdown_toggle%.lua:%d+: ToggleDropDownMenu: "), message)
  A.eq(message:find("OnEnter: ", 1, true), nil)
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

-- Initialize stores and calls init only when it is truthy (Mainline :83-86, Classic :82-85), so false keeps the
-- frame's earlier init.
local function test_initialize_with_a_false_init_keeps_the_earlier_one()
  for _, flavor in ipairs({ "retail", "vanilla" }) do
    withFrameXML(flavor, function(w)
      local frame = newDropdown("FalseInitDD")
      _G.UIDropDownMenu_Initialize(frame, false)
      _G.ToggleDropDownMenu(1, nil, frame)
      A.eq(w.menus[1].entries[1].text, "More", flavor)
    end)
  end
end

return function()
  test_initialize_with_a_false_init_keeps_the_earlier_one()
  test_initialize_at_a_level_with_no_list_names_the_caller_assumed()
  test_a_hooked_toggle_misuse_error_names_the_caller()
  test_initialize_on_the_open_frame_after_a_submenu_adds_to_the_shown_list_one()
  test_toggle_on_another_frame_while_list_one_is_shown_opens_it_for_that_frame()
  test_an_addon_error_without_a_position_in_a_submenu_init_is_recorded_unchanged()
  test_an_addon_error_with_a_position_in_a_submenu_init_is_recorded_unchanged()
  test_a_toggle_misuse_in_a_submenu_init_keeps_its_caller_line()
end
