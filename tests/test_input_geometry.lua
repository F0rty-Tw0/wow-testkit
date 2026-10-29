-- Input.frameAt and the rect-based IsMouseOver: hit rects from ui/layout_hit.lua, strata/level/creation order.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local Input = require("input")
local LayoutHit = require("ui.layout_hit")
local RenderOrder = require("render_order")

-- Screen 1920x1080, UIParent at scale 1.
local function inWorld(fn)
  HF.withFrameXML("retail", fn, { screen = { width = 1920, height = 1080 } })
end

-- A mouse-enabled frame under UIParent, BOTTOMLEFT of the screen +x,+y. Top-left-origin y = 1080 - top.
local function box(x, y, width, height)
  local f = _G.CreateFrame("Frame", nil, _G.UIParent)
  f:SetSize(width, height)
  f:SetPoint("BOTTOMLEFT", x, y)
  f:EnableMouse(true)
  return f
end

-- a: pixels x 100..300, bottom-up y 100..300 -> top-left y 780..980.
-- b: x 150..250, bottom-up y 150..250 -> top-left y 830..930; (160, 900) is inside both.
local function test_frame_at_returns_the_frame_under_the_point()
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    A.eq(Input.frameAt(w, 150, 900), a)
    A.eq(Input.frameAt(w, 150, 700), nil) -- above the frame (y < 780)
    A.eq(Input.frameAt(w, 350, 900), nil) -- right of it (x >= 300)
    A.eq(Input.frameAt(w, 5, 5), nil) -- UIParent is not mouse-enabled
  end)
end

local function test_edge_pixels_are_inside_on_the_low_side_assumed() -- (LY11)
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    A.eq(Input.frameAt(w, 100, 900), a)
    A.eq(Input.frameAt(w, 300, 900), nil)
    A.eq(Input.frameAt(w, 150, 780), a)
    A.eq(Input.frameAt(w, 150, 980), nil)
  end)
end

local function test_overlap_goes_to_the_higher_level_then_the_later_frame_assumed() -- (LY12)
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    local b = box(150, 150, 100, 100)
    A.eq(Input.frameAt(w, 160, 900), b) -- same level (UIParent's 0 + 1): created later wins
    a:SetFrameLevel(5)
    A.eq(Input.frameAt(w, 160, 900), a)
  end)
end

local function test_the_later_frame_wins_whatever_the_iteration_order_assumed() -- (LY12)
  inWorld(function(w)
    local frames = {}
    for i = 1, 40 do
      frames[i] = box(100, 100, 200, 200)
    end
    A.eq(Input.frameAt(w, 150, 900), frames[40])
  end)
end

local function test_strata_beats_level_assumed() -- (LY12)
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    local b = box(150, 150, 100, 100)
    a:SetFrameLevel(100)
    b:SetFrameStrata("HIGH")
    A.eq(Input.frameAt(w, 160, 900), b)
  end)
end

local function test_strata_rank_follows_the_wiki_order() -- (LY12)
  inWorld(function(w)
    local order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
    local frames = {}
    for i, strata in ipairs(order) do
      frames[i] = box(100, 100, 200, 200)
      frames[i]:SetFrameStrata(strata)
    end
    for i = #order, 1, -1 do
      A.eq(Input.frameAt(w, 150, 900), frames[i], order[i])
      frames[i]:Hide()
    end
  end)
end

