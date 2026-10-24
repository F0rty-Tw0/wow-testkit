-- Geometry getters over the resolved rects: ui/behaviour_layout.lua, Layout.screenRect and the LY14 clamp.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Layout = require("ui.layout")

-- P: 300x200 at BOTTOMLEFT of the screen +100,+100 -> pixels x 100..400, y 100..300 (bottom-up).
local function panel()
  local p = _G.CreateFrame("Frame", nil, _G.UIParent)
  p:SetSize(300, 200)
  p:SetPoint("BOTTOMLEFT", 100, 100)
  return p
end

local function test_edges_center_and_rect_come_from_the_anchors() -- (LY6)
  HF.withFrameXML("retail", function()
    local p = panel()
    A.eq(p:GetLeft(), 100)
    A.eq(p:GetRight(), 400) -- 100 + 300
    A.eq(p:GetBottom(), 100)
    A.eq(p:GetTop(), 300) -- 100 + 200
    A.same({ p:GetCenter() }, { 250, 200 }) -- 100 + 300 / 2, 100 + 200 / 2
    A.same({ p:GetRect() }, { 100, 100, 300, 200 })
    A.eq(p:IsRectValid(), true)
  end)
end

local function test_a_region_with_no_rect_returns_nothing() -- (LY6)
  HF.withFrameXML("retail", function()
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    f:SetSize(10, 10)
    for _, name in ipairs({ "GetLeft", "GetRight", "GetTop", "GetBottom", "GetCenter", "GetRect", "GetScaledRect" }) do
      A.eq(select("#", f[name](f)), 0, name)
    end
    A.eq(f:IsRectValid(), false)
  end)
end

local function test_size_comes_from_two_anchors_and_ignore_rect_reads_the_set_size() -- (LY5, LY13)
  HF.withFrameXML("retail", function()
    local p = panel()
    local q = _G.CreateFrame("Frame", nil, p)
    q:SetPoint("TOPLEFT", p, "TOPLEFT")
    q:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -50, 0)
    -- x 100..(400 - 50) = 350 -> 250 wide; y 100..300 -> 200 tall
    A.same({ q:GetSize() }, { 250, 200 })
    A.same({ q:GetSize(true) }, { 0, 0 })
    q:SetWidth(40)
    A.eq(q:GetWidth(true), 40)
    A.eq(q:GetWidth(), 250)
    A.eq(q:GetHeight(), 200)
  end)
end

local function test_a_size_without_anchors_still_reads_back()
  HF.withFrameXML("retail", function()
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    A.same({ f:GetSize() }, { 0, 0 })
    f:SetSize(30, 40)
    A.same({ f:GetSize() }, { 30, 40 })
  end)
end

local function test_scaled_rect_multiplies_the_rect_by_the_effective_scale() -- (LY7)
  HF.withFrameXML("retail", function()
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    f:SetSize(25, 25)
    f:SetScale(2)
    f:SetPoint("BOTTOMLEFT", 100, 100)
    -- wiki API_ScriptRegion_GetRect: GetRect() 100, 100, 25, 25 and GetScaledRect() 200, 200, 50, 50
    A.same({ f:GetRect() }, { 100, 100, 25, 25 })
    A.same({ f:GetScaledRect() }, { 200, 200, 50, 50 })
    A.eq(f:GetLeft(), 100)
  end)
end

local function test_screen_rect_is_pixels_from_the_top_left()
  HF.withFrameXML("retail", function(w)
    -- P pixels x 100..400, y 100..300 bottom-up: top-left origin y = 1080 - 300 = 780
    A.same(Layout.screenRect(w, panel()), { x = 100, y = 780, width = 300, height = 200 })
    A.eq(Layout.screenRect(w, _G.CreateFrame("Frame")), nil)
  end)
end

local function test_hit_insets_round_trip_without_moving_the_rect()
  HF.withFrameXML("retail", function()
    local p = panel()
    p:SetHitRectInsets(1, 2, 3, 4)
    A.same({ p:GetHitRectInsets() }, { 1, 2, 3, 4 })
    A.same({ p:GetRect() }, { 100, 100, 300, 200 })
  end)
end

local function test_a_clamped_frame_stays_on_the_screen_assumed() -- (LY14)
  HF.withFrameXML("retail", function(w)
    local p = panel()
    p:SetPoint("BOTTOMLEFT", 1800, 100) -- x 1800..2100: 180 px past the 1920 edge
    A.eq(p:GetLeft(), 1800) -- not clamped yet
    p:SetClampedToScreen(true)
    A.eq(p:IsClampedToScreen(), true)
    -- shift = 1920 - 2100 = -180: left 1800 - 180 = 1620
    A.eq(p:GetLeft(), 1620)
    A.same(Layout.screenRect(w, p), { x = 1620, y = 780, width = 300, height = 200 })
    local child = _G.CreateFrame("Frame", nil, p)
    child:SetSize(10, 10)
    child:SetPoint("BOTTOMLEFT")
    A.eq(child:GetLeft(), 1620) -- anchored children follow the clamped rect
    p:SetPoint("BOTTOMLEFT", -50, -40) -- off the left and bottom edges: both shifts are positive
    A.same({ p:GetRect() }, { 0, 0, 300, 200 })
    p:SetClampedToScreen(false)
    A.same({ p:GetRect() }, { -50, -40, 300, 200 })
  end)
