-- Rect resolution, cache and anchor cycles: ui/layout.lua.
local A = require("assert")
local HL = require("tests.helpers.layout")
local Layout = require("ui.layout")

local SCREEN = { width = 1000, height = 800 }
local CYCLE = "Cannot anchor to a region dependent on it"

local function frame(parent)
  return _G.CreateFrame("Frame", nil, parent)
end

-- Root R: 200x100 at BOTTOMLEFT of the screen +50,+30 -> pixels x 50..250, y 30..130.
local function root()
  local r = frame()
  r:SetSize(200, 100)
  r:SetPoint("BOTTOMLEFT", 50, 30)
  return r
end

local function test_a_region_without_points_has_no_rect()
  HL.withLayout(SCREEN, function(w)
    local f = frame()
    f:SetSize(10, 10)
    A.eq(Layout.rect(w, f), nil)
  end)
end

local function test_one_anchor_and_a_size_place_the_region_assumed() -- (LY5)
  HL.withLayout(SCREEN, function(w)
    -- left = 0 + 50, bottom = 0 + 30
    A.same(Layout.rect(w, root()), { left = 50, bottom = 30, width = 200, height = 100 })
  end)
end

local function test_screen_anchor_target_is_the_physical_screen_rect_assumed() -- (LY3, LY2)
  HL.withLayout(SCREEN, function(w)
    local f = frame()
    f:SetSize(100, 50)
    f:SetPoint("TOPRIGHT", nil, "TOPRIGHT", -10, -20)
    -- right = 1000 - 10 = 990 -> left = 890; top = 800 - 20 = 780 -> bottom = 730
    A.same(Layout.rect(w, f), { left = 890, bottom = 730, width = 100, height = 50 })
  end)
end

local function test_a_missing_global_name_anchors_to_the_screen_assumed() -- (LY4)
  HL.withLayout(SCREEN, function(w)
    local f = frame()
    f:SetSize(10, 10)
    f:SetPoint("TOPLEFT", "TkNoSuchFrame")
    -- top = 800 -> bottom = 790; left = 0
    A.same(Layout.rect(w, f), { left = 0, bottom = 790, width = 10, height = 10 })
  end)
end

local function test_center_anchor_to_a_corner_with_offsets()
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local c = frame(r)
    c:SetSize(40, 20)
    c:SetPoint("CENTER", r, "TOPRIGHT", -10, -5)
    -- R top-right = (250, 130); center at (250 - 10, 130 - 5) = (240, 125); left = 240 - 20, bottom = 125 - 10
    A.same(Layout.rect(w, c), { left = 220, bottom = 115, width = 40, height = 20 })
  end)
end

local function test_two_opposite_anchors_set_the_size_and_beat_an_explicit_size() -- (LY5)
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local d = frame(r)
    d:SetSize(5, 5) -- ignored
    d:SetPoint("TOPLEFT", r, "TOPLEFT", 10, -10)
    d:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -20, 15)
    -- TL = (50 + 10, 130 - 10) = (60, 120); BR = (250 - 20, 30 + 15) = (230, 45): width 170, height 75
    A.same(Layout.rect(w, d), { left = 60, bottom = 45, width = 170, height = 75 })
  end)
end

local function test_left_and_right_anchors_with_a_height_place_a_strip_assumed() -- (LY5)
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local f = frame(r)
    f:SetHeight(30)
    f:SetPoint("LEFT", r, "LEFT")
    f:SetPoint("RIGHT", r, "RIGHT")
    -- x 50..250 -> width 200; center y = 30 + 100 / 2 = 80 -> bottom = 80 - 15 = 65
    A.same(Layout.rect(w, f), { left = 50, bottom = 65, width = 200, height = 30 })
  end)
end

