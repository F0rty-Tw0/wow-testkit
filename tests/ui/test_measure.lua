-- Text measurement fallback: ui/measure.lua.
local A = require("assert")
local H = require("tests.helpers.world")
local Measure = require("ui.measure")

local FONT = "Fonts\\FRIZQT__.TTF"

local function near(actual, expected)
  A.truthy(math.abs(actual - expected) < 1e-9, string.format("expected %s, got %s", expected, actual))
end

local function test_width_counts_visible_characters_assumed() -- R2
  H.withWorld("retail", function(w)
    A.eq(Measure.width(w, FONT, 10, "", "Hello"), 25) -- 5 * 0.5 * 10
    A.eq(Measure.width(w, FONT, 12, "", "|cff00ff00abc|r"), 18) -- 3 * 0.5 * 12
    A.eq(Measure.width(w, FONT, 10, "", "\195\169t\195\169"), 15) -- 3 characters * 0.5 * 10
  end)
end

local function test_width_of_several_lines_is_the_widest_assumed()
  H.withWorld("retail", function(w)
    A.eq(Measure.width(w, FONT, 10, "", "ab\ncdef"), 20) -- 4 * 5
    A.eq(Measure.width(w, FONT, 10, "", "ab|ncdef"), 20)
  end)
end

local function test_height_is_lines_times_the_line_height_assumed()
  H.withWorld("retail", function(w)
    near(Measure.height(w, FONT, 10, "", "Hello"), 11.5) -- 1 * 10 * 1.15
    near(Measure.height(w, FONT, 10, "", ""), 11.5) -- empty text is one line
    near(Measure.height(w, FONT, 10, "", "a\nb"), 23) -- 2 lines
    near(Measure.height(w, FONT, 10, "", "a|nb"), 23)
  end)
end

local function test_wrapping_breaks_at_spaces_assumed()
  H.withWorld("retail", function(w)
    -- each letter is 5 wide: "aa bb" = 5 characters = 25; "aa bb cc" = 8 characters = 40
    near(Measure.height(w, FONT, 10, "", "aa bb cc", 25), 23) -- "aa bb" + "cc"
    near(Measure.height(w, FONT, 10, "", "aa bb cc", 24), 34.5) -- "aa", "bb", "cc"
    near(Measure.height(w, FONT, 10, "", "aa bb cc", nil), 11.5)
    near(Measure.height(w, FONT, 10, "", "abcdefgh", 25), 11.5) -- a word wider than 25 keeps its line
  end)
end

local function test_use_glyphs_replaces_the_estimate_for_that_font()
  H.withWorld("retail", function(w)
    Measure.useGlyphs(w, {
      ["Fonts\\Real.ttf"] = {
        width = function(size, _, text)
          return #text * size
        end,
      },
    })
    A.eq(Measure.width(w, "Fonts\\Real.ttf", 10, "", "abc"), 30)
    A.eq(Measure.width(w, FONT, 10, "", "abc"), 15) -- other fonts keep the estimate
  end)
end

return function()
  test_width_counts_visible_characters_assumed()
  test_width_of_several_lines_is_the_widest_assumed()
  test_height_is_lines_times_the_line_height_assumed()
  test_wrapping_breaks_at_spaces_assumed()
  test_use_glyphs_replaces_the_estimate_for_that_font()
end