end

local function test_clamp_rect_insets_move_the_edges_that_must_stay_inside_assumed() -- (LY14)
  HF.withFrameXML("retail", function()
    local p = panel()
    p:SetPoint("BOTTOMLEFT", 1800, 100)
    p:SetClampedToScreen(true)
    p:SetClampRectInsets(0, 20, 0, 0) -- clamp right = right + 20 <= 1920, so right <= 1900
    A.same({ p:GetClampRectInsets() }, { 0, 20, 0, 0 })
    A.eq(p:GetLeft(), 1600) -- 1900 - 300
    p:SetClampRectInsets(0, -100, 0, 0) -- the right 100 px may leave the screen: right <= 2020
    A.eq(p:GetLeft(), 1720)
  end)
end

local function test_a_clamp_rect_larger_than_the_screen_keeps_its_left_and_top_edges_assumed() -- (LY14)
  HF.withFrameXML("retail", function()
    local p = _G.CreateFrame("Frame", nil, _G.UIParent)
    p:SetSize(2000, 1200) -- 80 px wider and 120 px taller than the 1920 x 1080 screen
    p:SetPoint("BOTTOMLEFT", 30, 40)
    p:SetClampedToScreen(true)
    -- left lands on 0 and top on 1080: bottom = 1080 - 1200 = -120
    A.same({ p:GetRect() }, { 0, -120, 2000, 1200 })
  end)
end

local function test_clamp_insets_scale_with_the_frame_assumed() -- (LY14, LY7)
  HF.withFrameXML("retail", function()
    local p = _G.CreateFrame("Frame", nil, _G.UIParent)
    p:SetScale(2)
    p:SetSize(100, 100) -- 200 px square
    p:SetPoint("BOTTOMLEFT", 900, 0) -- pixels x 1800..2000
    p:SetClampedToScreen(true)
    p:SetClampRectInsets(0, 10, 0, 0) -- 10 units = 20 px: right + 20 <= 1920, so right <= 1900
    A.eq(p:GetLeft(), 850) -- pixel left 1700 / 2
  end)
end

local function test_a_region_is_never_clamped()
  HF.withFrameXML("retail", function(w)
    local p = panel()
    local texture = p:CreateTexture()
    texture:SetSize(50, 50)
    texture:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 2000, 0)
    -- Texture has no SetClampedToScreen on the client; write the store the frame setter would fill.
    w.ui.state[texture].values.ClampedToScreen = { true, n = 1 }
    Layout.invalidate(w, texture)
    A.eq(texture:GetLeft(), 2100)
  end)
end

local function test_geometry_getters_are_not_counted_as_unscripted()
  HF.withFrameXML("retail", function(w)
    local p, loose = panel(), _G.CreateFrame("Frame")
    for _, f in ipairs({ p, loose }) do
      f:GetLeft()
      f:GetRight()
      f:GetTop()
      f:GetBottom()
      f:GetCenter()
      f:GetRect()
      f:GetScaledRect()
      f:IsRectValid()
      f:GetSize()
    end
    for _, name in ipairs({ "GetLeft", "GetRect", "GetScaledRect", "IsRectValid", "GetCenter", "GetSize" }) do
      A.eq(w.unscripted["Frame:" .. name], nil, name)
    end
  end)
end

return function()
  test_edges_center_and_rect_come_from_the_anchors()
  test_a_region_with_no_rect_returns_nothing()
  test_size_comes_from_two_anchors_and_ignore_rect_reads_the_set_size()
  test_a_size_without_anchors_still_reads_back()
  test_scaled_rect_multiplies_the_rect_by_the_effective_scale()
  test_screen_rect_is_pixels_from_the_top_left()
  test_hit_insets_round_trip_without_moving_the_rect()
  test_a_clamped_frame_stays_on_the_screen_assumed()
  test_clamp_rect_insets_move_the_edges_that_must_stay_inside_assumed()
  test_a_clamp_rect_larger_than_the_screen_keeps_its_left_and_top_edges_assumed()
  test_clamp_insets_scale_with_the_frame_assumed()
  test_a_region_is_never_clamped()
  test_geometry_getters_are_not_counted_as_unscripted()
end
