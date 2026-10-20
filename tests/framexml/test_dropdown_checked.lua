-- UIDropDownMenu fake: when AddButton reads a function-valued checked, what it writes back into the caller's info, and
-- the entry text it sets.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")
local Snapshot = require("snapshot")

local withFrameXML = HF.withFrameXML

-- A dropdown whose level-1 init adds one entry "C" with fields, then runs after(); returns the frame.
local function newDropdown(fields, after)
  local frame = _G.CreateFrame("Frame", "CheckedDD", _G.UIParent, "UIDropDownMenuTemplate")
  _G.UIDropDownMenu_Initialize(frame, function(_, level)
    if level ~= 1 then
      return
    end
    local info = _G.UIDropDownMenu_CreateInfo()
    info.text = "C"
    for k, v in pairs(fields) do
      info[k] = v
    end
    _G.UIDropDownMenu_AddButton(info, 1)
    if after then
      after()
    end
  end, "MENU")
  return frame
end

local function throwing()
  error("checked boom")
end

-- Mainline UIDropDownMenu.lua:689-692, Classic :640-643: AddButton calls it with the entry's Button, once.
local function test_function_checked_runs_inside_add_button_with_the_entry_button()
  withFrameXML("retail", function(w)
    local calls, got, callsAfterAdd = 0, nil, nil
    local frame = newDropdown({
      isNotRadio = true,
      checked = function(self)
        calls, got = calls + 1, self
        return true
      end,
    }, function()
      callsAfterAdd = calls
    end)
    _G.ToggleDropDownMenu(1, nil, frame)
    A.eq(callsAfterAdd, 1)
    A.eq(calls, 1)
    A.eq(got, _G.DropDownList1Button1)
    A.eq(w.menus[1].entries[1].frame, got)
    A.eq(w.menus[1].entries[1].checked, true)
  end)
end

-- The call sits inside `if not info.notCheckable` (Mainline :650, Classic :585).
local function test_function_checked_on_a_not_checkable_entry_is_not_called()
  withFrameXML("retail", function(w)
    local calls = 0
    local frame = newDropdown({
      notCheckable = true,
      checked = function()
        calls = calls + 1
        return true
      end,
    })
    _G.ToggleDropDownMenu(1, nil, frame)
    A.eq(calls, 0)
    A.eq(w.menus[1].entries[1].checked, false)
  end)
end

-- Unprotected inside init, so it fails the Toggle as an init error does (S4): nothing opens, nothing is recorded.
local function test_function_checked_error_reaches_the_toggle_caller()
  withFrameXML("retail", function(w)
    local frame = newDropdown({ isNotRadio = true, checked = throwing })
    A.errors(function()
      _G.ToggleDropDownMenu(1, nil, frame)
    end, "checked boom")
    A.eq(w.dropdown.building, nil)
    A.eq(next(w.menus), nil)
    A.same(w.errors, {})
  end)
end

-- From an addon's OnClick, either error is recorded once by the script call and the menu stays closed.
local function test_function_checked_error_in_a_click_handler_is_recorded_like_an_init_error()
  for _, fields in ipairs({ { init = throwing }, { checked = throwing } }) do
    withFrameXML("retail", function(w)
      local frame = newDropdown({ isNotRadio = true, checked = fields.checked }, fields.init)
      local button = _G.CreateFrame("Button", "CheckedOpener", _G.UIParent)
      button:SetScript("OnClick", function()
        _G.ToggleDropDownMenu(1, nil, frame)
      end)
      Input.click(w, button, "LeftButton")
      A.eq(#w.errors, 1)
      A.contains(tostring(w.errors[1].message), "checked boom")
      A.eq(next(w.menus), nil)
      A.eq(_G.DropDownList1:IsShown(), false)
    end)
  end
end

-- Mainline :460-469 (Classic :411-420) set info.disabled on the caller's table for notClickable and isTitle, so a
-- reused info keeps it; a disabled entry drops colorCode and disablecolor replaces it (Mainline :472-481, Classic
-- :423-432).
local function test_add_button_writes_disabled_and_color_code_into_the_callers_info()
  withFrameXML("retail", function(w)
    local reused, colored, greyed
    local frame = _G.CreateFrame("Frame", "WriteBackDD", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(frame, function(_, level)
      if level ~= 1 then
        return
      end
      reused = _G.UIDropDownMenu_CreateInfo()
      reused.text, reused.isTitle, reused.notCheckable = "Head", true, true
      _G.UIDropDownMenu_AddButton(reused, 1)
      reused.text, reused.isTitle, reused.func = "Item", nil, function() end
      _G.UIDropDownMenu_AddButton(reused, 1)
      colored = { text = "Label", notCheckable = true, notClickable = true, colorCode = "|cffff0000" }
      _G.UIDropDownMenu_AddButton(colored, 1)
      greyed = { text = "Grey", notCheckable = true, disablecolor = "|cff808080" }
      _G.UIDropDownMenu_AddButton(greyed, 1)
    end, "MENU")
    _G.ToggleDropDownMenu(1, nil, frame)
    A.eq(reused.disabled, true)
    A.eq(w.menus[1].entries[2].enabled, false)
    A.eq(colored.disabled, true)
    A.eq(colored.colorCode, nil)
    A.eq(greyed.colorCode, "|cff808080")
  end)
end

-- With info.text the Button text is colorCode .. text .. "|r" when colorCode is set, else the text (Mainline
-- :484-490, Classic :435-441); colorCode is read after a disabled entry dropped it and disablecolor replaced it.
local function test_color_code_wraps_the_entry_text()
  for _, flavor in ipairs({ "retail", "vanilla" }) do
    withFrameXML(flavor, function(w)
      local frame = _G.CreateFrame("Frame", "ColorDD", _G.UIParent, "UIDropDownMenuTemplate")
      _G.UIDropDownMenu_Initialize(frame, function()
        _G.UIDropDownMenu_AddButton({ text = "Red", notCheckable = true, colorCode = "|cffff0000" }, 1)
        _G.UIDropDownMenu_AddButton({ text = "Off", notCheckable = true, disabled = true, colorCode = "|cffff0000" }, 1)
        _G.UIDropDownMenu_AddButton({ text = "Grey", notCheckable = true, disabled = true, disablecolor = "|cff808080" }, 1)
      end, "MENU")
      _G.ToggleDropDownMenu(1, nil, frame)
      local entries = w.menus[1].entries
      A.eq(entries[1].text, "|cffff0000Red|r", flavor)
      A.eq(entries[1].frame.NormalText:GetText(), "|cffff0000Red|r", flavor)
      A.eq(entries[2].text, "Off", flavor)
      A.eq(entries[3].text, "|cff808080Grey|r", flavor)
      local expected = "[ff0000]Red\n[ffffff]Off (disabled)\n[808080]Grey (disabled)"
      A.eq(Snapshot.menu({ levels = w.menus }), expected, flavor)
    end)
  end
end

return function()
  test_color_code_wraps_the_entry_text()
  test_add_button_writes_disabled_and_color_code_into_the_callers_info()
  test_function_checked_runs_inside_add_button_with_the_entry_button()
  test_function_checked_on_a_not_checkable_entry_is_not_called()
  test_function_checked_error_reaches_the_toggle_caller()
  test_function_checked_error_in_a_click_handler_is_recorded_like_an_init_error()
end