-- The frame drawn last of the given ones (render_order.lua's draw order).
local function drawnOnTop(w, frames)
  local wanted, top = {}, nil
  for _, frame in ipairs(frames) do
    wanted[frame] = true
  end
  for _, entry in ipairs(RenderOrder.collect(w)) do
    top = wanted[entry.obj] and entry.obj or top
  end

  return top
end

-- BLIZZARD (a FRAMESTRATA with no rank here) draws as MEDIUM and a lowercase name as its strata; the hit follows the
-- draw. WORLD and unknown names raise (test_behaviour_render.lua). Each odd frame is made first, so a tie with the frame
-- below it (made later) would draw that one on top: "high" must rank above MEDIUM, not fall back to it.
local function test_the_hit_follows_the_draw_order_for_odd_strata_assumed() -- (LY12)
  inWorld(function(w)
    for odd, below in pairs({ BLIZZARD = "LOW", high = "MEDIUM" }) do
      local oddFrame = box(100, 100, 200, 200)
      oddFrame:SetFrameStrata(odd)
      local under = box(100, 100, 200, 200)
      under:SetFrameStrata(below)
      oddFrame:SetFrameLevel(under:GetFrameLevel())
      A.eq(drawnOnTop(w, { under, oddFrame }), oddFrame, odd)
      A.eq(Input.frameAt(w, 150, 900), oddFrame, odd)
      under:Hide()
      oddFrame:Hide()
    end
  end)
end

local function test_hidden_and_mouse_disabled_frames_are_skipped()
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    local b = box(150, 150, 100, 100)
    b:Hide()
    A.eq(Input.frameAt(w, 160, 900), a)
    b:Show()
    b:EnableMouse(false)
    A.eq(Input.frameAt(w, 160, 900), a)
  end)
end

local function test_a_child_of_a_hidden_parent_is_skipped()
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    local child = _G.CreateFrame("Frame", nil, a)
    child:SetAllPoints()
    child:EnableMouse(true)
    A.eq(Input.frameAt(w, 150, 900), child)
    a:Hide()
    A.eq(Input.frameAt(w, 150, 900), nil)
  end)
end

local function test_a_texture_is_never_a_target()
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    local tex = a:CreateTexture()
    tex:SetAllPoints()
    A.eq(Input.frameAt(w, 150, 900), a)
  end)
end

local function test_hit_rect_insets_shrink_the_target() -- (LY11)
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    a:SetHitRectInsets(50, 0, 0, 0) -- left 50: hit x 150..300
    A.eq(Input.frameAt(w, 120, 900), nil)
    A.eq(Input.frameAt(w, 160, 900), a)
    a:SetHitRectInsets(-50, 0, 0, 0) -- a negative inset grows it: x 50..300
    A.eq(Input.frameAt(w, 60, 900), a)
  end)
end

local function test_layout_hit_rect_applies_each_inset_to_its_side() -- (LY11)
  inWorld(function(w)
    local a = box(100, 100, 200, 200) -- screen x 100, y 780, 200 x 200
    a:SetHitRectInsets(10, 20, 30, 40) -- left, right, top, bottom
    A.same(LayoutHit.rect(w, a), { x = 110, y = 810, width = 170, height = 130 })
    -- offsets (top, bottom, left, right): top grows up, negative bottom grows down, negative left grows left
    A.same(LayoutHit.rect(w, a, 5, -5, -5, 5), { x = 105, y = 805, width = 180, height = 140 })
    a:SetHitRectInsets(100, 100, 0, 0) -- no width left
    A.eq(LayoutHit.rect(w, a), nil)
  end)
end

local function test_layout_hit_rect_scales_insets_and_offsets_by_the_effective_scale() -- (LY11)
  inWorld(function(w)
    local a = box(100, 100, 100, 100)
    a:SetScale(2) -- pixels x 200..400, bottom-up y 200..400 -> top-left y 680..880
    a:SetHitRectInsets(10, 0, 0, 0)
    A.same(LayoutHit.rect(w, a, 0, 0, 0, 5), { x = 220, y = 680, width = 190, height = 200 })
  end)
end

local function test_is_mouse_over_tests_the_cursor_against_the_rect()
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    Input.setCursor(w, 160, 900)
    A.eq(a:IsMouseOver(), true)
    Input.setCursor(w, 350, 900)
    A.eq(a:IsMouseOver(), false)
    A.eq(a:IsMouseOver(0, 0, 0, 60), true) -- offsetRight 60 grows x to 360 (assumed sign, LY11)
  end)
end

