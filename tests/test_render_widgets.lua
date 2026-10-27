-- Widget state and backdrops of a frame item: render_widgets.lua through render_fields.lua.
local A = require("assert")
local H = require("tests.helpers.render")
local Render = require("render")

-- A 50x20 widget centred on UIParent, so the snapshot places it.
local function anchored(typeName, name, template)
  local frame = _G.CreateFrame(typeName, name, _G.UIParent, template)
  frame:SetSize(50, 20)
  frame:SetPoint("CENTER")
  return frame
end

local function test_edit_box_state()
  H.withRender(function(w)
    local box = anchored("EditBox", "Box")
    box:SetText("abc")
    box:SetCursorPosition(2)
    box:SetFocus()
    local widget = H.item(Render.snapshot(w), "Box").widget
    A.same(widget, { type = "EditBox", text = "abc", cursor = 2, focused = true, multiLine = false })
    box:SetMultiLine(true)
    box:ClearFocus()
    widget = H.item(Render.snapshot(w), "Box").widget
    A.eq(widget.multiLine, true)
    A.eq(widget.focused, false)
  end)
end

local function test_fresh_edit_box_reads_empty_text_and_cursor_zero()
  H.withRender(function(w)
    anchored("EditBox", "Fresh")
    A.same(H.item(Render.snapshot(w), "Fresh").widget, { type = "EditBox", text = "", cursor = 0, focused = false, multiLine = false })
  end)
end

local function test_check_button_and_button_state()
  H.withRender(function(w)
    local check = anchored("CheckButton", "Chk")
    check:SetChecked(true)
    check:Disable()
    anchored("Button", "Btn")
    local snap = Render.snapshot(w)
    A.same(H.item(snap, "Chk").widget, { type = "CheckButton", checked = true, enabled = false })
    A.same(H.item(snap, "Btn").widget, { type = "Button", enabled = true })
  end)
end

local function test_slider_and_status_bar_state()
  H.withRender(function(w)
    local slider = anchored("Slider", "Sld")
    slider:SetMinMaxValues(0, 10)
    slider:SetValue(4)
    slider:SetOrientation("HORIZONTAL")
    local bar = anchored("StatusBar", "Bar")
    bar:SetMinMaxValues(0, 200)
    bar:SetValue(50)
    bar:SetStatusBarColor(0, 1, 0)
    local snap = Render.snapshot(w)
    A.same(H.item(snap, "Sld").widget, { type = "Slider", value = 4, min = 0, max = 10, orientation = "HORIZONTAL" })
    A.same(H.item(snap, "Bar").widget, { type = "StatusBar", value = 50, min = 0, max = 200, color = { 0, 1, 0, 1 }, orientation = "HORIZONTAL" })
  end)
end

local function test_fresh_slider_and_status_bar_orientation() -- (V12)
  H.withRender(function(w)
    anchored("Slider", "FreshSld")
    anchored("StatusBar", "FreshBar")
    local snap = Render.snapshot(w)
    A.eq(H.item(snap, "FreshSld").widget.orientation, "VERTICAL")
    A.eq(H.item(snap, "FreshBar").widget.orientation, "HORIZONTAL")
    anchored("StatusBar", "TallBar"):SetOrientation("VERTICAL")
    A.eq(H.item(Render.snapshot(w), "TallBar").widget.orientation, "VERTICAL")
  end)
end

local function test_scrolling_message_frame_lines()
  H.withRender(function(w)
    local log = anchored("ScrollingMessageFrame", "Log")
    log:AddMessage("a", 1, 0, 0)
    log:AddMessage("b")
    local expected = { type = "ScrollingMessageFrame", lines = { { text = "a", r = 1, g = 0, b = 0 }, { text = "b", r = 1, g = 1, b = 1 } } }
    A.same(H.item(Render.snapshot(w), "Log").widget, expected)
  end)
end

local function test_plain_frame_has_no_widget_and_no_backdrop()
  H.withRender(function(w)
    anchored("Frame", "Plain")
    local item = H.item(Render.snapshot(w), "Plain")
    local snap = Render.snapshot(w)
    A.same({ item.widget, item.backdrop, H.piece(snap, "Plain", "center"), H.piece(snap, "Plain", "edge") }, {})
  end)
end

