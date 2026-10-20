-- Placeholder text metrics: half the font size per visible character.
local A = require("assert")
local Metrics = require("ui.metrics_placeholder")

local function test_width_ignores_color_codes()
  A.eq(Metrics.stringWidth("|cff00ff00abc|r", 12), 18)
end

local function test_width_counts_utf8_characters_once()
  A.eq(Metrics.stringWidth("\195\169t\195\169", 10), 15)
end

local function test_height_is_font_size()
  A.eq(Metrics.stringHeight(14), 14)
end

return function()
  test_width_ignores_color_codes()
  test_width_counts_utf8_characters_once()
  test_height_is_font_size()
end