local function test_is_mouse_over_grows_the_rect_by_each_offset_in_its_direction() -- (LY11)
  inWorld(function(w)
    local a = box(100, 100, 200, 200) -- screen x 100..300, y 780..980
    Input.setCursor(w, 150, 770) -- 10 above the top edge
    A.eq(a:IsMouseOver(), false)
    A.eq(a:IsMouseOver(10, 0, 0, 0), true) -- offsetTop grows it up
    Input.setCursor(w, 150, 990) -- 10 below the bottom edge
    A.eq(a:IsMouseOver(0, 0, 0, 0), false)
    A.eq(a:IsMouseOver(0, -11, 0, 0), true) -- negative offsetBottom grows it down
    A.eq(a:IsMouseOver(0, 11, 0, 0), false) -- positive offsetBottom shrinks it
    Input.setCursor(w, 90, 900) -- 10 left of the left edge
    A.eq(a:IsMouseOver(0, 0, -11, 0), true) -- negative offsetLeft grows it left
    A.eq(a:IsMouseOver(0, 0, 11, 0), false)
  end)
end

local function test_is_mouse_over_uses_the_hit_insets_assumed() -- (LY11)
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    a:SetHitRectInsets(50, 0, 0, 0)
    Input.setCursor(w, 120, 900)
    A.eq(a:IsMouseOver(), false)
    A.eq(a:IsMouseOver(0, 0, -30, 0), true)
  end)
end

local function test_is_mouse_over_does_not_include_descendants_with_a_cursor()
  inWorld(function(w)
    local a = box(100, 100, 100, 100)
    local child = _G.CreateFrame("Frame", nil, a)
    child:SetSize(50, 50)
    child:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT", 100, 0) -- outside a: x 300..350
    Input.setCursor(w, 320, 960)
    A.eq(child:IsMouseOver(), true)
    A.eq(a:IsMouseOver(), false)
  end)
end

local function test_is_mouse_over_falls_back_to_the_focus_chain_without_a_cursor()
  inWorld(function(w)
    local a = box(100, 100, 200, 200)
    local child = _G.CreateFrame("Frame", nil, a)
    w.input.mouseFocus = child
    A.eq(a:IsMouseOver(), true)
    Input.setCursor(w, 5, 5) -- a cursor elsewhere: the rect decides
    A.eq(a:IsMouseOver(), false)
    Input.setCursor(w, nil)
    A.eq(a:IsMouseOver(), true)
  end)
end

local function test_set_cursor_stores_the_point_and_nil_clears_it()
  inWorld(function(w)
    Input.setCursor(w, 3, 4)
    A.same(w.input.cursor, { 3, 4 })
    Input.setCursor(w, nil)
    A.eq(w.input.cursor, nil)
  end)
end

local function test_seq_counts_creation_order_across_all_widgets()
  inWorld(function(w)
    local a = _G.CreateFrame("Frame")
    local b = _G.CreateFrame("Frame")
    local tex = b:CreateTexture()
    local sa, sb, st = w.ui.state[a].seq, w.ui.state[b].seq, w.ui.state[tex].seq
    A.eq(sb, sa + 1)
    A.eq(st, sb + 1)
    A.eq(w.ui.seq, st)
  end)
end

return function()
  test_frame_at_returns_the_frame_under_the_point()
  test_edge_pixels_are_inside_on_the_low_side_assumed()
  test_overlap_goes_to_the_higher_level_then_the_later_frame_assumed()
  test_the_later_frame_wins_whatever_the_iteration_order_assumed()
  test_strata_beats_level_assumed()
  test_strata_rank_follows_the_wiki_order()
  test_the_hit_follows_the_draw_order_for_odd_strata_assumed()
  test_hidden_and_mouse_disabled_frames_are_skipped()
  test_a_child_of_a_hidden_parent_is_skipped()
  test_a_texture_is_never_a_target()
  test_hit_rect_insets_shrink_the_target()
  test_layout_hit_rect_applies_each_inset_to_its_side()
  test_layout_hit_rect_scales_insets_and_offsets_by_the_effective_scale()
  test_is_mouse_over_tests_the_cursor_against_the_rect()
  test_is_mouse_over_grows_the_rect_by_each_offset_in_its_direction()
  test_is_mouse_over_uses_the_hit_insets_assumed()
  test_is_mouse_over_does_not_include_descendants_with_a_cursor()
  test_is_mouse_over_falls_back_to_the_focus_chain_without_a_cursor()
  test_set_cursor_stores_the_point_and_nil_clears_it()
  test_seq_counts_creation_order_across_all_widgets()
end
