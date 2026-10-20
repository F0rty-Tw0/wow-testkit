-- framexml/fakes/tooltip_unit.lua: the Classic Hide and SetShown wrappers that forget the tooltip's unit (row T3).
local A = require("assert")
local HF = require("tests.helpers.framexml")

local BOB = { name = "Bob", isPlayer = true, guid = "G" }

local function withClassicMouseover(fn)
  HF.withUnits("vanilla", function(w)
    w:unit("mouseover", BOB)
    fn(_G.GameTooltip)
  end)
end

local function test_classic_hide_on_a_non_widget_raises_the_kit_error()
  withClassicMouseover(function(tooltip)
    for _, name in ipairs({ "Hide", "SetShown" }) do
      A.errors(function()
        tooltip[name]({}, false)
      end, "GameTooltip:" .. name .. ": self is not a widget of this world")
    end
  end)
end

-- Only a shown-to-hidden change forgets the unit: Hide on a tooltip never shown since SetUnit is no change.
local function test_classic_hide_of_a_never_shown_tooltip_keeps_the_unit_assumed()
  withClassicMouseover(function(tooltip)
    tooltip:SetUnit("mouseover")
    tooltip:Hide()
    A.same({ tooltip:GetUnit() }, { "Bob", "mouseover" })
  end)
end

return function()
  test_classic_hide_on_a_non_widget_raises_the_kit_error()
  test_classic_hide_of_a_never_shown_tooltip_keeps_the_unit_assumed()
end
