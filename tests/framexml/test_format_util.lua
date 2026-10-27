-- Number, money and time formatters (framexml/fakes/format_util.lua). Rule tags W<n> name rows of docs/client-sources.md
-- `## Widgets`.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

local function test_break_up_large_numbers_groups_thousands_assumed() -- W70
  withFrameXML("retail", function()
    A.eq(_G.BreakUpLargeNumbers(1234567), "1,234,567")
    A.eq(_G.BreakUpLargeNumbers(999), "999")
    A.eq(_G.BreakUpLargeNumbers(1000), "1,000")
  end)
end

local function test_format_large_number_groups_with_the_separator_string() -- W70
  withFrameXML("retail", function()
    A.eq(_G.FormatLargeNumber(1234567), "1,234,567")
    A.eq(_G.FormatLargeNumber(12), "12")
    A.eq(_G.FormatLargeNumber(100000), "100,000")
    _G.LARGE_NUMBER_SEPERATOR = "."
    A.eq(_G.FormatLargeNumber(1234), "1.234")
  end)
end

local function test_abbreviate_numbers_use_the_number_cap_letters_assumed() -- W70
  withFrameXML("retail", function()
    A.eq(_G.AbbreviateNumbers(999), "999")
    A.eq(_G.AbbreviateNumbers(1500), "1.5K")
    A.eq(_G.AbbreviateNumbers(2500000), "2.5M")
    A.eq(_G.AbbreviateLargeNumbers(1000), "1K")
    A.eq(_G.AbbreviateLargeNumbers(3000000000), "3B")
  end)
end

local function test_get_coin_text_separates_with_a_comma() -- W70
  withFrameXML("retail", function()
    A.eq(_G.C_CurrencyInfo.GetCoinText(12345), "1 Gold, 23 Silver, 45 Copper")
    A.eq(_G.C_CurrencyInfo.GetCoinText(12345, " "), "1 Gold 23 Silver 45 Copper")
    A.eq(_G.C_CurrencyInfo.GetCoinText(5), "5 Copper")
  end)
end

-- The bare name is in no flavor's api or FrameXML list; the client's own code calls the C_CurrencyInfo function.
local function test_get_coin_text_has_no_bare_global() -- W70
  withFrameXML("retail", function()
    A.eq(_G.GetCoinText, nil)
    A.eq(_G.GetCoinTextureString, nil)
  end)
end

local function test_get_coin_texture_string_sizes_the_icons_by_font_height_assumed() -- W70
  withFrameXML("retail", function()
    A.eq(
      _G.C_CurrencyInfo.GetCoinTextureString(12345, 12),
      "1|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t 23|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t 45|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
    )
    A.eq(_G.C_CurrencyInfo.GetCoinTextureString(7), "7|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t")
  end)
end

local function test_get_money_string_uses_the_icon_textures() -- W70
  withFrameXML("retail", function()
    A.eq(_G.GetMoneyString(12345), "1" .. GOLD_ICON .. " 23" .. SILVER_ICON .. " 45" .. COPPER_ICON)
  end)
end

local function test_get_money_string_skips_empty_denominations_and_zero() -- W70
  withFrameXML("retail", function()
    A.eq(_G.GetMoneyString(10000), "1" .. GOLD_ICON)
    A.eq(_G.GetMoneyString(0), "0" .. COPPER_ICON)
    A.eq(_G.GetMoneyString(0, false, false, true), "0" .. GOLD_ICON)
  end)
end

local function test_get_money_string_separates_thousands_and_wraps_a_colour() -- W70
  withFrameXML("retail", function()
    A.eq(_G.GetMoneyString(12345670000, true), "1,234,567" .. GOLD_ICON)
    A.eq(_G.GetMoneyString(10000, false, false, false, _G.RED_FONT_COLOR), "|cffff2020" .. "1" .. GOLD_ICON .. "|r")
  end)
end

local function test_get_money_string_hides_copper_over_the_gold_threshold() -- W70
  withFrameXML("retail", function()
    A.eq(_G.GetMoneyString(12345, false, true), "1" .. GOLD_ICON .. " 23" .. SILVER_ICON .. " 45" .. COPPER_ICON)
    A.eq(_G.GetMoneyString(1200045, false, true), "120" .. GOLD_ICON)
  end)
end

local function test_seconds_to_time_keeps_two_terms() -- W70
  withFrameXML("retail", function()
    A.eq(_G.SecondsToTime(3725), "1 Hr 2 Min")
    A.eq(_G.SecondsToTime(45), "45 Sec")
    A.eq(_G.SecondsToTime(90000), "1 Day 1 Hr")
  end)
end

local function test_seconds_to_time_flags_drop_seconds_spell_out_and_cap_terms() -- W70
  withFrameXML("retail", function()
    A.eq(_G.SecondsToTime(125, true), "2 Min")
    A.eq(_G.SecondsToTime(3725, false, true), "1 Hour 2 Minutes")
    A.eq(_G.SecondsToTime(3725, false, false, 3), "1 Hr 2 Min 5 Sec")
    A.eq(_G.SecondsToTime(0), "")
  end)
end

local function test_get_time_precise_sec_follows_the_world_clock_assumed() -- W70
  withFrameXML("retail", function(w)
    A.eq(_G.GetTimePreciseSec(), w.now)
    local before = _G.GetTimePreciseSec()
    w:advance(2)
    A.eq(_G.GetTimePreciseSec(), before + 2)
  end)
end

return function()
  test_break_up_large_numbers_groups_thousands_assumed()
  test_format_large_number_groups_with_the_separator_string()
  test_abbreviate_numbers_use_the_number_cap_letters_assumed()
  test_get_coin_text_separates_with_a_comma()
  test_get_coin_text_has_no_bare_global()
  test_get_coin_texture_string_sizes_the_icons_by_font_height_assumed()
  test_get_money_string_uses_the_icon_textures()
  test_get_money_string_skips_empty_denominations_and_zero()
  test_get_money_string_separates_thousands_and_wraps_a_colour()
  test_get_money_string_hides_copper_over_the_gold_threshold()
  test_seconds_to_time_keeps_two_terms()
  test_seconds_to_time_flags_drop_seconds_spell_out_and_cap_terms()
  test_get_time_precise_sec_follows_the_world_clock_assumed()
end
