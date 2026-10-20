-- GameTooltip, GameTooltip_SetDefaultAnchor, TooltipDataProcessor and GameTooltip:SetUnit.
local A = require("assert")
local H = require("tests.helpers.world")
local HF = require("tests.helpers.framexml")
local FrameXML = require("framexml.fakes")

local MAGE = { name = "Bob", isPlayer = true, classFile = "MAGE", className = "Mage", raceName = "Orc", level = 80, guid = "G" }

local function withMouseover(flavor, fn)
  HF.withUnits(flavor, function(w)
    w:unit("mouseover", MAGE)
    fn(w, _G.GameTooltip)
  end)
end

local function leftTexts(tooltip)
  local out = {}
  for i = 1, tooltip:NumLines() do
    out[i] = _G["GameTooltipTextLeft" .. i]:GetText()
  end
  return out
end

local function unitType()
  return _G.Enum.TooltipDataType.Unit
end

local function test_post_call_sees_get_unit()
  withMouseover("retail", function(_, tooltip)
    local seen
    _G.TooltipDataProcessor.AddTooltipPostCall(unitType(), function(tip)
      seen = { tip:GetUnit() }
    end)
    tooltip:SetUnit("mouseover")
    A.same(seen, { "Bob", "mouseover", "G" })
  end)
end

-- Mainline GameTooltipDataMixin:GetUnit → TooltipUtil.GetDisplayedUnit (TooltipUtil.lua:34-41, live and forever):
-- name, UnitTokenFromGUID(guid), guid. Classic's GetUnit is the C method: name, unit (wiki API_GameTooltip_GetUnit).
local function test_get_unit_returns_the_guid_on_mainline_only()
  for flavor, expected in pairs({ retail = { "Bob", "mouseover", "G" }, forever = { "Bob", "mouseover", "G" }, vanilla = { "Bob", "mouseover" } }) do
    withMouseover(flavor, function(_, tooltip)
      tooltip:SetUnit("mouseover")
      A.same({ tooltip:GetUnit() }, expected, flavor)
    end)
  end
end

-- UnitTokenFromGUID tests "target" before "mouseover" (wiki API_UnitTokenFromGUID).
local function test_get_unit_token_comes_from_the_guid_on_mainline()
  HF.withUnits("retail", function(w)
    w:unit("target", MAGE)
    w:mouseover("target")
    _G.GameTooltip:SetUnit("mouseover")
    A.same({ _G.GameTooltip:GetUnit() }, { "Bob", "target", "G" })
  end)
end

-- GameTooltipTemplate's OnHide is GameTooltip_OnHide (Mainline GameTooltip.xml:27), which calls ClearHandlerInfo
-- (GameTooltip.lua:421; forever :430), so a hidden tooltip shows no unit.
-- Classic's GetUnit is C: wiki API_GameTooltip_GetUnit, "Returns nil when the tooltip is not shown". User decision
-- (row T3): the unit is forgotten when the tooltip goes from shown to hidden; a never-shown tooltip still answers.
local function test_classic_forgets_the_unit_when_the_shown_tooltip_hides_assumed()
  for _, hide in ipairs({ "Hide", "SetShown" }) do
    withMouseover("vanilla", function(_, tooltip)
      tooltip:SetScript("OnHide", function() end)
      tooltip:SetUnit("mouseover")
      A.same({ tooltip:GetUnit() }, { "Bob", "mouseover" }, hide)
      tooltip:Show()
      tooltip[hide](tooltip, false)
      A.eq(select("#", tooltip:GetUnit()), 0, hide)
    end)
  end
end

local function test_hiding_the_tooltip_forgets_the_unit_on_mainline()
  withMouseover("forever", function(_, tooltip)
    tooltip:SetUnit("mouseover")
    tooltip:Show()
    tooltip:Hide()
    A.eq(select("#", tooltip:GetUnit()), 0)
  end)
end

local function test_line_pre_call_true_drops_the_line()
  withMouseover("retail", function(_, tooltip)
    _G.TooltipDataProcessor.AddLinePreCall(_G.TooltipDataProcessor.AllTypes, function(_, line)
      return line.leftText == "Level 80 Orc Mage"
    end)
    tooltip:SetUnit("mouseover")
    A.same(leftTexts(tooltip), { "Bob" })
  end)
