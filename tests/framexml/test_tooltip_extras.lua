-- GameTooltip extras (framexml/fakes/tooltip_extras.lua): AppendText, SetPadding, IsOwned, FadeOut and the hyperlink, item
-- and spell setters. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function leftTexts(tooltip)
  local out = {}
  for i = 1, tooltip:NumLines() do
    out[i] = _G["GameTooltipTextLeft" .. i]:GetText()
  end

  return out
end

local function ownedTooltip()
  local tooltip = _G.GameTooltip
  tooltip:SetOwner(_G.UIParent, "ANCHOR_NONE")

  return tooltip
end

local function test_append_text_joins_the_last_line() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:AddLine("a")
    tooltip:AddLine("x")
    tooltip:AppendText("b")
    A.same(leftTexts(tooltip), { "a", "xb" })
  end)
end

local function test_append_text_without_lines_adds_nothing_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:AppendText("b")
    A.eq(tooltip:NumLines(), 0)
  end)
end

local function test_padding_defaults_to_zero() -- W56
  withFrameXML("retail", function()
    A.same({ _G.GameTooltip:GetPadding() }, { 0, 0, 0, 0 })
  end)
end

local function test_padding_round_trips_right_bottom_left_top() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:SetPadding(1, 2, 3, 4)
    A.same({ tooltip:GetPadding() }, { 1, 2, 3, 4 })
  end)
end

local function test_padding_left_and_top_default_to_zero_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:SetPadding(5, 6)
    A.same({ tooltip:GetPadding() }, { 5, 6, 0, 0 })
  end)
end

local function test_is_owned_is_true_only_for_the_owner_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    local other = _G.CreateFrame("Frame", nil, _G.UIParent)
    A.same({ tooltip:IsOwned(_G.UIParent), tooltip:IsOwned(other) }, { true, false })
  end)
end

local function test_fade_out_hides_the_tooltip_at_once_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:Show()
    tooltip:FadeOut()
    A.eq(tooltip:IsShown(), false)
  end)
end

local function test_item_by_id_without_item_data_adds_one_white_line_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    A.eq(rawget(_G, "GetItemInfo"), nil)
    tooltip:AddLine("old")
    tooltip:SetItemByID(1234)
    A.same(leftTexts(tooltip), { "item:1234" })
    A.same({ _G.GameTooltipTextLeft1:GetTextColor() }, { 1, 1, 1, 1 })
  end)
end

local function test_item_by_id_with_item_data_shows_the_item_name_assumed() -- W56
  withFrameXML("retail", function()
    rawset(_G, "GetItemInfo", function(id)
      return "Sword " .. id
    end)
    local tooltip = ownedTooltip()
    tooltip:SetItemByID(7)
    A.same(leftTexts(tooltip), { "Sword 7" })
  end)
end

local function test_spell_by_id_without_spell_data_adds_one_white_line_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:SetSpellByID(99)
    A.same(leftTexts(tooltip), { "spell:99" })
  end)
end

local function test_spell_by_id_with_spell_data_shows_the_spell_name_assumed() -- W56
  withFrameXML("retail", function()
    rawset(_G, "GetSpellInfo", function(id)
      return "Bolt " .. id
    end)
    local tooltip = ownedTooltip()
    tooltip:SetSpellByID(5)
    A.same(leftTexts(tooltip), { "Bolt 5" })
  end)
end

local function test_spell_by_id_reads_the_name_of_a_spell_info_table_assumed() -- W56
  withFrameXML("retail", function()
    rawset(_G, "GetSpellInfo", function(id)
      return { name = "Table " .. id }
    end)
    local tooltip = ownedTooltip()
    tooltip:SetSpellByID(5)
    A.same(leftTexts(tooltip), { "Table 5" })
  end)
end

local function test_hyperlink_shows_the_names_of_item_and_spell_data_assumed() -- W56
  withFrameXML("retail", function()
    rawset(_G, "GetItemInfo", function(id)
      return "Sword " .. id
    end)
    rawset(_G, "GetSpellInfo", function(id)
      return "Bolt " .. id
    end)
    local tooltip = ownedTooltip()
    tooltip:SetHyperlink("item:7")
    A.same(leftTexts(tooltip), { "Sword 7" })
    tooltip:SetHyperlink("spell:5")
    A.same(leftTexts(tooltip), { "Bolt 5" })
  end)
end

local function test_hyperlink_equals_the_id_setters_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:SetHyperlink("spell:99")
    A.same(leftTexts(tooltip), { "spell:99" })
    tooltip:SetHyperlink("item:1234")
    A.same(leftTexts(tooltip), { "item:1234" })
  end)
end

local function test_hyperlink_reads_a_full_link_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:SetHyperlink("|cff1eff00|Hitem:1234:0:0|h[Thing]|h|r")
    A.same(leftTexts(tooltip), { "item:1234" })
  end)
end

local function test_hyperlink_of_another_type_shows_the_link_assumed() -- W56
  withFrameXML("retail", function()
    local tooltip = ownedTooltip()
    tooltip:SetHyperlink("quest:55:1:2")
    A.same(leftTexts(tooltip), { "quest:55" })
  end)
end

return function()
  test_append_text_joins_the_last_line()
  test_append_text_without_lines_adds_nothing_assumed()
  test_padding_defaults_to_zero()
  test_padding_round_trips_right_bottom_left_top()
  test_padding_left_and_top_default_to_zero_assumed()
  test_is_owned_is_true_only_for_the_owner_assumed()
  test_fade_out_hides_the_tooltip_at_once_assumed()
  test_item_by_id_without_item_data_adds_one_white_line_assumed()
  test_item_by_id_with_item_data_shows_the_item_name_assumed()
  test_spell_by_id_without_spell_data_adds_one_white_line_assumed()
  test_spell_by_id_with_spell_data_shows_the_spell_name_assumed()
  test_spell_by_id_reads_the_name_of_a_spell_info_table_assumed()
  test_hyperlink_shows_the_names_of_item_and_spell_data_assumed()
  test_hyperlink_equals_the_id_setters_assumed()
  test_hyperlink_reads_a_full_link_assumed()
  test_hyperlink_of_another_type_shows_the_link_assumed()
end