local function test_too_few_constraints_give_no_rect_assumed() -- (LY5)
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local single = frame(r)
    single:SetPoint("TOPLEFT", r, "TOPLEFT") -- no size
    A.eq(Layout.rect(w, single), nil)
    local strip = frame(r)
    strip:SetPoint("LEFT", r, "LEFT")
    strip:SetPoint("RIGHT", r, "RIGHT") -- width known, no height
    A.eq(Layout.rect(w, strip), nil)
  end)
end

local function test_an_anchor_to_a_region_without_a_rect_gives_no_rect()
  HL.withLayout(SCREEN, function(w)
    local nowhere, f = frame(), frame()
    nowhere:SetSize(5, 5)
    f:SetSize(5, 5)
    f:SetPoint("TOP", nowhere)
    A.eq(Layout.rect(w, f), nil)
  end)
end

local function test_offsets_and_sizes_are_in_the_regions_own_scale_space() -- (LY7)
  HL.withLayout(SCREEN, function(w)
    local r = root()
    local s = frame(r)
    s:SetScale(2)
    s:SetSize(25, 25)
    s:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 10, 10)
    -- effective scale 2: pixel anchor = (50 + 10 * 2, 30 + 10 * 2) = (70, 50), size 25 * 2 = 50 px
    A.same(Layout.pixelRect(w, s), { left = 70, bottom = 50, right = 120, top = 100 })
    -- units = pixels / 2
    A.same(Layout.rect(w, s), { left = 35, bottom = 25, width = 25, height = 25 })
  end)
end

local function test_a_size_the_user_set_comes_back_exactly()
  HL.withLayout(SCREEN, function(w)
    local f = frame()
    f:SetSize(20.1, 10.3)
    f:SetPoint("BOTTOMLEFT", 100.3, 7.7)
    local rect = Layout.rect(w, f)
    A.eq(rect.width, 20.1)
    A.eq(rect.height, 10.3)
  end)
end

local function test_mutators_refresh_the_rect()
  HL.withLayout(SCREEN, function(w)
    local r = root()
    r:SetWidth(300)
    A.eq(Layout.rect(w, r).width, 300)
    r:SetPoint("BOTTOMLEFT", 70, 30)
    A.eq(Layout.rect(w, r).left, 70)
    r:SetScale(2)
    -- units unchanged for a screen-anchored root, pixels doubled: (70 * 2, 30 * 2)..(70 * 2 + 300 * 2, 30 * 2 + 100 * 2)
    A.same(Layout.pixelRect(w, r), { left = 140, bottom = 60, right = 740, top = 260 })
  end)
end

local function test_layout_follows_a_reparent_of_the_anchor_target() -- Review Focus 1
  HL.withLayout(SCREEN, function(w)
    local p1 = frame()
    p1:SetSize(100, 100)
    p1:SetPoint("BOTTOMLEFT", 100, 100)
    local b = frame(p1)
    b:SetSize(20, 20)
    b:SetPoint("BOTTOMLEFT", p1, "BOTTOMLEFT", 10, 10)
    local a = frame()
    a:SetSize(5, 5)
    a:SetPoint("BOTTOMLEFT", b, "TOPRIGHT")
    -- b = (110..130, 110..130), so a starts at its top-right (130, 130)
    A.same(Layout.rect(w, a), { left = 130, bottom = 130, width = 5, height = 5 })
    local p2 = frame()
    p2:SetScale(2)
    b:SetParent(p2)
    -- b now has scale 2: offset 10 -> 20 px, size 20 -> 40 px, so b = (120..160, 120..160) and a starts at (160, 160)
    A.same(Layout.rect(w, a), { left = 160, bottom = 160, width = 5, height = 5 })
  end)
end

local function test_hiding_the_anchor_target_keeps_the_rect_assumed() -- Review Focus 1
  HL.withLayout(SCREEN, function(w)
    local b = root()
    local a = frame()
    a:SetSize(5, 5)
    a:SetPoint("BOTTOMLEFT", b, "TOPRIGHT")
    b:Hide()
    A.same(Layout.rect(w, a), { left = 250, bottom = 130, width = 5, height = 5 })
  end)