end

local function test_processing_info_only_while_processing()
  withMouseover("retail", function(_, tooltip)
    local info
    _G.TooltipDataProcessor.AddTooltipPreCall(unitType(), function(tip)
      info = tip:GetProcessingTooltipInfo()
    end)
    tooltip:SetUnit("mouseover")
    A.eq(info.tooltipData.guid, "G")
    A.eq(info.getterName, "GetUnit")
    A.same(info.getterArgs, { "mouseover" })
    A.eq(tooltip:GetProcessingTooltipInfo(), nil)
  end)
end

local function test_name_line_is_class_colored()
  withMouseover("retail", function(_, tooltip)
    tooltip:SetUnit("mouseover")
    local mage = _G.RAID_CLASS_COLORS.MAGE
    A.same({ _G.GameTooltipTextLeft1:GetTextColor() }, { mage.r, mage.g, mage.b, 1 })
  end)
end

local function test_tooltip_pre_call_true_skips_lines_and_post_calls()
  withMouseover("forever", function(_, tooltip)
    local posted = false
    _G.TooltipDataProcessor.AddTooltipPreCall(unitType(), function()
      return true
    end)
    _G.TooltipDataProcessor.AddTooltipPostCall(_G.TooltipDataProcessor.AllTypes, function()
      posted = true
    end)
    tooltip:SetUnit("mouseover")
    A.eq(tooltip:NumLines(), 0)
    A.eq(posted, false)
  end)
end

local function test_classic_fires_on_tooltip_set_unit_after_lines()
  withMouseover("vanilla", function(_, tooltip)
    local lines
    tooltip:HookScript("OnTooltipSetUnit", function(tip)
      lines = tip:NumLines()
    end)
    tooltip:SetUnit("mouseover")
    A.eq(lines, 2)
    A.eq(_G.TooltipDataProcessor, nil)
  end)
end

local function test_erroring_post_call_is_recorded_and_lines_stay()
  withMouseover("retail", function(w, tooltip)
    _G.TooltipDataProcessor.AddTooltipPostCall(unitType(), function()
      error("boom")
    end)
    tooltip:SetUnit("mouseover")
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "boom")
    A.eq(tooltip:NumLines(), 2)
  end)
end

local function test_unit_without_fixture_leaves_tooltip_empty()
  HF.withUnits("retail", function()
    _G.GameTooltip:AddLine("old")
    _G.GameTooltip:SetUnit("target")
    A.eq(_G.GameTooltip:NumLines(), 0)
  end)
end

local function test_unit_without_fixture_forgets_the_previous_unit_assumed()
  for _, flavor in ipairs({ "retail", "vanilla" }) do
    withMouseover(flavor, function(_, tooltip)
      tooltip:SetUnit("mouseover")
      tooltip:SetUnit("target")
      A.same({ tooltip:GetUnit() }, {})
    end)
  end
end

local function test_set_default_anchor_owns_and_anchors_bottom_right()
  HF.withFrameXML("tbc", function()
    local tooltip = _G.GameTooltip
    _G.GameTooltip_SetDefaultAnchor(tooltip, _G.UIParent)
    A.eq(tooltip:GetOwner(), _G.UIParent)
    A.eq(tooltip:GetAnchorType(), "ANCHOR_NONE")
    A.same({ tooltip:GetPoint() }, { "BOTTOMRIGHT", _G.UIParent, "BOTTOMRIGHT", -13, 64 })
  end)
end

local function test_add_double_line_fills_both_sides_with_colors()
  HF.withFrameXML("mists", function()
    _G.GameTooltip:AddDoubleLine("L", "R", 1, 0, 0, 0, 1, 0)
    A.eq(_G.GameTooltipTextRight1:GetText(), "R")
    A.same({ _G.GameTooltipTextLeft1:GetTextColor() }, { 1, 0, 0, 1 })
    A.same({ _G.GameTooltipTextRight1:GetTextColor() }, { 0, 1, 0, 1 })
  end)
end

