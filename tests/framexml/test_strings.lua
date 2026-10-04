-- Kit-authored global strings.
local A = require("assert")
local HF = require("tests.helpers.framexml")

local function test_level_strings_format()
  HF.withFrameXML("vanilla", function()
    A.eq(_G.TOOLTIP_UNIT_LEVEL_CLASS:format(60, "Mage"), "Level 60 Mage")
    A.eq(_G.FACTION_HORDE, "Horde")
  end)
end

return function()
  test_level_strings_format()
end
