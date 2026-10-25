-- Client glyph widths: advances plus kerning from the extracted tables replace the Measure estimate.
local A = require("assert")
local Client = require("client")
local H = require("tests.helpers.client")
local Measure = require("ui.measure")
local Tmp = require("tests.helpers.tmp")
local World = require("world")

local FONT = "Fonts\\FRIZQT__.TTF"
local TABLE =
  "return { upm = 1000, notdef = 500, advance = { [65] = 700, [86] = 700, [32] = 300, [233] = 600 }, kern = { [65 * 0x200000 + 86] = -80 } }"

local function withGlyphs(fn)
  local ex = H.extract(Tmp.dir("glyphs"), "retail", "1", { ["fonts/glyphs/frizqt__.ttf.lua"] = TABLE })
  local w = World.new({ flavor = "retail", client = ex })
  Measure.useGlyphs(w, Client.glyphs(ex))
  local ok, err = pcall(fn, w)
  w:destroy()
  if not ok then
    error(err, 0)
  end
end

local function test_width_sums_advances_and_kerning_assumed()
  withGlyphs(function(w)
    A.eq(Measure.width(w, FONT, 10, "", "AV"), 13.2) -- (700 + 700 - 80) * 10 / 1000
  end)
end

local function test_missing_glyph_uses_notdef_assumed()
  withGlyphs(function(w)
    A.eq(Measure.width(w, FONT, 10, "", "A?"), 12) -- (700 + 500) * 10 / 1000
  end)
end

local function test_font_file_is_matched_case_insensitively_with_either_slash()
  withGlyphs(function(w)
    A.eq(Measure.width(w, "fonts/frizqt__.ttf", 10, "", "A"), 7)
    A.eq(Measure.width(w, "FONTS\\frizqt__.TTF", 10, "", "A"), 7)
  end)
end

local function test_a_font_with_no_table_keeps_the_estimate()
  withGlyphs(function(w)
    A.eq(Measure.width(w, "Fonts\\ARIALN.TTF", 10, "", "abc"), 15)
  end)
end

local function test_colour_escapes_take_no_room()
  withGlyphs(function(w)
    A.eq(Measure.width(w, FONT, 10, "", "|cff00ff00A|rV"), 13.2) -- the colour codes do not break the AV pair
    A.eq(Measure.width(w, FONT, 10, "", "A||"), 12) -- "||" is one pipe, no glyph: notdef
  end)
end

local function test_utf8_characters_count_once_by_codepoint()
  withGlyphs(function(w)
    A.eq(Measure.width(w, FONT, 10, "", "\195\169"), 6) -- U+00E9
    A.eq(Measure.width(w, FONT, 10, "", "\255"), 5) -- a stray byte is one notdef
  end)
end

local function test_a_texture_keeps_its_own_width_between_glyph_runs()
  withGlyphs(function(w)
    A.eq(Measure.width(w, FONT, 10, "", "A|Tx:16:16|tV"), 30) -- 7 + 16 + 7, no kern across the texture
  end)
end

local function test_wrap_uses_the_glyph_width()
  withGlyphs(function(w)
    A.eq(Measure.height(w, FONT, 10, "", "A A", 8), 2 * 10 * Measure.LINE_HEIGHT) -- "A A" is 17 wide, over 8: two lines
  end)
end

return function()
  test_width_sums_advances_and_kerning_assumed()
  test_missing_glyph_uses_notdef_assumed()
  test_font_file_is_matched_case_insensitively_with_either_slash()
  test_a_font_with_no_table_keeps_the_estimate()
  test_colour_escapes_take_no_room()
  test_utf8_characters_count_once_by_codepoint()
  test_a_texture_keeps_its_own_width_between_glyph_runs()
  test_wrap_uses_the_glyph_width()
end