end

local function test_invalidate_refreshes_after_a_direct_state_write()
  HL.withLayout(SCREEN, function(w)
    local f = root()
    A.eq(Layout.rect(w, f).width, 200)
    w.ui.state[f].width = 300
    Layout.invalidate(w, f)
    A.eq(Layout.rect(w, f).width, 300)
  end)
end

local function test_a_two_frame_anchor_cycle_raises_at_the_closing_set_point() -- (LY9) Review Focus 2
  HL.withLayout(SCREEN, function(w)
    local a, b = frame(), frame()
    a:SetPoint("TOP", b)
    A.errors(function()
      b:SetPoint("TOP", a)
    end, CYCLE)
    A.eq(b:GetNumPoints(), 0)
    A.eq(Layout.rect(w, a), nil) -- b has no points: an invalid rect, not a stack overflow
  end)
end

local function test_a_three_frame_cycle_raises_and_keeps_the_old_anchors() -- (LY9)
  HL.withLayout(SCREEN, function()
    local a, b, c = frame(), frame(), frame()
    a:SetPoint("TOP", b)
    b:SetPoint("TOP", c)
    A.errors(function()
      c:SetPoint("LEFT", a, "RIGHT")
    end, CYCLE) -- a -> b -> c -> a closes the loop
    A.eq(c:GetNumPoints(), 0)
    A.eq(a:GetNumPoints(), 1) -- the earlier anchors stay
  end)
end

local function test_set_all_points_to_a_dependant_raises() -- (LY9)
  HL.withLayout(SCREEN, function()
    local a, b = frame(), frame()
    a:SetPoint("TOP", b)
    A.errors(function()
      b:SetAllPoints(a)
    end, CYCLE)
    A.eq(b:GetNumPoints(), 0)
  end)
end

local function test_the_error_names_the_region_that_made_the_call() -- (LY9)
  HL.withLayout(SCREEN, function()
    local a, b = _G.CreateFrame("Frame", "TkA"), _G.CreateFrame("Frame", "TkB")
    a:SetPoint("TOP", b)
    local message = A.errors(function()
      b:SetPoint("TOP", a)
    end)
    A.contains(message, "Action[SetPoint] failed because[" .. CYCLE .. "]: attempted from: TkB:SetPoint.")
  end)
end

local function test_anchoring_to_itself_raises() -- (LY9)
  HL.withLayout(SCREEN, function()
    local a = frame()
    A.errors(function()
      a:SetPoint("TOP", a)
    end, "Action[SetPoint] failed because[Cannot anchor to itself]")
    A.eq(a:GetNumPoints(), 0)
  end)
end

return function()
  test_a_region_without_points_has_no_rect()
  test_one_anchor_and_a_size_place_the_region_assumed()
  test_screen_anchor_target_is_the_physical_screen_rect_assumed()
  test_a_missing_global_name_anchors_to_the_screen_assumed()
  test_center_anchor_to_a_corner_with_offsets()
  test_two_opposite_anchors_set_the_size_and_beat_an_explicit_size()
  test_left_and_right_anchors_with_a_height_place_a_strip_assumed()
  test_too_few_constraints_give_no_rect_assumed()
  test_an_anchor_to_a_region_without_a_rect_gives_no_rect()
  test_offsets_and_sizes_are_in_the_regions_own_scale_space()
  test_a_size_the_user_set_comes_back_exactly()
  test_mutators_refresh_the_rect()
  test_layout_follows_a_reparent_of_the_anchor_target()
  test_hiding_the_anchor_target_keeps_the_rect_assumed()
  test_invalidate_refreshes_after_a_direct_state_write()
  test_a_two_frame_anchor_cycle_raises_at_the_closing_set_point()
  test_a_three_frame_cycle_raises_and_keeps_the_old_anchors()
  test_set_all_points_to_a_dependant_raises()
  test_the_error_names_the_region_that_made_the_call()
  test_anchoring_to_itself_raises()
end
