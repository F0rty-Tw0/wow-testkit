-- FontString auto-size and wrap width: ui/layout.lua with ui/measure.lua.
local A = require("assert")
local HL = require("tests.helpers.layout")
local Layout = require("ui.layout")

local SCREEN = { width = 1000, height = 800 }
local FONT = "Fonts\\FRIZQT__.TTF"

local function near(actual, expected)
  A.truthy(math.abs(actual - expected) < 1e-9, string.format("expected %s, got %s", expected, actual))
end

-- R: 200x100 at BOTTOMLEFT of the screen +50,+30 -> pixels x 50..250, y 30..130.
local function root()
  local r = _G.CreateFrame("Frame")
  r:SetSize(200, 100)
  r:SetPoint("BOTTOMLEFT", 50, 30)
  return r
end

local function text(parent, str, size)
  local fs = parent:CreateFontString()
  fs:SetFont(FONT, size or 10)
  fs:SetText(str)
  return fs
end

local function test_one_anchor_sizes_the_font_string_to_its_text_assumed() -- (LY10)
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local fs = text(r, "Hello")
    fs:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -4)
    local rect = Layout.rect(w, fs)
    -- left = 50 + 4 = 54; top = 130 - 4 = 126; width 5 * 0.5 * 10 = 25; height 11.5 -> bottom = 126 - 11.5
    near(rect.left, 54)
    near(rect.width, 25)
    near(rect.height, 11.5)
    near(rect.bottom, 114.5)
  end)
end

local function test_an_explicit_width_wins_over_the_text_width()
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local fs = text(r, "Hello")
    fs:SetWidth(100)
    fs:SetPoint("TOPLEFT", r, "TOPLEFT")
    near(Layout.rect(w, fs).width, 100)
    near(Layout.rect(w, fs).height, 11.5) -- 25 wide text fits in 100: one line
  end)
end

local function test_two_anchors_fix_the_width_and_the_text_wraps_in_it_assumed() -- (LY10)
  HL.withLayout(SCREEN, function(w)
    local r = root()
    -- five 8-letter words: a line holds 40 + 5 + 40 + 5 + 40 + 5 + 40 = 175 for four words, 220 for five > 200
    local fs = text(r, "aaaaaaaa bbbbbbbb cccccccc dddddddd eeeeeeee")
    fs:SetPoint("TOPLEFT", r, "TOPLEFT")
    fs:SetPoint("TOPRIGHT", r, "TOPRIGHT")
    A.eq(Layout.wrapWidth(w, fs), 200)
    near(Layout.rect(w, fs).width, 200)
    near(Layout.rect(w, fs).height, 23) -- 2 lines
    near(fs:GetStringHeight(), 23)
    fs:SetWordWrap(false)
    near(Layout.rect(w, fs).height, 11.5)
  end)
end

local function test_without_anchors_get_width_and_height_report_the_text_size_assumed() -- (LY10)
  HL.withLayout(SCREEN, function(w)
    local fs = text(_G.CreateFrame("Frame"), "Hello")
    near(fs:GetWidth(), 25)
    near(fs:GetHeight(), 11.5)
    A.eq(Layout.rect(w, fs), nil)
  end)
end

local function test_a_height_alone_leaves_the_width_to_the_text_assumed() -- (LY10)
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local fs = text(r, "Hello world foo bar") -- 19 characters * 5 = 95 wide
    fs:SetHeight(20)
    fs:SetPoint("TOPLEFT", r, "TOPLEFT")
    near(fs:GetWidth(), 95) -- not the 20 of the height
    A.eq(Layout.wrapWidth(w, fs), nil) -- no width was set: nothing to wrap at
    near(fs:GetStringHeight(), 11.5) -- one line
    near(Layout.rect(w, fs).width, 95)
    near(Layout.rect(w, fs).height, 20)
  end)
end

local function test_text_and_font_changes_refresh_the_size()
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local fs = text(r, "Hello")
    fs:SetPoint("TOPLEFT", r, "TOPLEFT")
    near(Layout.rect(w, fs).width, 25)
    fs:SetText("Hello world") -- 11 characters * 5
    near(Layout.rect(w, fs).width, 55)
    fs:SetFont(FONT, 20) -- 11 * 0.5 * 20
    near(Layout.rect(w, fs).width, 110)
  end)
end

return function()
  test_one_anchor_sizes_the_font_string_to_its_text_assumed()
  test_an_explicit_width_wins_over_the_text_width()
  test_two_anchors_fix_the_width_and_the_text_wraps_in_it_assumed()
  test_without_anchors_get_width_and_height_report_the_text_size_assumed()
  test_a_height_alone_leaves_the_width_to_the_text_assumed()
  test_text_and_font_changes_refresh_the_size()
end
