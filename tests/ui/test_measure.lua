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

local function test_hyperlink_prefix_and_closing_tag_are_invisible_assumed() -- R2
  H.withWorld("retail", function(w)
    local link = "|cff0070dd|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
    A.eq(Measure.width(w, FONT, 10, "", link), 65) -- "[Thunderfury]" = 13 characters * 5
    A.eq(Measure.width(w, FONT, 10, "", "a |Hspell:2096:0|h[Mind Vision]|h b"), 85) -- 2 + 13 + 2 = 17 characters
  end)
end

local function test_an_escaped_pipe_is_one_character_assumed() -- R2
  H.withWorld("retail", function(w)
    A.eq(Measure.width(w, FONT, 10, "", "a||b"), 15) -- 3 characters
    A.eq(Measure.width(w, FONT, 10, "", "||r"), 10) -- a pipe and an r, not a color reset
    A.eq(Measure.width(w, FONT, 10, "", "||cff00ff00x"), 55) -- "|cff00ff00x" is 11 characters, not a color code
  end)
end

local function test_a_texture_is_as_wide_as_the_wiki_sizing_rules_say_assumed() -- R2
  H.withWorld("retail", function(w)
    local icon = "|TInterface\\Icons\\INV_Misc_QuestionMark:%s|t"
    local function width(params, tail)
      return Measure.width(w, FONT, 10, "", string.format(icon, params) .. (tail or ""))
    end
    A.eq(width("0"), 10) -- height 0, no width: a square of the text height (the font size)
    A.eq(width("16"), 16) -- positive height, no width: a square of that height
    A.eq(width("16:0"), 10) -- positive height, width 0: the text height
    A.eq(width("0:2"), 20) -- height 0, width 2: width times the text height
    A.eq(width("16:8"), 8) -- both positive: the width
    A.eq(width("0", " a"), 20) -- the texture, a space and a: 10 + 2 * 5
  end)
end

local function test_a_named_color_start_is_invisible_up_to_its_colon_assumed() -- R2
  H.withWorld("retail", function(w)
    A.eq(Measure.width(w, FONT, 10, "", "|cnRED_FONT_COLOR:ab|r"), 10) -- only "ab" is drawn
    A.eq(Measure.width(w, FONT, 10, "", "|cnIQ3:rare|r x"), 30) -- "rare x" = 6 characters; the digit belongs to the name
    A.eq(Measure.width(w, FONT, 10, "", "|cn:ab|r"), 30) -- no name: not a color start, so "|cn:ab" counts as 6 characters; only the |r is invisible
  end)
end

local function test_an_atlas_is_sized_like_a_texture_assumed() -- R2
  H.withWorld("retail", function(w)
    local function width(params, tail)
      return Measure.width(w, FONT, 10, "", "|A:" .. params .. "|a" .. (tail or ""))
    end
    A.eq(width("4259:19:19"), 19) -- "|A:atlas:height:width|a": both positive set the width
    A.eq(width("4259:16:0"), 10) -- the |T sizing rules apply to the height and width fields (assumed)
    A.eq(width("4259:0:2"), 20)
    A.eq(width("4259:16"), 16)
    A.eq(width("tank:16:16:0:0:1:1:1", " a"), 26) -- offsets and vertex colors take no room: 16 + " a" (2 * 5)
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

local function test_lines_and_line_count_follow_the_wrap_assumed() -- R2
  H.withWorld("retail", function(w)
    A.same(Measure.lines(w, FONT, 10, "", "aa\nbbbb cccc", nil), { "aa", "bbbb cccc" })
    A.same(Measure.lines(w, FONT, 10, "", "aa\nbbbb cccc", 30), { "aa", "bbbb", "cccc" })
    A.eq(Measure.lineCount(w, FONT, 10, "", "aa\nbbbb cccc", 30), 3)
    A.eq(Measure.lineCount(w, FONT, 10, "", "", 30), 1)
  end)
end

local function test_max_lines_limit_the_widest_line_assumed() -- R2
  H.withWorld("retail", function(w)
    A.eq(Measure.width(w, FONT, 10, "", "aa\nbbbbbb"), 30)
    A.eq(Measure.width(w, FONT, 10, "", "aa\nbbbbbb", 1), 10)
    A.eq(Measure.wrappedWidth(w, FONT, 10, "", "bbbb aaaaaa", 30), 30)
    A.eq(Measure.wrappedWidth(w, FONT, 10, "", "bbbb aaaaaa", 30, 1), 20)
  end)
end

return function()
  test_width_counts_visible_characters_assumed()
  test_hyperlink_prefix_and_closing_tag_are_invisible_assumed()
  test_an_escaped_pipe_is_one_character_assumed()
  test_a_texture_is_as_wide_as_the_wiki_sizing_rules_say_assumed()
  test_a_named_color_start_is_invisible_up_to_its_colon_assumed()
  test_an_atlas_is_sized_like_a_texture_assumed()
  test_width_of_several_lines_is_the_widest_assumed()
  test_height_is_lines_times_the_line_height_assumed()
  test_wrapping_breaks_at_spaces_assumed()
  test_use_glyphs_replaces_the_estimate_for_that_font()
  test_lines_and_line_count_follow_the_wrap_assumed()
  test_max_lines_limit_the_widest_line_assumed()
end
