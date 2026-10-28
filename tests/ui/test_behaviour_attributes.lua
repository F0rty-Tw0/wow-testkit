-- SetAttribute / GetAttribute: any value per attribute name, OnAttributeChanged, unchecked value argument.
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets

local function test_set_attribute_accepts_a_boolean_from_addon_code()
  withWidgets("retail", function(w)
    local button = _G.CreateFrame("Button")
    w:run("addon", function()
      button:SetAttribute("useOnKeyDown", true)
    end)
  end)
end

local function test_attribute_name_is_still_checked()
  withWidgets("retail", function(w)
    local button = _G.CreateFrame("Button")
    local message = A.errors(function()
      w:run("addon", function()
        button:SetAttribute(true, "x")
      end)
    end, "bad argument #1 'attributeName' (string expected, got boolean)")
    A.contains(message, "Button:SetAttribute")
  end)
end

local function test_get_attribute_returns_the_value_for_that_name()
  withWidgets("retail", function()
    local button = _G.CreateFrame("Button")
    button:SetAttribute("a", 1)
    button:SetAttribute("b", true)
    A.eq(button:GetAttribute("a"), 1)
    A.eq(button:GetAttribute("b"), true)
    A.eq(button:GetAttribute("c"), nil)
  end)
end

-- source: wiki API_Frame_SetAttribute, attributeName "(case-insensitive)"
local function test_attribute_names_are_case_insensitive()
  withWidgets("retail", function()
    local button = _G.CreateFrame("Button")
    button:SetAttribute("useOnKeyDown", true)
    A.eq(button:GetAttribute("USEONKEYDOWN"), true)
  end)
end

-- source: wiki UIHANDLER_OnAttributeChanged, "(self, name, value)", name "The lowercased name"
local function test_set_attribute_fires_on_attribute_changed()
  withWidgets("retail", function()
    local button = _G.CreateFrame("Button")
    local calls = {}
    button:SetScript("OnAttributeChanged", function(...)
      calls[#calls + 1] = { ... }
    end)
    button:SetAttribute("a", 1)
    button:SetAttribute("UseOnKeyDown", true)
    A.eq(#calls, 2)
    A.same({ calls[1][1] == button, calls[1][2], calls[1][3] }, { true, "a", 1 })
    A.same({ calls[2][1] == button, calls[2][2], calls[2][3] }, { true, "useonkeydown", true })
  end)
end

local function test_get_attribute_is_not_counted_as_unscripted()
  withWidgets("retail", function(w)
    local button = _G.CreateFrame("Button")
    button:SetAttribute("a", 1)
    button:GetAttribute("a")
    A.eq(w.unscripted["Button:GetAttribute"], nil)
    A.eq(w.unscripted["Button:SetAttribute"], nil)
  end)
end

-- The error and its text are assumed (row A3): no source shows the client's message for a nil name.
local function nilNameError(call)
  local ok, err = pcall(call)
  A.eq(ok, false)
  return tostring(err)
end

local function at(line)
  return "test_behaviour_attributes%.lua:" .. line .. ": "
end

local function test_nil_attribute_name_raises_at_the_callers_line_assumed()
  withWidgets("retail", function(w)
    local button = _G.CreateFrame("Button")
    local line
    local err = nilNameError(function()
      line = debug.getinfo(1, "l").currentline + 1
      button:SetAttribute(nil, 1)
    end)
    A.truthy(err:find(at(line) .. "SetAttribute: attributeName must be a string"), err)
    err = nilNameError(function()
      line = debug.getinfo(1, "l").currentline + 1
      button:GetAttribute(nil)
    end)
    A.truthy(err:find(at(line) .. "GetAttribute: attributeName must be a string"), err)
    err = nilNameError(function()
      w:run("addon", function()
        button:SetAttribute(nil, 1)
      end)
    end)
    A.contains(err, "SetAttribute: attributeName must be a string")
  end)
end

-- source: wiki API_Frame_SetAttribute ("triggers the OnAttributeChanged script handler"; SetAttributeNoHandler does not), Task 12.4
-- real check: blizzard_uiparentpanelmanager sets UIPanelLayout-* with it and ShowUIPanel reads them back.
local function test_set_attribute_no_handler_stores_without_the_handler()
  withWidgets("retail", function()
    local frame, seen = _G.CreateFrame("Frame"), {}
    frame:SetScript("OnAttributeChanged", function(_, name)
      seen[#seen + 1] = name
    end)
    frame:SetAttributeNoHandler("UIPanelLayout-Area", "left")
    A.same({ frame:GetAttribute("uipanellayout-area"), seen }, { "left", {} })
  end)
end

return function()
  test_set_attribute_no_handler_stores_without_the_handler()
  test_nil_attribute_name_raises_at_the_callers_line_assumed()
  test_set_attribute_accepts_a_boolean_from_addon_code()
  test_attribute_name_is_still_checked()
  test_get_attribute_returns_the_value_for_that_name()
  test_attribute_names_are_case_insensitive()
  test_set_attribute_fires_on_attribute_changed()
  test_get_attribute_is_not_counted_as_unscripted()
end