local function test_add_line_defaults_to_white()
  HF.withFrameXML("retail", function()
    _G.GameTooltip:AddLine("x")
    A.same({ _G.GameTooltipTextLeft1:GetTextColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_clear_lines_empties_hides_and_reuses_font_strings()
  HF.withFrameXML("retail", function()
    local tooltip = _G.GameTooltip
    tooltip:AddLine("a")
    local first = _G.GameTooltipTextLeft1
    tooltip:ClearLines()
    A.eq(tooltip:NumLines(), 0)
    A.eq(first:GetText(), "")
    A.eq(first:IsShown(), false)
    tooltip:SetText("b")
    A.eq(_G.GameTooltipTextLeft1, first)
    A.same({ first:GetText(), first:IsShown() }, { "b", true })
  end)
end

local function test_tooltip_is_the_eager_named_game_tooltip()
  HF.withFrameXML("retail", function(w)
    A.eq(_G.GameTooltip:GetObjectType(), "GameTooltip")
    A.eq(_G.GameTooltip:GetName(), "GameTooltip")
    A.eq(w.unscripted["frame:GameTooltip"], nil)
  end)
end

local function test_status_bar_and_nine_slice()
  HF.withFrameXML("vanilla", function()
    A.eq(_G.GameTooltipStatusBar:GetObjectType(), "StatusBar")
    A.eq(_G.GameTooltipStatusBar:GetParent(), _G.GameTooltip)
    local slice = _G.GameTooltip.NineSlice
    slice:SetBorderColor(1, 0, 0, 1)
    slice:SetCenterColor(0, 0, 1)
    A.same({ slice:GetBorderColor() }, { 1, 0, 0, 1 })
    A.same({ slice:GetCenterColor() }, { 0, 0, 1, 1 })
  end)
end

local function test_none_line_pre_call_sees_level_and_faction()
  HF.withUnits("retail", function(w)
    local fixture = { name = "Bob", isPlayer = true, className = "Mage", raceName = "Orc", level = 80, faction = "Horde" }
    w:unit("mouseover", fixture)
    local seen = {}
    _G.TooltipDataProcessor.AddLinePreCall(_G.Enum.TooltipDataLineType.None, function(_, line)
      seen[#seen + 1] = line.leftText
    end)
    _G.GameTooltip:SetUnit("mouseover")
    A.same(seen, { "Level 80 Orc Mage", "Horde" })
  end)
end

local function test_tooltip_starts_hidden()
  HF.withFrameXML("forever", function()
    A.eq(_G.GameTooltip:IsShown(), false)
  end)
end

local function test_missing_tooltip_enums_get_fallbacks()
  H.withWorld("retail", function(w)
    _G.Enum.TooltipDataType = nil
    _G.Enum.TooltipDataLineType = nil
    FrameXML.installStage1(w)
    A.eq(_G.Enum.TooltipDataType.Unit, 2)
    A.eq(_G.Enum.TooltipDataLineType.UnitName, 2)
    A.eq(_G.Enum.TooltipDataLineType.None, 0)
  end)
end

return function()
  test_post_call_sees_get_unit()
  test_get_unit_returns_the_guid_on_mainline_only()
  test_get_unit_token_comes_from_the_guid_on_mainline()
  test_hiding_the_tooltip_forgets_the_unit_on_mainline()
  test_classic_forgets_the_unit_when_the_shown_tooltip_hides_assumed()
  test_line_pre_call_true_drops_the_line()
  test_processing_info_only_while_processing()
  test_name_line_is_class_colored()
  test_tooltip_pre_call_true_skips_lines_and_post_calls()
  test_classic_fires_on_tooltip_set_unit_after_lines()
  test_erroring_post_call_is_recorded_and_lines_stay()
  test_unit_without_fixture_leaves_tooltip_empty()
  test_unit_without_fixture_forgets_the_previous_unit_assumed()
  test_set_default_anchor_owns_and_anchors_bottom_right()
  test_add_double_line_fills_both_sides_with_colors()
  test_add_line_defaults_to_white()
  test_clear_lines_empties_hides_and_reuses_font_strings()
  test_tooltip_is_the_eager_named_game_tooltip()
  test_status_bar_and_nine_slice()
  test_none_line_pre_call_sees_level_and_faction()
  test_tooltip_starts_hidden()
  test_missing_tooltip_enums_get_fallbacks()
end
