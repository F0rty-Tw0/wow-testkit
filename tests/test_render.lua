-- Render snapshot: render.lua with render_order.lua and render_fields.lua. Rects are screen pixels, origin top-left.
local A = require("assert")
local H = require("tests.helpers.render")
local Json = require("json")
local Render = require("render")

local function makeFrame(name, width, height, parent)
  local frame = _G.CreateFrame("Frame", name, parent or _G.UIParent)
  frame:SetSize(width, height)
  frame:SetPoint("CENTER")
  return frame
end

-- A texture of frame placed over all of it.
local function makeTexture(frame, name, layer, subLevel)
  local texture = frame:CreateTexture(name, layer, nil, subLevel)
  texture:SetAllPoints()
  return texture
end

-- Frame "A" 200x120 CENTER of the screen: UI left 960-100=860, bottom 540-60=480, top 600 -> y = 1080-600 = 480.
-- "AIcon" 40x40 TOPLEFT of A + (10,-10): left 870, top 590 -> y 490.
-- "AText" "Hi" at size 12, TOPLEFT of A + (4,-4): left 864, top 596 -> y 484; width 2*0.5*12 = 12, height 1.15*12 = 13.8.
local function test_frame_and_region_rects_are_screen_pixels_assumed() -- (LY10)
  H.withRender(function(w)
    local a = makeFrame("A", 200, 120)
    makeTexture(a, "AFill")
    local icon = a:CreateTexture("AIcon")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", a, "TOPLEFT", 10, -10)
    local text = a:CreateFontString("AText")
    text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    text:SetText("Hi")
    text:SetPoint("TOPLEFT", a, "TOPLEFT", 4, -4)
    local snap = Render.snapshot(w)
    A.same(H.rect(snap, "A"), { x = 860, y = 480, width = 200, height = 120 })
    A.same(H.rect(snap, "AFill"), { x = 860, y = 480, width = 200, height = 120 })
    A.same(H.rect(snap, "AIcon"), { x = 870, y = 490, width = 40, height = 40 })
    local r = H.rect(snap, "AText")
    A.eq(r.x, 864)
    A.eq(r.y, 484)
    A.eq(r.width, 12)
    A.truthy(math.abs(r.height - 13.8) < 1e-9)
    A.eq(H.item(snap, "AIcon").parent, H.item(snap, "A").id)
  end)
end

local function test_header_screen_errors_and_assets()
  H.withRender(function(w)
    w:recordError("boom")
    local snap = Render.snapshot(w)
    A.eq(snap.ver, 1)
    A.same(snap.screen, { width = 1920, height = 1080, scale = 1 })
    A.same(snap.assets, {})
    A.eq(snap.errors[1].message, "boom")
  end)
end

local function test_frames_draw_by_strata_then_level_then_creation_assumed() -- (V1, V2, V3)
  H.withRender(function(w)
    makeFrame("OrdHi", 10, 10):SetFrameStrata("HIGH")
    makeFrame("OrdA", 10, 10)
    makeFrame("OrdB", 10, 10)
    makeFrame("OrdLow", 10, 10):SetFrameLevel(0)
    A.same(H.names(Render.snapshot(w), "Ord"), { "OrdLow", "OrdA", "OrdB", "OrdHi" })
  end)
end

-- RText is created first, yet draws above both ARTWORK textures: a FontString has no sublevel and always draws
-- above the textures of its layer, so a plain sublevel-then-creation sort (RText before RArt) must fail here.
local function test_regions_draw_by_layer_then_sublevel_then_creation_assumed() -- (V4, V5, V6, V7, V8)
  H.withRender(function(w)
    local r = makeFrame("R", 100, 100)
    local text = r:CreateFontString("RText")
    text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    text:SetPoint("CENTER")
    makeTexture(r, "RArt")
    makeTexture(r, "RBack", "BACKGROUND")
    makeTexture(r, "ROver", "OVERLAY")
    makeTexture(r, "RArt2"):SetDrawLayer("ARTWORK", -1)
    makeFrame("RChild", 10, 10, r):SetFrameLevel(2)
    A.same(H.names(Render.snapshot(w), "R"), { "R", "RBack", "RArt2", "RArt", "RText", "ROver", "RChild" })
  end)
end

local function test_equal_layer_and_sublevel_draw_in_creation_order_assumed() -- (V7)
  H.withRender(function(w)
    local same = makeFrame("Same", 100, 100)
    makeTexture(same, "SameFirst", "BORDER", 3)
    makeTexture(same, "SameSecond", "BORDER", 3)
    A.same(H.names(Render.snapshot(w), "Same"), { "Same", "SameFirst", "SameSecond" })
  end)
end

local function test_font_string_ignores_sublevel() -- (V6)
  H.withRender(function(w)
    local fs = makeFrame("FS", 100, 100)
    makeTexture(fs, "FSTex", "ARTWORK", 7)
    local text = fs:CreateFontString("FSText")
    text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    text:SetPoint("CENTER")
    text:SetDrawLayer("ARTWORK", -8)
    A.same(H.names(Render.snapshot(w), "FS"), { "FS", "FSTex", "FSText" })
  end)
end

local function test_hidden_objects_are_skipped()
  H.withRender(function(w)
    local hiddenFrame = makeFrame("HidFrame", 10, 10)
    local shown = makeFrame("HidShown", 10, 10)
    makeTexture(shown, "HidTex"):Hide()
    makeFrame("HidKid", 10, 10, hiddenFrame)
    hiddenFrame:Hide()
    local snap = Render.snapshot(w)
    A.eq(H.item(snap, "HidFrame"), nil)
    A.eq(H.item(snap, "HidTex"), nil)
    A.eq(H.item(snap, "HidKid"), nil)
    A.truthy(H.item(snap, "HidShown"))
  end)
