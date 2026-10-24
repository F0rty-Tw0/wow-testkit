-- Anchor storage and point queries: ui/behaviour_layout.lua.
local A = require("assert")
local HF = require("tests.helpers.framexml")
local HW = require("tests.helpers.widgets")

local function frame(parent)
  return _G.CreateFrame("Frame", nil, parent)
end

local function test_clear_point_removes_only_that_anchor()
  HW.withWidgets("retail", function()
    local f = frame()
    f:SetPoint("TOP", 1, 1)
    f:SetPoint("BOTTOM", 2, 2)
    f:ClearPoint("top") -- case-insensitive like SetPoint
    A.eq(f:GetNumPoints(), 1)
    A.eq((f:GetPoint(1)), "BOTTOM")
    f:ClearPoint("CENTER") -- not set: nothing happens
    A.eq(f:GetNumPoints(), 1)
  end)
end

local function test_get_point_by_name_returns_that_anchor()
  HW.withWidgets("retail", function()
    local target, f = frame(), frame()
    f:SetPoint("TOP", target, "BOTTOM", 3, 4)
    A.same({ f:GetPointByName("TOP") }, { "TOP", target, "BOTTOM", 3, 4 })
    A.eq(select("#", f:GetPointByName("LEFT")), 0)
  end)
end

local function test_get_point_past_the_end_returns_nothing()
  HW.withWidgets("retail", function()
    local f = frame()
    f:SetPoint("TOP")
    A.eq(select("#", f:GetPoint(2)), 0)
  end)
end

local function test_omitted_relative_to_anchors_to_the_parent_or_the_screen() -- (LY1)
  HF.withFrameXML("retail", function()
    local parent = frame(_G.UIParent)
    local child = frame(parent)
    child:SetPoint("TOPLEFT", 10, -20)
    A.same({ child:GetPoint() }, { "TOPLEFT", parent, "TOPLEFT", 10, -20 })
    local loose = frame() -- no parent: the screen, whose GetPoint answer is nil
    loose:SetPoint("CENTER", 5, 6)
    A.eq(select("#", loose:GetPoint()), 5)
    A.same({ loose:GetPoint() }, { "CENTER", nil, "CENTER", 5, 6 })
  end)
end

-- (LY2) wiki API_Region_SetPoint: explicit nil anchors to the screen (user ruling 2026-10-24; spec §4 differs).
local function test_explicit_nil_relative_to_anchors_to_the_screen() -- (LY2)
  HF.withFrameXML("retail", function()
    local parent = frame(_G.UIParent)
    local child = frame(parent)
    child:SetPoint("TOP", nil, "BOTTOM", 1, 2)
    A.same({ child:GetPoint() }, { "TOP", nil, "BOTTOM", 1, 2 })
    A.eq(select("#", child:GetPoint()), 5)
  end)
end

local function test_string_relative_to_resolves_through_globals() -- (LY4)
  HW.withWidgets("retail", function()
    local target = _G.CreateFrame("Frame", "TkAnchorTarget")
    local f = frame()
    f:SetPoint("TOP", "TkAnchorTarget", "BOTTOM")
    A.same({ f:GetPoint() }, { "TOP", target, "BOTTOM", 0, 0 })
  end)
end

local function test_missing_global_name_anchors_to_the_screen_assumed() -- (LY4)
  HW.withWidgets("retail", function()
    local f = frame()
    f:SetPoint("TOP", "TkNoSuchFrame")
    A.eq(f:GetNumPoints(), 1)
    A.eq(select(2, f:GetPoint()), nil)
  end)
end

local function test_set_all_points_defaults_to_the_parent_and_replaces_older_anchors() -- (LY1)
  HF.withFrameXML("retail", function()
    local parent = frame(_G.UIParent)
    local child = frame(parent)
    child:SetPoint("CENTER")
    child:SetAllPoints()
    A.eq(child:GetNumPoints(), 2)
    A.same({ child:GetPoint(1) }, { "TOPLEFT", parent, "TOPLEFT", 0, 0 })
    A.same({ child:GetPoint(2) }, { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0 })
    local loose = frame()
    loose:SetAllPoints()
    A.eq(select(2, loose:GetPoint(1)), nil)
  end)
end

return function()
  test_clear_point_removes_only_that_anchor()
  test_get_point_by_name_returns_that_anchor()
  test_get_point_past_the_end_returns_nothing()
  test_omitted_relative_to_anchors_to_the_parent_or_the_screen()
  test_explicit_nil_relative_to_anchors_to_the_screen()
  test_string_relative_to_resolves_through_globals()
  test_missing_global_name_anchors_to_the_screen_assumed()
  test_set_all_points_defaults_to_the_parent_and_replaces_older_anchors()
end
