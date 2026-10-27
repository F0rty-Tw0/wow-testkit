-- Animation timing and properties: orders, delays, smoothing, progress and the defaults of every animation getter. Rule
-- tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local AG = require("tests.helpers.anim_group")
local HW = require("tests.helpers.widgets")

local group, recorder = AG.group, AG.recorder
local withWidgets = HW.withWidgets

local function test_orders_default_to_one_and_durations_to_zero() -- W57
  withWidgets("retail", function()
    local animGroup = _G.CreateFrame("Frame"):CreateAnimationGroup()
    local plain = animGroup:CreateAnimation("Translation")
    A.same({ plain:GetOrder(), plain:GetDuration(), plain:GetStartDelay(), plain:GetEndDelay() }, { 1, 0, 0, 0 })
    plain:SetOrder(3)
    A.eq(plain:GetOrder(), 3)
  end)
end

local function test_orders_sequence_and_equal_orders_overlap_assumed() -- W57
  withWidgets("retail", function(w)
    local _, animGroup, a1 = group()
    a1:SetOrder(1)
    local a2, a3 = animGroup:CreateAnimation("Alpha"), animGroup:CreateAnimation("Alpha")
    a2:SetOrder(2)
    a2:SetDuration(2)
    a3:SetOrder(2)
    a3:SetDuration(1)
    local log = recorder(animGroup)
    A.eq(animGroup:GetDuration(), 3)
    animGroup:Play()
    w:advance(1.5)
    A.same({ a1:GetProgress(), a2:GetProgress(), a3:GetProgress() }, { 1, 0.25, 0.5 })
    w:advance(1.25)
    A.same(log, { "play" })
    w:advance(0.25)
    A.same(log, { "play", "fin:false" })
  end)
end

local function test_orders_run_by_number_not_by_creation_assumed() -- W57
  withWidgets("retail", function(w)
    local _, animGroup, early = group()
    early:SetOrder(5)
    local late, zero = animGroup:CreateAnimation("Alpha"), animGroup:CreateAnimation("Translation")
    late:SetOrder(2)
    late:SetDuration(2)
    zero:SetOrder(9)
    A.same({ animGroup:GetDuration(), zero:GetProgress() }, { 3, 0 })
    animGroup:Play()
    w:advance(2.5)
    A.same({ late:GetProgress(), early:GetProgress(), zero:GetProgress() }, { 1, 0.5, 0 })
    w:advance(0.5)
    A.same({ early:GetProgress(), zero:GetProgress() }, { 1, 1 })
  end)
end

local function test_negative_durations_and_delays_count_as_zero_assumed() -- W57
  withWidgets("retail", function()
    local _, animGroup, alpha = group()
    alpha:SetDuration(3)
    alpha:SetStartDelay(-2)
    alpha:SetEndDelay(-3)
    A.eq(animGroup:GetDuration(), 3)
  end)
end

local function test_progress_is_one_after_a_finish_and_zero_after_a_stop_assumed()
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group()
    A.eq(alpha:GetProgress(), 0)
    animGroup:Play()
    w:advance(2)
    A.eq(alpha:GetProgress(), 1)
    animGroup:Play()
    w:advance(0.5)
    animGroup:Stop()
    A.eq(alpha:GetProgress(), 0)
  end)
end

local function test_elapsed_is_the_seconds_into_the_animation_assumed()
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group()
    alpha:SetDuration(2)
    alpha:SetStartDelay(1)
    animGroup:Play()
    w:advance(2)
    A.same({ alpha:GetElapsed(), alpha:GetProgress() }, { 1, 0.5 })
  end)
end

local function test_smoothing_defaults_to_none_and_out_in_aliases_in_out() -- W64
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group()
    A.eq(alpha:GetSmoothing(), "NONE")
    alpha:SetSmoothing("OUT_IN")
    A.eq(alpha:GetSmoothing(), "OUT_IN")
    animGroup:Play()
    w:advance(0.25)
    A.eq(alpha:GetSmoothProgress(), 0.15625)
  end)
end

local function test_smoothing_curves_assumed() -- W64
  withWidgets("retail", function(w)
    local expected = { NONE = 0.5, IN = 0.25, OUT = 0.75, IN_OUT = 0.5 }
    for smoothing, value in pairs(expected) do
      local _, animGroup, alpha = group()
      alpha:SetSmoothing(smoothing)
      animGroup:Play()
      w:advance(0.5)
      A.same({ smoothing, alpha:GetProgress(), alpha:GetSmoothProgress() }, { smoothing, 0.5, value })
      animGroup:Stop()
    end
    local _, animGroup, alpha = group()
    alpha:SetSmoothing("IN_OUT")
    animGroup:Play()
    w:advance(0.25)
    A.eq(alpha:GetSmoothProgress(), 3 * 0.0625 - 2 * 0.015625)
  end)
