-- ScrollFrame behaviour (ui/behaviour_scroll.lua): the scroll child, scroll offsets, ranges and their scripts. Rule tags
-- W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local HL = require("tests.helpers.layout")
local Layout = require("ui.layout")

local SCREEN = { width = 1000, height = 800 }

-- ScrollFrame Sf 100x50 at BOTTOMLEFT of UIParent holding the child Sc 100x200 at its TOPLEFT.
local function scroller()
  local sf = _G.CreateFrame("ScrollFrame", "Sf", _G.UIParent)
  sf:SetSize(100, 50)
  sf:SetPoint("BOTTOMLEFT")
  local sc = _G.CreateFrame("Frame", "Sc", sf)
  sc:SetSize(100, 200)
  sc:SetPoint("TOPLEFT")
  sf:SetScrollChild(sc)

  return sf, sc
end

-- ScrollFrame Sf 100x50 at BOTTOMLEFT of UIParent holding the child Sc 100x200 with no anchor of its own.
local function anchorlessScroller()
  local sf = _G.CreateFrame("ScrollFrame", "Sf", _G.UIParent)
  sf:SetSize(100, 50)
  sf:SetPoint("BOTTOMLEFT")
  local sc = _G.CreateFrame("Frame", "Sc", sf)
  sc:SetSize(100, 200)
  sf:SetScrollChild(sc)

  return sf, sc
end

-- source: blizzard_sharedxml/securescrolltemplates.xml:160-168 (`FauxScrollFrameTemplate`) declares its scroll child with
-- a `<Size>` and no `<Anchors>`; assumed (W45) the frame places such a child at its own top-left.
local function test_a_scroll_child_without_anchors_sits_at_the_frame_top_left_assumed() -- W45
  HL.withLayout(SCREEN, function(w)
    local sf, sc = anchorlessScroller()
    A.same(Layout.rect(w, sc), { left = 0, bottom = -150, width = 100, height = 200 })
    A.same({ sf:GetVerticalScrollRange(), sf:GetHorizontalScrollRange() }, { 150, 0 })
  end)
end

local function test_an_anchorless_scroll_child_moves_with_the_scroll_offsets_assumed() -- W45
  HL.withLayout(SCREEN, function(w)
    local sf, sc = anchorlessScroller()
    sf:SetVerticalScroll(30)
    sf:SetHorizontalScroll(20)
    A.same({ Layout.rect(w, sc).left, Layout.rect(w, sc).bottom }, { -20, -120 })
  end)
end

local function test_a_replaced_scroll_child_without_anchors_has_no_rect_assumed() -- W45
  HL.withLayout(SCREEN, function(w)
    local sf, sc = anchorlessScroller()
    local next = _G.CreateFrame("Frame", "Next", sf)
    next:SetSize(100, 200)
    sf:SetScrollChild(next)
    A.same({ Layout.rect(w, sc), Layout.rect(w, next).bottom }, { nil, -150 })
  end)
end