end

local function test_effective_alpha_multiplies_the_chain()
  H.withRender(function(w)
    local frame = makeFrame("AlphaFrame", 10, 10)
    frame:SetAlpha(0.5)
    makeTexture(frame, "AlphaTex"):SetAlpha(0.5)
    local snap = Render.snapshot(w)
    A.eq(H.item(snap, "AlphaTex").alpha, 0.25)
    A.eq(H.item(snap, "AlphaFrame").alpha, 0.5)
  end)
end

local function test_highlight_layer_draws_only_over_the_mouse() -- (V9)
  H.withRender(function(w)
    local button = _G.CreateFrame("Button", "Btn", _G.UIParent)
    button:SetSize(50, 20)
    button:SetPoint("CENTER")
    makeTexture(button, "BtnHi", "HIGHLIGHT")
    local kid = _G.CreateFrame("Frame", "BtnKid", button)
    A.eq(H.item(Render.snapshot(w), "BtnHi"), nil)
    w.input.mouseFocus = button
    A.truthy(H.item(Render.snapshot(w), "BtnHi"))
    w.input.mouseFocus = kid
    A.truthy(H.item(Render.snapshot(w), "BtnHi"))
  end)
end

-- Clipper 100x100 CENTER: left 910, bottom 490, top 590 -> y 490.
local function test_clip_rects_come_from_clipping_ancestors_assumed() -- (V10)
  H.withRender(function(w)
    local clipper = makeFrame("Clipper", 100, 100)
    clipper:SetClipsChildren(true)
    local tex = clipper:CreateTexture("ClipTex")
    tex:SetSize(200, 200)
    tex:SetPoint("CENTER", clipper, "CENTER")
    local inner = _G.CreateFrame("Frame", "Inner", clipper)
    inner:SetSize(60, 60)
    inner:SetPoint("BOTTOMLEFT", clipper, "BOTTOMLEFT")
    inner:SetClipsChildren(true)
    makeTexture(inner, "InnerTex")
    makeFrame("Plain", 10, 10)
    local snap = Render.snapshot(w)
    local clipperRect = { x = 910, y = 490, width = 100, height = 100 }
    A.same(H.rect(snap, "ClipTex"), { x = 860, y = 440, width = 200, height = 200 })
    A.same(H.item(snap, "ClipTex").clip, clipperRect)
    A.eq(H.item(snap, "Clipper").clip, nil)
    A.eq(H.item(snap, "Plain").clip, nil)
    A.same(H.item(snap, "InnerTex").clip, { x = 910, y = 530, width = 60, height = 60 })
    A.same(H.item(snap, "Inner").clip, clipperRect)
  end)
end

local function test_scroll_frame_clips_its_scroll_child_assumed() -- (V10)
  H.withRender(function(w)
    local scroll = _G.CreateFrame("ScrollFrame", "Scroll", _G.UIParent)
    scroll:SetSize(100, 100)
    scroll:SetPoint("CENTER")
    local child = _G.CreateFrame("Frame", "ScrollChild", scroll)
    child:SetSize(300, 300)
    child:SetPoint("CENTER")
    scroll:SetScrollChild(child)
    A.same(H.item(Render.snapshot(w), "ScrollChild").clip, { x = 910, y = 490, width = 100, height = 100 })
  end)
end

local function test_objects_without_a_rect_are_unplaced()
  H.withRender(function(w)
    _G.CreateFrame("Frame", "Loose", _G.UIParent)
    local snap = Render.snapshot(w)
    A.eq(H.item(snap, "Loose"), nil)
    local found
    for _, entry in ipairs(snap.unplaced) do
      if entry.name == "Loose" then
        found = entry
      end
    end
    A.eq(found.kind, "frame")
    A.eq(found.id:sub(1, 1), "f")
  end)
end

local function test_snapshot_leaves_unscripted_counts_alone()
  H.withRender(function(w)
    makeTexture(makeFrame("Quiet", 100, 100), "QuietTex")
    local before = {}
    for key, count in pairs(w.unscripted) do
      before[key] = count
    end
    Render.snapshot(w)
    A.same(w.unscripted, before)
  end)
end

local function test_snapshot_encodes_to_json()
  H.withRender(function(w)
    makeFrame("Enc", 10, 10)
    A.contains(Json.encode(Render.snapshot(w)), '"ver":1')
  end)
end

return function()
  test_frame_and_region_rects_are_screen_pixels_assumed()
  test_header_screen_errors_and_assets()
  test_frames_draw_by_strata_then_level_then_creation_assumed()
  test_regions_draw_by_layer_then_sublevel_then_creation_assumed()
  test_equal_layer_and_sublevel_draw_in_creation_order_assumed()
  test_font_string_ignores_sublevel()
  test_hidden_objects_are_skipped()
  test_effective_alpha_multiplies_the_chain()
  test_highlight_layer_draws_only_over_the_mouse()
  test_clip_rects_come_from_clipping_ancestors_assumed()
  test_scroll_frame_clips_its_scroll_child_assumed()
  test_objects_without_a_rect_are_unplaced()
  test_snapshot_leaves_unscripted_counts_alone()
  test_snapshot_encodes_to_json()
end