end

local function test_start_and_end_delay_pad_the_animation_assumed() -- W57
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group()
    alpha:SetStartDelay(1)
    alpha:SetEndDelay(0.5)
    local log = recorder(animGroup)
    A.eq(animGroup:GetDuration(), 2.5)
    animGroup:Play()
    w:advance(0.75)
    A.eq(alpha:GetProgress(), 0)
    w:advance(0.75)
    A.eq(alpha:GetProgress(), 0.5)
    w:advance(0.75)
    A.same({ alpha:GetProgress(), log }, { 1, { "play" } })
    w:advance(0.5)
    A.same(log, { "play", "fin:false" })
  end)
end

local function test_animation_defaults_match_the_xml_defaults() -- W61 W62 W63
  withWidgets("retail", function()
    local animGroup = _G.CreateFrame("Frame"):CreateAnimationGroup()
    local alpha, move = animGroup:CreateAnimation("Alpha"), animGroup:CreateAnimation("Translation")
    local grow, spin = animGroup:CreateAnimation("Scale"), animGroup:CreateAnimation("Rotation")
    A.same({ alpha:GetFromAlpha(), alpha:GetToAlpha() }, { 0, 1 })
    A.same({ move:GetOffset() }, { 0, 0 })
    A.same({ grow:GetScaleFrom() }, { 1, 1 })
    A.same({ grow:GetScaleTo() }, { 1, 1 })
    A.same({ grow:GetOrigin() }, { "CENTER", 0, 0 })
    A.same({ spin:GetOrigin() }, { "CENTER", 0, 0 })
    A.same({ spin:GetDegrees(), spin:GetRadians() }, { 0, 0 })
  end)
end

local function test_rotation_degrees_and_radians_are_one_angle()
  withWidgets("retail", function()
    local spin = _G.CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Rotation")
    spin:SetDegrees(180)
    A.eq(spin:GetRadians(), math.pi)
    spin:SetRadians(math.pi / 2)
    A.eq(spin:GetDegrees(), 90)
  end)
end

local function test_scale_setters_round_trip()
  withWidgets("retail", function()
    local grow = _G.CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Scale")
    grow:SetScaleFrom(0.5, 2)
    grow:SetScaleTo(3, 4)
    A.same({ grow:GetScaleFrom() }, { 0.5, 2 })
    A.same({ grow:GetScaleTo() }, { 3, 4 })
    grow:SetScale(5, 6)
    A.same({ grow:GetScale() }, { 5, 6 })
    A.same({ grow:GetScaleTo() }, { 5, 6 })
    grow:SetOrigin("TOPLEFT", 1, 2)
    A.same({ grow:GetOrigin() }, { "TOPLEFT", 1, 2 })
  end)
end

local function test_target_defaults_to_the_group_parent()
  withWidgets("retail", function()
    local frame, animGroup, alpha = group()
    local other = _G.CreateFrame("Frame")
    A.eq(alpha:GetTarget(), frame)
    alpha:SetTarget(other)
    A.eq(alpha:GetTarget(), other)
    A.eq(animGroup:GetParent(), frame)
  end)
end

local function test_to_final_alpha_defaults_to_false()
  withWidgets("retail", function()
    local _, animGroup = group()
    A.eq(animGroup:IsSetToFinalAlpha(), false)
    animGroup:SetToFinalAlpha(true)
    A.eq(animGroup:IsSetToFinalAlpha(), true)
  end)
end

return function()
  test_orders_default_to_one_and_durations_to_zero()
  test_orders_sequence_and_equal_orders_overlap_assumed()
  test_orders_run_by_number_not_by_creation_assumed()
  test_negative_durations_and_delays_count_as_zero_assumed()
  test_progress_is_one_after_a_finish_and_zero_after_a_stop_assumed()
  test_elapsed_is_the_seconds_into_the_animation_assumed()
  test_smoothing_defaults_to_none_and_out_in_aliases_in_out()
  test_smoothing_curves_assumed()
  test_start_and_end_delay_pad_the_animation_assumed()
  test_animation_defaults_match_the_xml_defaults()
  test_rotation_degrees_and_radians_are_one_angle()
  test_scale_setters_round_trip()
  test_target_defaults_to_the_group_parent()
  test_to_final_alpha_defaults_to_false()
end
