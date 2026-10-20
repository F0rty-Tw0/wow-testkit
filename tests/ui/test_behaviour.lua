-- Hand-written widget semantics: anchors, size, visibility, hierarchy, mouse and movement.
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets

local function pointOf(f, i)
  return { f:GetPoint(i) }
end

local function test_set_point_offsets_default_relative_to_parent()
  withWidgets("retail", function()
    local parent = _G.CreateFrame("Frame")
    local f = _G.CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", 10, -20)
    A.same(pointOf(f, 1), { "TOPLEFT", parent, "TOPLEFT", 10, -20 })
  end)
end

local function test_set_point_without_offsets_defaults_them_to_zero()
  withWidgets("retail", function(w)
    local other = _G.CreateFrame("Frame")
    local f = _G.CreateFrame("Frame")
    w:run("addon", f.SetPoint, f, "CENTER", other, "CENTER")
    A.same(pointOf(f), { "CENTER", other, "CENTER", 0, 0 })
  end)
end

local function test_set_point_relative_with_offsets_reuses_point()
  withWidgets("retail", function()
    local other = _G.CreateFrame("Frame")
    local f = _G.CreateFrame("Frame")
    f:SetPoint("left", other, 5, 6)
    A.same(pointOf(f), { "LEFT", other, "LEFT", 5, 6 })
  end)
end

local function test_set_point_replaces_same_point()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:SetPoint("TOP", 1, 1)
    f:SetPoint("BOTTOM", 2, 2)
    f:SetPoint("TOP", 3, 3)
    A.eq(f:GetNumPoints(), 2)
    A.eq(select(4, f:GetPoint(1)), 3)
  end)
end

local function test_set_all_points_anchors_both_corners()
  withWidgets("retail", function()
    local other = _G.CreateFrame("Frame")
    local f = _G.CreateFrame("Frame")
    f:SetPoint("TOP")
    f:SetAllPoints(other)
    A.same(pointOf(f, 1), { "TOPLEFT", other, "TOPLEFT", 0, 0 })
    A.same(pointOf(f, 2), { "BOTTOMRIGHT", other, "BOTTOMRIGHT", 0, 0 })
  end)
end

local function test_clear_all_points_removes_anchors()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:SetPoint("TOP")
    f:ClearAllPoints()
    A.eq(f:GetNumPoints(), 0)
    A.eq(f:GetPoint(1), nil)
  end)
end

local function test_size_setters_feed_getters()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    A.same({ f:GetSize() }, { 0, 0 })
    f:SetSize(30, 40)
    f:SetWidth(50)
    A.same({ f:GetSize() }, { 50, 40 })
    f:SetHeight(60)
    A.eq(f:GetHeight(), 60)
    A.eq(f:GetWidth(), 50)
  end)
end

local function test_child_of_hidden_parent_is_shown_not_visible()
  withWidgets("retail", function()
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, parent)
    parent:Hide()
    A.eq(child:IsShown(), true)
    A.eq(child:IsVisible(), false)
    parent:SetShown(true)
    A.eq(child:IsVisible(), true)
  end)
end

local function test_show_and_hide_fire_only_on_visibility_change()
  withWidgets("retail", function()
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, parent)
    local seen = {}
    local function record(name)
      return function()
        seen[#seen + 1] = name
      end
    end
    child:SetScript("OnShow", record("child show"))
    child:SetScript("OnHide", record("child hide"))
    child:Show()
    parent:Hide()
    child:Hide()
    child:Show()
    parent:Show()
    A.same(seen, { "child hide", "child show" })
  end)
end

local function test_create_regions_are_listed_with_parent()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    local tex = f:CreateTexture()
    local text = f:CreateFontString("MyText")
    A.same({ f:GetRegions() }, { tex, text })
    A.eq(tex:GetParent(), f)
    A.eq(_G.MyText, text)
    A.eq(text:GetObjectType(), "FontString")
  end)
end

local function test_animation_group_has_parent_but_is_not_a_region()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    local group = f:CreateAnimationGroup()
    A.eq(group:GetParent(), f)
    A.eq(select("#", f:GetRegions()), 0)
  end)
end

local function test_children_follow_set_parent()
  withWidgets("retail", function()
    local a = _G.CreateFrame("Frame")
    local b = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, a)
    A.same({ a:GetChildren() }, { child })
    child:SetParent(b)
    A.eq(select("#", a:GetChildren()), 0)
    A.same({ b:GetChildren() }, { child })
    A.eq(child:GetParent(), b)
  end)
end

local function test_set_parent_to_self_or_a_descendant_errors_and_keeps_the_parent_assumed()
  withWidgets("retail", function()
    local a = _G.CreateFrame("Frame", "LoopA")
    local b = _G.CreateFrame("Frame", "LoopB", a)
    local c = _G.CreateFrame("Frame", nil, b)
    local ok, err = pcall(a.SetParent, a, c)
    A.eq(ok, false)
    A.truthy(tostring(err):find("LoopA:SetParent(): Would create a loop parenting to Frame", 1, true), tostring(err))
    A.eq(a:GetParent(), nil)
    A.same({ b:GetChildren() }, { c })
    ok, err = pcall(b.SetParent, b, b)
    A.eq(ok, false)
    A.truthy(tostring(err):find("LoopB:SetParent(): Would create a loop parenting to LoopB", 1, true), tostring(err))
    A.eq(b:GetParent(), a)
  end)
end

local function test_object_type_checks_ancestors()
  withWidgets("retail", function()
    local check = _G.CreateFrame("CheckButton", "MyCheck")
    A.eq(check:GetObjectType(), "CheckButton")
    A.eq(check:IsObjectType("button"), true)
    A.eq(check:IsObjectType("Frame"), true)
    A.eq(check:IsObjectType("Texture"), false)
    A.eq(check:GetName(), "MyCheck")
  end)
end

local function test_mouse_flags_round_trip()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    A.eq(f:IsMouseEnabled(), false)
    f:EnableMouse(true)
    f:EnableMouseWheel(1)
    A.eq(f:IsMouseEnabled(), true)
    A.eq(f:IsMouseWheelEnabled(), true)
  end)
end

local function test_moving_a_movable_frame_is_scripted()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    f:SetMovable(true)
    f:StartMoving()
    f:StopMovingOrSizing()
    A.eq(f:IsMovable(), true)
    A.eq(w.unscripted["Frame:StartMoving"], nil)
    A.eq(w.unscripted["Frame:StopMovingOrSizing"], nil)
  end)
end

return function()
  test_set_point_offsets_default_relative_to_parent()
  test_set_point_without_offsets_defaults_them_to_zero()
  test_set_point_relative_with_offsets_reuses_point()
  test_set_point_replaces_same_point()
  test_set_all_points_anchors_both_corners()
  test_clear_all_points_removes_anchors()
  test_size_setters_feed_getters()
  test_child_of_hidden_parent_is_shown_not_visible()
  test_show_and_hide_fire_only_on_visibility_change()
  test_create_regions_are_listed_with_parent()
  test_animation_group_has_parent_but_is_not_a_region()
  test_children_follow_set_parent()
  test_set_parent_to_self_or_a_descendant_errors_and_keeps_the_parent_assumed()
  test_object_type_checks_ancestors()
  test_mouse_flags_round_trip()
  test_moving_a_movable_frame_is_scripted()
end