local function recordScript(frame, script)
  local seen = {}
  frame:SetScript(script, function(self, ...)
    seen[#seen + 1] = { self, ... }
  end)

  return seen
end

local function test_scroll_ranges_and_child_offset() -- W45
  HL.withLayout(SCREEN, function(w)
    local sf, sc = scroller()
    A.eq(sc:GetParent(), sf)
    A.same({ sf:GetVerticalScrollRange(), sf:GetHorizontalScrollRange() }, { 150, 0 })
    A.eq(Layout.rect(w, sc).bottom, -150)
    sf:SetVerticalScroll(30)
    A.eq(Layout.rect(w, sc).bottom, -120)
    A.eq(sf:GetVerticalScroll(), 30)
  end)
end

local function test_set_scroll_child_parents_the_child_to_the_frame_assumed() -- W45
  HL.withLayout(SCREEN, function()
    local sf = _G.CreateFrame("ScrollFrame", nil, _G.UIParent)
    local sc = _G.CreateFrame("Frame", nil, _G.UIParent)
    sf:SetScrollChild(sc)
    A.eq(sc:GetParent(), sf)
  end)
end

local function test_horizontal_scroll_moves_the_child_left_assumed() -- W45
  HL.withLayout(SCREEN, function(w)
    local sf, sc = scroller()
    sc:SetWidth(300)
    A.eq(sf:GetHorizontalScrollRange(), 200)
    sf:SetHorizontalScroll(20)
    A.eq(sf:GetHorizontalScroll(), 20)
    A.eq(Layout.rect(w, sc).left, -20)
  end)
end

local function test_a_fresh_scroll_frame_has_no_child_and_no_scroll() -- W45
  HL.withLayout(SCREEN, function()
    local sf = _G.CreateFrame("ScrollFrame", nil, _G.UIParent)
    A.eq(sf:GetScrollChild(), nil)
    A.same({ sf:GetVerticalScroll(), sf:GetHorizontalScroll(), sf:GetVerticalScrollRange(), sf:GetHorizontalScrollRange() }, { 0, 0, 0, 0 })
  end)
end

local function test_get_scroll_child_returns_the_child() -- W45
  HL.withLayout(SCREEN, function()
    local sf, sc = scroller()
    A.eq(sf:GetScrollChild(), sc)
  end)
end

local function test_a_child_smaller_than_the_frame_has_no_range_assumed() -- W45
  HL.withLayout(SCREEN, function()
    local sf, sc = scroller()
    sc:SetSize(40, 20)
    A.same({ sf:GetVerticalScrollRange(), sf:GetHorizontalScrollRange() }, { 0, 0 })
  end)
end

local function test_a_child_without_a_rect_has_no_range_assumed() -- W45
  HL.withLayout(SCREEN, function()
    local sf = _G.CreateFrame("ScrollFrame", nil, _G.UIParent)
    sf:SetSize(100, 50)
    sf:SetPoint("BOTTOMLEFT")
    sf:SetScrollChild(_G.CreateFrame("Frame", nil, sf))
    A.eq(sf:GetVerticalScrollRange(), 0)
  end)
end

local function test_only_the_scroll_child_moves_assumed() -- W45
  HL.withLayout(SCREEN, function(w)
    local sf = scroller()
    local other = _G.CreateFrame("Frame", "Other", sf)
    other:SetSize(10, 10)
    other:SetPoint("TOPLEFT")
    local before = Layout.rect(w, other).bottom
    sf:SetVerticalScroll(30)
    A.eq(Layout.rect(w, other).bottom, before)
  end)
end

local function test_replacing_the_scroll_child_stops_shifting_the_old_one_assumed() -- W45
  HL.withLayout(SCREEN, function(w)
    local sf, sc = scroller()
    sf:SetVerticalScroll(30)
    local next = _G.CreateFrame("Frame", "Next", sf)
    next:SetSize(100, 200)
    next:SetPoint("TOPLEFT")
    sf:SetScrollChild(next)
    A.same({ Layout.rect(w, sc).bottom, Layout.rect(w, next).bottom }, { -150, -120 })
  end)
end

local function test_scroll_is_not_clamped_and_fires_the_script() -- W45
  HL.withLayout(SCREEN, function()
    local sf = scroller()
    local seen = recordScript(sf, "OnVerticalScroll")
    sf:SetVerticalScroll(500)
    A.eq(sf:GetVerticalScroll(), 500)
    A.same(seen, { { sf, 500 } })
    sf:SetVerticalScroll(500)
    A.eq(#seen, 1)
  end)
end

local function test_horizontal_scroll_fires_its_own_script() -- W45
  HL.withLayout(SCREEN, function()
    local sf = scroller()
    local horizontal = recordScript(sf, "OnHorizontalScroll")
    local vertical = recordScript(sf, "OnVerticalScroll")
    sf:SetHorizontalScroll(7)
    sf:SetHorizontalScroll(7)
    A.same(horizontal, { { sf, 7 } })
    A.eq(#vertical, 0)
  end)
end

local function test_scroll_range_changed_fires_on_update_scroll_child_rect() -- W45
  HL.withLayout(SCREEN, function()
    local sf, sc = scroller()
    local seen = recordScript(sf, "OnScrollRangeChanged")
    sf:UpdateScrollChildRect()
    sc:SetHeight(300)
    sf:UpdateScrollChildRect()
    A.same(seen, { { sf, 0, 150 }, { sf, 0, 250 } })
    sf:UpdateScrollChildRect()
    A.eq(#seen, 2)
    sc:SetWidth(250)
    sf:UpdateScrollChildRect()
    A.same(seen[3], { sf, 150, 250 })
  end)
end

return function()
  test_scroll_ranges_and_child_offset()
  test_a_scroll_child_without_anchors_sits_at_the_frame_top_left_assumed()
  test_an_anchorless_scroll_child_moves_with_the_scroll_offsets_assumed()
  test_a_replaced_scroll_child_without_anchors_has_no_rect_assumed()
  test_set_scroll_child_parents_the_child_to_the_frame_assumed()
  test_horizontal_scroll_moves_the_child_left_assumed()
  test_a_fresh_scroll_frame_has_no_child_and_no_scroll()
  test_get_scroll_child_returns_the_child()
  test_a_child_smaller_than_the_frame_has_no_range_assumed()
  test_a_child_without_a_rect_has_no_range_assumed()
  test_only_the_scroll_child_moves_assumed()
  test_replacing_the_scroll_child_stops_shifting_the_old_one_assumed()
  test_scroll_is_not_clamped_and_fires_the_script()
  test_horizontal_scroll_fires_its_own_script()
  test_scroll_range_changed_fires_on_update_scroll_child_rect()
end
