-- framexml/fakes/tooltip_unit.lua: the Classic Hide and SetShown wrappers that forget the tooltip's unit (row T3).
local A = require("assert")
local HF = require("tests.helpers.framexml")

local BOB = { name = "Bob", isPlayer = true, guid = "G" }

local function withClassicMouseover(fn, flavor)
  HF.withUnits(flavor or "vanilla", function(w)
    w:unit("mouseover", BOB)
    fn(_G.GameTooltip)
  end)
end

-- The error names the caller's line, as the unwrapped class method does, not the wrapper's.
local function test_classic_hide_on_a_non_widget_raises_the_kit_error_at_the_caller()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists" }) do
    withClassicMouseover(function(tooltip)
      for _, name in ipairs({ "Hide", "SetShown" }) do
        local message = A.errors(function()
          tooltip[name]({}, false)
        end, "GameTooltip:" .. name .. ": self is not a widget of this world")
        A.truthy(message:find("test_tooltip_unit%.lua:%d+: GameTooltip:" .. name), flavor .. ": " .. message)
      end
    end, flavor)
  end
end

-- Only a shown-to-hidden change forgets the unit: Hide on a tooltip never shown since SetUnit is no change.
local function test_classic_hide_of_a_never_shown_tooltip_keeps_the_unit_assumed()
  withClassicMouseover(function(tooltip)
    tooltip:SetUnit("mouseover")
    tooltip:Hide()
    A.same({ tooltip:GetUnit() }, { "Bob", "mouseover" })
  end)
end

-- An ancestor's hide counts as the tooltip's hide: it fires the tooltip's OnHide (ui/behaviour.lua fireVisibility), so
-- the C unit goes as for the tooltip's own Hide, whatever its scripts; showing the ancestor again does not bring it back.
local function test_classic_ancestor_hide_forgets_the_unit_assumed()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists" }) do
    withClassicMouseover(function(tooltip)
      tooltip:SetScript("OnHide", function() end)
      tooltip:SetUnit("mouseover")
      tooltip:Show()
      _G.UIParent:Hide()
      A.eq(select("#", tooltip:GetUnit()), 0, flavor)
      _G.UIParent:Show()
      A.eq(select("#", tooltip:GetUnit()), 0, flavor)
    end, flavor)
  end
end

-- An ancestor hide of a tooltip that is not visible changes nothing, so the unit stays.
local function test_classic_ancestor_hide_of_a_hidden_tooltip_keeps_the_unit_assumed()
  withClassicMouseover(function(tooltip)
    tooltip:SetUnit("mouseover")
    _G.UIParent:Hide()
    A.same({ tooltip:GetUnit() }, { "Bob", "mouseover" })
  end)
end

-- Only a hide forgets: showing the tooltip, and showing its ancestor again, keep the unit.
local function test_classic_show_keeps_the_unit_assumed()
  withClassicMouseover(function(tooltip)
    tooltip:SetUnit("mouseover")
    tooltip:Show()
    A.same({ tooltip:GetUnit() }, { "Bob", "mouseover" })
    tooltip:Hide()
    _G.UIParent:Hide()
    tooltip:SetUnit("mouseover")
    tooltip:Show()
    _G.UIParent:Show()
    A.same({ tooltip:GetUnit() }, { "Bob", "mouseover" })
  end)
end

-- An OnHide that sets the unit and shows the tooltip again ends with a shown tooltip, which keeps the new unit; an
-- OnHide hook still reads the unit during an ancestor's hide, as the kit forgets only after the scripts.
local function test_classic_on_hide_that_shows_again_keeps_the_unit_assumed()
  withClassicMouseover(function(tooltip)
    tooltip:SetUnit("mouseover")
    tooltip:Show()
    tooltip:SetScript("OnHide", function(self)
      self:SetUnit("mouseover")
      self:Show()
    end)
    tooltip:Hide()
    A.same({ tooltip:GetUnit() }, { "Bob", "mouseover" })
    local seen
    tooltip:SetScript("OnHide", nil)
    tooltip:HookScript("OnHide", function(self)
      seen = { self:GetUnit() }
    end)
    _G.UIParent:Hide()
    A.same(seen, { "Bob", "mouseover" })
    A.eq(select("#", tooltip:GetUnit()), 0)
  end)
end

-- The tooltip's own Hide forgets even while a hidden ancestor keeps it invisible: no OnHide fires then, so only the
-- Hide wrapper sees the shown-to-hidden change.
local function test_classic_own_hide_under_a_hidden_ancestor_forgets_the_unit_assumed()
  withClassicMouseover(function(tooltip)
    _G.UIParent:Hide()
    tooltip:Show()
    tooltip:SetUnit("mouseover")
    tooltip:Hide()
    A.eq(select("#", tooltip:GetUnit()), 0)
  end)
end

-- Mainline GameTooltipTemplate has <OnHide function="GameTooltip_OnHide"/> (Blizzard_GameTooltip/Mainline/
-- GameTooltip.xml:27 on live and forever), so a tooltip made from it forgets its unit on hide as GameTooltip does.
local function test_mainline_template_tooltip_forgets_the_unit_on_hide()
  for _, flavor in ipairs({ "retail", "forever" }) do
    withClassicMouseover(function(tooltip)
      local made = _G.CreateFrame("GameTooltip", "MadeTooltip", _G.UIParent, "GameTooltipTemplate")
      A.eq(type(_G.GameTooltip_OnHide), "function", flavor)
      A.eq(made:GetScript("OnHide"), _G.GameTooltip_OnHide, flavor)
      A.eq(made.StatusBar:GetObjectType(), "StatusBar", flavor)
      A.eq(tooltip:GetScript("OnHide"), _G.GameTooltip_OnHide, flavor)
      made:SetUnit("mouseover")
      made:Show()
      made:Hide()
      A.eq(select("#", made:GetUnit()), 0, flavor)
    end, flavor)
  end
end

return function()
  test_mainline_template_tooltip_forgets_the_unit_on_hide()
  test_classic_hide_on_a_non_widget_raises_the_kit_error_at_the_caller()
  test_classic_hide_of_a_never_shown_tooltip_keeps_the_unit_assumed()
  test_classic_ancestor_hide_forgets_the_unit_assumed()
  test_classic_ancestor_hide_of_a_hidden_tooltip_keeps_the_unit_assumed()
  test_classic_show_keeps_the_unit_assumed()
  test_classic_on_hide_that_shows_again_keeps_the_unit_assumed()
  test_classic_own_hide_under_a_hidden_ancestor_forgets_the_unit_assumed()
end
