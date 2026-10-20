-- Color tables and difficulty colors.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local withFrameXML = HF.withFrameXML

local function test_class_color_generates_hex()
  withFrameXML("retail", function()
    A.eq(_G.RAID_CLASS_COLORS.MAGE:GenerateHexColor(), "ff3fc7eb")
    A.eq(_G.RAID_CLASS_COLORS.MAGE.colorStr, "ff3fc7eb")
  end)
end

local function test_faction_bar_colors_cover_eight_reactions()
  withFrameXML("tbc", function()
    A.eq(#_G.FACTION_BAR_COLORS, 8)
    A.eq(_G.FACTION_BAR_COLORS[5].g > _G.FACTION_BAR_COLORS[5].r, true)
  end)
end

-- GetDifficultyColor is in Ketho's FrameXML list on live and forever only (checked 2026-10-04).
local function test_get_difficulty_color_follows_ketho_framexml()
  withFrameXML("retail", function()
    A.eq(type(_G.GetDifficultyColor), "function")
  end)
  withFrameXML("vanilla", function()
    A.eq(_G.GetDifficultyColor, nil)
    A.eq(type(_G.GetQuestDifficultyColor), "function")
  end)
end

local function test_difficulty_color_bands_against_player_level()
  withFrameXML("retail", function(w)
    w:stub("UnitLevel", { returns = { 60 } })
    local color = _G.GetQuestDifficultyColor
    A.eq(color(65), color(70))
    A.eq(color(63) == color(65), false)
    A.eq(color(62), color(58))
    A.eq(color(57) == color(58), false)
    A.eq(color(1) == color(57), false)
  end)
end

local function test_difficulty_color_defaults_player_level_to_80()
  withFrameXML("retail", function()
    A.eq(_G.GetCreatureDifficultyColor(80), _G.GetCreatureDifficultyColor(78))
    A.eq(_G.GetCreatureDifficultyColor(85) == _G.GetCreatureDifficultyColor(80), false)
  end)
end

return function()
  test_class_color_generates_hex()
  test_faction_bar_colors_cover_eight_reactions()
  test_get_difficulty_color_follows_ketho_framexml()
  test_difficulty_color_bands_against_player_level()
  test_difficulty_color_defaults_player_level_to_80()
end
