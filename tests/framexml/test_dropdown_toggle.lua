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

return function()
  test_an_addon_error_without_a_position_in_a_submenu_init_is_recorded_unchanged()
  test_an_addon_error_with_a_position_in_a_submenu_init_is_recorded_unchanged()
end
