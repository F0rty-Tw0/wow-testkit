-- Range and scroll widgets of a render item's widget (render_widgets.lua, render_widgets_range.lua): the slider thumb, the
-- status bar texture and fill options, the scroll frame and the message frame lines. Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local A = require("assert")
local Fields = require("render_fields")
local H = require("tests.helpers.render")
local Render = require("render")
local S = require("tests.helpers.widget_snap")

local PATH = "Interface\\TargetingFrame\\UI-StatusBar"

local function test_slider_thumb_exports_look_and_size() -- W43
  H.withRender(function(w)
    local s = S.anchored("Slider", "Sl", nil, 100, 20)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(0, 10)
    s:SetValue(5)
    local thumb = s:CreateTexture("SlThumb")
    thumb:SetColorTexture(1, 0, 0)
    thumb:SetSize(10, 20)
    s:SetThumbTexture(thumb)
    local snap = Render.snapshot(w)
    A.same(H.item(snap, "Sl").widget.thumb, { width = 10, height = 20, color = { 1, 0, 0, 1 } })
    A.same(H.names(snap, "Sl"), { "Sl" })
  end)
end

local function test_a_fresh_slider_exports_no_thumb()
  H.withRender(function(w)
    S.anchored("Slider", "Sl")
    A.same(S.snap(w, "Sl").widget, { type = "Slider", value = 0, min = 0, max = 0, orientation = "VERTICAL" })
  end)
end

local function test_slider_orientation_getter_and_snapshot_agree() -- V12
  H.withRender(function(w)
    local s = S.anchored("Slider", "Sl")
    A.eq(S.snap(w, "Sl").widget.orientation, s:GetOrientation())
    s:SetOrientation("HORIZONTAL")
    A.eq(S.snap(w, "Sl").widget.orientation, s:GetOrientation())
  end)
end

local function test_status_bar_orientation_getter_and_snapshot_agree() -- V12
  H.withRender(function(w)
    local bar = S.anchored("StatusBar", "Bar")
    A.eq(S.snap(w, "Bar").widget.orientation, bar:GetOrientation())
    bar:SetOrientation("VERTICAL")
    A.eq(S.snap(w, "Bar").widget.orientation, bar:GetOrientation())
  end)
end

local function test_status_bar_exports_reverse_and_texture() -- W44
  H.withRender(function(w)
    local bar = S.anchored("StatusBar", "Bar")
    local fresh = S.snap(w, "Bar").widget
    A.eq(fresh.reverse, nil)
    A.eq(fresh.texture, nil)
    bar:SetReverseFill(true)
    bar:SetStatusBarTexture(PATH)
    local widget = S.snap(w, "Bar").widget
    A.eq(widget.reverse, true)
    A.same(widget.texture, { file = Fields.refPath(PATH) })
    bar:SetReverseFill(false)
    A.eq(S.snap(w, "Bar").widget.reverse, nil)
  end)
end

-- The part draws among the regions of its frame in its own layer, so the snapshot says which (only when it is not the
-- default ARTWORK, sublevel 0), for the viewer to stack the fill and the thumb among them.
local function test_a_slider_thumb_exports_its_draw_layer_when_not_the_default() -- W43
  H.withRender(function(w)
    local s = S.anchored("Slider", "Sl", nil, 100, 20)
    local thumb = s:CreateTexture("SlThumb", "OVERLAY", nil, 3)
    thumb:SetColorTexture(1, 0, 0)
    s:SetThumbTexture(thumb)
    local exported = S.snap(w, "Sl").widget.thumb
    A.same({ exported.layer, exported.sublevel }, { "OVERLAY", 3 })
  end)
end

local function test_a_status_bar_texture_exports_its_draw_layer_when_not_the_default() -- W44
  H.withRender(function(w)
    local bar = S.anchored("StatusBar", "Bar")
    local tex = bar:CreateTexture("BarTex", "BACKGROUND")
    tex:SetColorTexture(1, 1, 1)
    bar:SetStatusBarTexture(tex)
    local exported = S.snap(w, "Bar").widget.texture
    A.same({ exported.layer, exported.sublevel }, { "BACKGROUND", nil })
    tex:SetDrawLayer("ARTWORK", 0)
    A.same({ S.snap(w, "Bar").widget.texture.layer, S.snap(w, "Bar").widget.texture.sublevel }, { nil, nil })
  end)
end

