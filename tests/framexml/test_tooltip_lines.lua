-- TooltipLines.build: a unit's tooltip data (name, guild, level, faction and PvP lines) from its fixture answers.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local TooltipLines = require("framexml.fakes.tooltip_lines")

local MAGE = { name = "Bob", isPlayer = true, classFile = "MAGE", className = "Mage", raceName = "Orc", level = 80 }

local function buildFor(flavor, fixture)
  local data
  HF.withUnits(flavor, function(w)
    w:unit("target", fixture)
    data = TooltipLines.build(w, "target")
  end)
  return data
end

local function leftTexts(data)
  local out = {}
  for i, line in ipairs(data.lines) do
    out[i] = line.leftText
  end
  return out
end

local function test_player_lines_are_name_and_level_race_class()
  A.same(leftTexts(buildFor("retail", MAGE)), { "Bob", "Level 80 Orc Mage" })
end

local function test_data_is_unit_type_with_guid()
  local fixture = { name = "Bob", isPlayer = true, guid = "G" }
  local data = buildFor("forever", fixture)
  A.eq(data.guid, "G")
  A.eq(data.type, 2)
end

local function test_player_name_line_is_class_colored()
  local color = buildFor("retail", MAGE).lines[1].leftColor
  HF.withFrameXML("retail", function()
    local mage = _G.RAID_CLASS_COLORS.MAGE
    A.same(color, { r = mage.r, g = mage.g, b = mage.b })
  end)
end

local function test_name_line_has_unit_name_type()
  A.eq(buildFor("retail", MAGE).lines[1].type, 2)
end

local function test_npc_level_line_shows_level_only()
  local data = buildFor("vanilla", { name = "Wolf", level = 60, reaction = 2 })
  A.same(leftTexts(data), { "Wolf", "Level 60" })
end

local function test_npc_name_line_uses_reaction_color()
  local color = buildFor("tbc", { name = "Wolf", level = 60, reaction = 4 }).lines[1].leftColor
  A.same(color, { r = 0.9, g = 0.7, b = 0 })
end

local function test_realm_is_appended_to_name()
  local fixture = { name = "Bob", realm = "Stormrage", isPlayer = true, className = "Mage", raceName = "Orc", level = 1 }
  A.eq(buildFor("retail", fixture).lines[1].leftText, "Bob-Stormrage")
end

local function test_unknown_level_shows_question_marks()
  local data = buildFor("mists", { name = "Boss", level = -1 })
  A.eq(data.lines[2].leftText, "Level ??")
end

local function test_guild_faction_and_pvp_lines()
  local fixture = { name = "Bob", isPlayer = true, className = "Mage", raceName = "Orc", level = 80 }
  fixture.guild, fixture.faction, fixture.pvp = "Wardens", "Horde", true
  local texts = leftTexts(buildFor("retail", fixture))
  A.same(texts, { "Bob", "<Wardens>", "Level 80 Orc Mage", "Horde", "PvP" })
end

local function test_level_line_has_none_type()
  local data = buildFor("retail", MAGE)
  HF.withFrameXML("retail", function()
    A.eq(data.lines[2].type, _G.Enum.TooltipDataLineType.None)
  end)
end

return function()
  test_player_lines_are_name_and_level_race_class()
  test_data_is_unit_type_with_guid()
  test_player_name_line_is_class_colored()
  test_name_line_has_unit_name_type()
  test_npc_level_line_shows_level_only()
  test_npc_name_line_uses_reaction_color()
  test_realm_is_appended_to_name()
  test_unknown_level_shows_question_marks()
  test_guild_faction_and_pvp_lines()
  test_level_line_has_none_type()
end
