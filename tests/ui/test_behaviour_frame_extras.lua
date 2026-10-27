-- Frame extras (ui/behaviour_frame_extras.lua): raise and lower, the id and flag pairs, child and region counts, and
-- RegisterAllEvents. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local HW = require("tests.helpers.widgets")

local function newFrame(parent)
  return _G.CreateFrame("Frame", nil, parent)
end

-- Two siblings under one parent at the given levels.
local function pair(aLevel, bLevel)
  local parent = newFrame()
  local a, b = newFrame(parent), newFrame(parent)
  a:SetFrameLevel(aLevel)
  b:SetFrameLevel(bLevel)

  return a, b
end

local function test_raise_goes_above_the_highest_sibling_assumed() -- W48
  HW.withWidgets("retail", function()
    local a = pair(3, 7)
    a:Raise()
    A.eq(a:GetFrameLevel(), 8)
  end)
end

local function test_lower_goes_below_the_lowest_sibling_assumed() -- W48
  HW.withWidgets("retail", function()
    local a, b = pair(3, 7)
    b:Lower()
    A.eq(b:GetFrameLevel(), 2)
    A.eq(a:GetFrameLevel(), 3)
  end)
end

local function test_raise_goes_above_a_sibling_at_the_same_level_assumed() -- W48
  HW.withWidgets("retail", function()
    local a = pair(5, 5)
    a:Raise()
    A.eq(a:GetFrameLevel(), 6)
  end)
end

local function test_lower_goes_below_a_sibling_at_the_same_level_assumed() -- W48
  HW.withWidgets("retail", function()
    local a = pair(5, 5)
    a:Lower()
    A.eq(a:GetFrameLevel(), 4)
  end)
end

local function test_raise_keeps_a_frame_that_is_already_on_top_assumed() -- W48
  HW.withWidgets("retail", function()
    local _, b = pair(3, 7)
    b:Raise()
    A.eq(b:GetFrameLevel(), 7)
  end)
end

local function test_lower_stops_at_level_zero_assumed() -- W48
  HW.withWidgets("retail", function()
    local _, b = pair(0, 4)
    b:Lower()
    A.eq(b:GetFrameLevel(), 0)
  end)
end

local function test_raise_ignores_siblings_of_another_strata_assumed() -- W48
  HW.withWidgets("retail", function()
    local a, b = pair(3, 7)
    b:SetFrameStrata("HIGH")
    a:Raise()
    A.eq(a:GetFrameLevel(), 3)
  end)
end

local function test_raise_on_a_frame_without_a_parent_changes_nothing_assumed() -- W48
  HW.withWidgets("retail", function()
    local f = newFrame()
    f:SetFrameLevel(4)
    f:Raise()
    f:Lower()
    A.eq(f:GetFrameLevel(), 4)
  end)
end

local function test_register_all_events_receives_any_fired_event_assumed() -- W54
  HW.withWidgets("retail", function(w)
    local f = newFrame()
    local seen = {}
    f:SetScript("OnEvent", function(_, event)
      seen[#seen + 1] = event
    end)
    f:RegisterAllEvents()
    w:fire("PLAYER_ENTERING_WORLD")
    A.same(seen, { "PLAYER_ENTERING_WORLD" })
  end)
end

local function test_register_all_events_flags_the_frame_for_the_event_lookup() -- W54
  HW.withWidgets("retail", function(w)
    local f = newFrame()
    f:RegisterAllEvents()
    A.eq(w:isEventRegistered(f, "PLAYER_LOGIN"), true)
    f:UnregisterAllEvents()
    A.eq(w:isEventRegistered(f, "PLAYER_LOGIN"), false)
  end)
end

local function test_id_defaults_to_zero_and_round_trips() -- W51
  HW.withWidgets("retail", function(w)
    local f = newFrame()
    A.eq(f:GetID(), 0)
    f:SetID(5)
    A.eq(f:GetID(), 5)
    A.eq(w.unscripted["Frame:GetID"], nil)
  end)
end

local function test_toplevel_defaults_to_false_and_round_trips() -- W49
  HW.withWidgets("retail", function()
    local f = newFrame()
    A.eq(f:IsToplevel(), false)
    f:SetToplevel(true)
    A.eq(f:IsToplevel(), true)
    f:SetToplevel(false)
    A.eq(f:IsToplevel(), false)
  end)
end

local function test_fixed_level_and_strata_default_to_false_and_round_trip() -- W50
  HW.withWidgets("retail", function()
    local f = newFrame()
    A.same({ f:HasFixedFrameLevel(), f:HasFixedFrameStrata() }, { false, false })
    f:SetFixedFrameLevel(true)
    A.same({ f:HasFixedFrameLevel(), f:HasFixedFrameStrata() }, { true, false })
    f:SetFixedFrameStrata(true)
    A.same({ f:HasFixedFrameLevel(), f:HasFixedFrameStrata() }, { true, true })
  end)
end

local function test_child_and_region_counts() -- W52
  HW.withWidgets("retail", function()
    local parent = newFrame()
    newFrame(parent)
    newFrame(parent)
    parent:CreateTexture()
    parent:CreateFontString()
    A.same({ parent:GetNumChildren(), parent:GetNumRegions() }, { 2, 2 })
    A.same({ newFrame():GetNumChildren(), newFrame():GetNumRegions() }, { 0, 0 })
  end)
end

local function test_keyboard_flags_are_stored() -- W53
  HW.withWidgets("retail", function()
    local f = newFrame()
    A.same({ f:IsKeyboardEnabled(), f:GetPropagateKeyboardInput() }, { false, false })
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    A.same({ f:IsKeyboardEnabled(), f:GetPropagateKeyboardInput() }, { true, true })
  end)
end

return function()
  test_raise_goes_above_the_highest_sibling_assumed()
  test_lower_goes_below_the_lowest_sibling_assumed()
  test_raise_goes_above_a_sibling_at_the_same_level_assumed()
  test_lower_goes_below_a_sibling_at_the_same_level_assumed()
  test_raise_keeps_a_frame_that_is_already_on_top_assumed()
  test_lower_stops_at_level_zero_assumed()
  test_raise_ignores_siblings_of_another_strata_assumed()
  test_raise_on_a_frame_without_a_parent_changes_nothing_assumed()
  test_register_all_events_receives_any_fired_event_assumed()
  test_register_all_events_flags_the_frame_for_the_event_lookup()
  test_id_defaults_to_zero_and_round_trips()
  test_toplevel_defaults_to_false_and_round_trips()
  test_fixed_level_and_strata_default_to_false_and_round_trip()
  test_child_and_region_counts()
  test_keyboard_flags_are_stored()
end