local function test_status_bar_texture_region_is_not_drawn() -- W44
  H.withRender(function(w)
    local bar = S.anchored("StatusBar", "Bar")
    local tex = bar:CreateTexture("BarTex")
    tex:SetAllPoints()
    bar:SetStatusBarTexture(tex)
    A.same(H.names(Render.snapshot(w), "Bar"), { "Bar" })
  end)
end

local function test_a_path_on_an_adopted_bar_texture_draws_no_extra_region_assumed() -- W44
  H.withRender(function(w)
    local bar = S.anchored("StatusBar", "Bar")
    local tex = bar:CreateTexture("BarTex")
    tex:SetAllPoints()
    bar:SetStatusBarTexture(tex)
    local before = #Render.snapshot(w).items
    bar:SetStatusBarTexture(PATH)
    A.same({ #Render.snapshot(w).items, S.snap(w, "Bar").widget.texture }, { before, { file = Fields.refPath(PATH) } })
  end)
end

local function test_status_bar_exports_a_fill_style_other_than_standard() -- W44
  H.withRender(function(w)
    local bar = S.anchored("StatusBar", "Bar")
    A.eq(S.snap(w, "Bar").widget.fillStyle, nil)
    bar:SetFillStyle("CENTER")
    A.eq(S.snap(w, "Bar").widget.fillStyle, "CENTER")
    bar:SetFillStyle("STANDARD")
    A.eq(S.snap(w, "Bar").widget.fillStyle, nil)
  end)
end

local function scrollFrame()
  local sf = S.anchored("ScrollFrame", "Sf", nil, 100, 50)
  local sc = _G.CreateFrame("Frame", "Sc", sf)
  sc:SetSize(100, 200)
  sc:SetPoint("TOPLEFT")
  sf:SetScrollChild(sc)

  return sf
end

local function test_scroll_frame_widget_and_shifted_child_rect() -- W45
  H.withRender(function(w)
    local sf = scrollFrame()
    local before = H.item(Render.snapshot(w), "Sc")
    A.same(S.snap(w, "Sf").widget, { type = "ScrollFrame", child = before.id, h = 0, v = 0, hRange = 0, vRange = 150 })
    sf:SetVerticalScroll(30)
    local snap = Render.snapshot(w)
    A.same(H.item(snap, "Sf").widget, { type = "ScrollFrame", child = before.id, h = 0, v = 30, hRange = 0, vRange = 150 })
    A.eq(H.item(snap, "Sc").rect.y, before.rect.y - 30)
  end)
end

local function test_scroll_frame_exports_the_horizontal_offset_and_range() -- W45
  H.withRender(function(w)
    local sf = scrollFrame()
    _G.Sc:SetWidth(300)
    sf:SetHorizontalScroll(20)
    local widget = S.snap(w, "Sf").widget
    A.same({ widget.h, widget.hRange }, { 20, 200 })
  end)
end

local function test_a_scroll_frame_without_a_child_exports_no_child() -- W45
  H.withRender(function(w)
    S.anchored("ScrollFrame", "Sf")
    A.same(S.snap(w, "Sf").widget, { type = "ScrollFrame", h = 0, v = 0, hRange = 0, vRange = 0 })
  end)
end

local function test_message_frame_keeps_the_newest_max_lines_assumed() -- W46
  H.withRender(function(w)
    local log = S.anchored("ScrollingMessageFrame", "Log")
    log:SetMaxLines(2)
    log:AddMessage("a")
    log:AddMessage("b")
    log:AddMessage("c")
    A.eq(log:GetNumMessages(), 2)
    local texts = {}
    for i, line in ipairs(S.snap(w, "Log").widget.lines) do
      texts[i] = line.text
    end
    A.same(texts, { "b", "c" })
  end)
end

return function()
  test_slider_thumb_exports_look_and_size()
  test_a_fresh_slider_exports_no_thumb()
  test_slider_orientation_getter_and_snapshot_agree()
  test_status_bar_orientation_getter_and_snapshot_agree()
  test_status_bar_exports_reverse_and_texture()
  test_a_slider_thumb_exports_its_draw_layer_when_not_the_default()
  test_a_status_bar_texture_exports_its_draw_layer_when_not_the_default()
  test_status_bar_texture_region_is_not_drawn()
  test_a_path_on_an_adopted_bar_texture_draws_no_extra_region_assumed()
  test_status_bar_exports_a_fill_style_other_than_standard()
  test_scroll_frame_widget_and_shifted_child_rect()
  test_scroll_frame_exports_the_horizontal_offset_and_range()
  test_a_scroll_frame_without_a_child_exports_no_child()
  test_message_frame_keeps_the_newest_max_lines_assumed()
end