local function test_backdrop_exports_files_colours_and_insets() -- (V13)
  H.withRender(function(w)
    local frame = anchored("Frame", "BD", "BackdropTemplate")
    frame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame:SetBackdropBorderColor(1, 0, 0)
    local snap = Render.snapshot(w)
    local expected = {
      bgFile = "path:interface/buttons/white8x8",
      edgeFile = "path:interface/tooltips/ui-tooltip-border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
      color = { 0, 0, 0, 0.5 },
      borderColor = { 1, 0, 0, 1 },
    }
    A.same(H.piece(snap, "BD", "center").backdrop, expected)
    A.same(H.piece(snap, "BD", "edge").backdrop, expected)
    A.same(snap.assets["path:interface/buttons/white8x8"], { kind = "path", path = "Interface/Buttons/WHITE8X8" })
  end)
end

local function test_backdrop_colours_default_to_white() -- (V13)
  H.withRender(function(w)
    anchored("Frame", "WhiteBD", "BackdropTemplate"):SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    A.same(
      H.piece(Render.snapshot(w), "WhiteBD", "center").backdrop,
      { bgFile = "path:interface/buttons/white8x8", color = { 1, 1, 1, 1 }, borderColor = { 1, 1, 1, 1 } }
    )
  end)
end

local function test_cleared_backdrop_is_absent()
  H.withRender(function(w)
    local frame = anchored("Frame", "GoneBD", "BackdropTemplate")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetBackdrop(nil)
    A.eq(H.piece(Render.snapshot(w), "GoneBD", "center"), nil)
  end)
end

-- source: row V4 (confirmed) the backdrop's Center texture is in BACKGROUND and its edge pieces default to BORDER, so a
-- region in either layer sorts with them; assumed (the sublevel is 0 and a piece draws below a region of the same layer and
-- sublevel, as the frame is created first).
local function test_backdrop_pieces_sort_with_the_regions_of_their_layers_assumed()
  H.withRender(function(w)
    local frame = anchored("Frame", "SortBD", "BackdropTemplate")
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border" })
    local function region(name, layer, sublevel)
      local texture = frame:CreateTexture(name, layer, nil, sublevel)
      texture:SetAllPoints()
      texture:SetColorTexture(1, 0, 0, 1)
    end
    region("Art", "ARTWORK")
    region("Border", "BORDER")
    region("Back", "BACKGROUND")
    region("Under", "BACKGROUND", -1)
    local order = {}
    for _, item in ipairs(Render.snapshot(w).items) do
      if item.parent == "f" .. w.ui.state[frame].seq or item.name == "SortBD" then
        order[#order + 1] = item.piece or item.name
      end
    end
    A.same(order, { "SortBD", "Under", "center", "Back", "edge", "Border", "Art" })
  end)
end

local function test_backdrop_piece_follows_the_frame_alpha_and_has_no_name()
  H.withRender(function(w)
    local frame = anchored("Frame", "AlphaBD", "BackdropTemplate")
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    frame:SetAlpha(0.5)
    local snap = Render.snapshot(w)
    local piece = H.piece(snap, "AlphaBD", "center")
    A.same({ piece.alpha, piece.name, piece.layer, piece.rect }, { 0.5, nil, "BACKGROUND", H.rect(snap, "AlphaBD") })
    A.eq(H.piece(snap, "AlphaBD", "edge").layer, "BORDER")
  end)
end

local function test_widget_snapshot_leaves_unscripted_counts_alone()
  H.withRender(function(w)
    anchored("Slider", "S1")
    anchored("StatusBar", "S2")
    anchored("EditBox", "S3")
    anchored("Frame", "S4", "BackdropTemplate"):SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    local before = {}
    for key, count in pairs(w.unscripted) do
      before[key] = count
    end
    Render.snapshot(w)
    A.same(w.unscripted, before)
  end)
end

return function()
  test_edit_box_state()
  test_fresh_edit_box_reads_empty_text_and_cursor_zero()
  test_check_button_and_button_state()
  test_slider_and_status_bar_state()
  test_fresh_slider_and_status_bar_orientation()
  test_scrolling_message_frame_lines()
  test_plain_frame_has_no_widget_and_no_backdrop()
  test_backdrop_exports_files_colours_and_insets()
  test_backdrop_colours_default_to_white()
  test_cleared_backdrop_is_absent()
  test_backdrop_pieces_sort_with_the_regions_of_their_layers_assumed()
  test_backdrop_piece_follows_the_frame_alpha_and_has_no_name()
  test_widget_snapshot_leaves_unscripted_counts_alone()
end
