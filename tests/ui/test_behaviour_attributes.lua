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

return function()
  test_set_attribute_accepts_a_boolean_from_addon_code()
  test_attribute_name_is_still_checked()
  test_get_attribute_returns_the_value_for_that_name()
  test_attribute_names_are_case_insensitive()
  test_set_attribute_fires_on_attribute_changed()
  test_get_attribute_is_not_counted_as_unscripted()
end
