-- Animation playback in the render snapshot, alpha: the multiplier, the final alpha, stop and pause, and the clock.
-- Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local AG = require("tests.helpers.anim_group")
local H = require("tests.helpers.render")
local S = require("tests.helpers.widget_snap")

local animated, fade = AG.animated, AG.fade

local function test_alpha_animation_multiplies_the_frame_alpha_assumed() -- W61
  H.withRender(function(w)
    local animGroup, animation = animated("Pulse", "Alpha")
    fade(animGroup, animation)
    animGroup:Play()
    w:advance(0.25)
    A.eq(S.snap(w, "Pulse").alpha, 0.75)
    w:advance(0.75)
    A.eq(S.snap(w, "Pulse").alpha, 1)
  end)
end

local function test_alpha_animation_multiplies_the_frame_alpha_chain_assumed() -- W61
  H.withRender(function(w)
    local animGroup, animation, frame = animated("PulseHalf", "Alpha")
    frame:SetAlpha(0.5)
    fade(animGroup, animation)
    animGroup:Play()
    w:advance(0.5)
    A.eq(S.snap(w, "PulseHalf").alpha, 0.25)
  end)
end

local function test_a_fresh_widget_exports_no_animation_fields()
  H.withRender(function(w)
    S.anchored("Frame", "Calm")
    local item = S.snap(w, "Calm")
    A.same(item.rect, { x = 910, y = 515, width = 100, height = 50 })
    A.eq(item.alpha, 1)
    A.eq(item.rotation, nil)
  end)
end

local function test_final_alpha_is_kept_when_requested_assumed() -- W60
  H.withRender(function(w)
    local keep, keepFade = animated("Keeps", "Alpha")
    fade(keep, keepFade)
    keep:SetToFinalAlpha(true)
    local drop, dropFade = animated("Drops", "Alpha")
    fade(drop, dropFade)
    keep:Play()
    drop:Play()
    w:advance(1.5)
    A.same({ S.snap(w, "Keeps").alpha, S.snap(w, "Drops").alpha }, { 0, 1 })
  end)
end

local function test_final_alpha_comes_from_the_last_alpha_animation_assumed() -- W60
  H.withRender(function(w)
    local animGroup, first = animated("Last", "Alpha")
    first:SetOrder(1)
    first:SetToAlpha(0.5)
    local second, third, early = animGroup:CreateAnimation("Alpha"), animGroup:CreateAnimation("Alpha"), animGroup:CreateAnimation("Alpha")
    second:SetOrder(2)
    second:SetToAlpha(0.25)
    third:SetOrder(2)
    third:SetToAlpha(0.75)
    early:SetOrder(1)
    early:SetToAlpha(0.125)
    animGroup:CreateAnimation("Translation"):SetOrder(3)
    animGroup:SetToFinalAlpha(true)
    animGroup:Play()
    w:advance(5)
    A.eq(S.snap(w, "Last").alpha, 0.75)
  end)
end

local function test_stop_drops_the_final_alpha_assumed() -- W60
  H.withRender(function(w)
    local animGroup, animation = animated("Reset", "Alpha")
    fade(animGroup, animation)
    animGroup:SetToFinalAlpha(true)
    animGroup:Play()
    w:advance(1.5)
    animGroup:Stop()
    A.eq(S.snap(w, "Reset").alpha, 1)
  end)
end

local function test_stop_removes_the_effect_and_replay_restarts_it_assumed() -- W61
  H.withRender(function(w)
    local animGroup, animation = animated("Again", "Alpha")
    fade(animGroup, animation)
    animGroup:Play()
    w:advance(0.5)
    animGroup:Stop()
    A.eq(S.snap(w, "Again").alpha, 1)
    animGroup:Play()
    w:advance(0.25)
    A.eq(S.snap(w, "Again").alpha, 0.75)
  end)
end

local function test_pause_holds_the_effect_assumed() -- W65
  H.withRender(function(w)
    local animGroup, animation = animated("Held", "Alpha")
    fade(animGroup, animation)
    animGroup:Play()
    w:advance(0.25)
    animGroup:Pause()
    w:advance(3)
    A.eq(S.snap(w, "Held").alpha, 0.75)
  end)
end

local function test_smoothing_bends_the_alpha_animation_assumed() -- W64
  H.withRender(function(w)
    local animGroup, animation = animated("Eased", "Alpha")
    fade(animGroup, animation)
    animation:SetSmoothing("IN")
    animGroup:Play()
    w:advance(0.5)
    A.eq(S.snap(w, "Eased").alpha, 0.75)
  end)
end

local function test_alpha_animations_of_two_groups_multiply_assumed() -- W61
  H.withRender(function(w)
    local first, firstFade, frame = animated("Twice", "Alpha")
    fade(first, firstFade)
    local second = frame:CreateAnimationGroup()
    local secondFade = second:CreateAnimation("Alpha")
    secondFade:SetFromAlpha(1)
    secondFade:SetToAlpha(0)
    secondFade:SetDuration(2)
    first:Play()
    second:Play()
    w:advance(0.5)
    A.eq(S.snap(w, "Twice").alpha, 0.5 * 0.75)
  end)
end

local function test_target_picks_the_animated_widget_assumed() -- W61
  H.withRender(function(w)
    local animGroup, animation = animated("Owner", "Alpha")
    S.anchored("Frame", "Aimed")
    fade(animGroup, animation)
    animation:SetTarget(_G.Aimed)
    animGroup:Play()
    w:advance(0.5)
    A.same({ S.snap(w, "Owner").alpha, S.snap(w, "Aimed").alpha }, { 1, 0.5 })
  end)
end

local function test_children_inherit_the_alpha_animation_assumed() -- W61
  H.withRender(function(w)
    local animGroup, animation, frame = animated("Parent", "Alpha")
    fade(animGroup, animation)
    local tex = frame:CreateTexture("ParentTex")
    tex:SetAllPoints()
    animGroup:Play()
    w:advance(0.5)
    A.eq(S.snap(w, "ParentTex").alpha, 0.5)
  end)
end

local function test_ignore_parent_alpha_stops_the_inherited_animation_assumed() -- W61
  H.withRender(function(w)
    local animGroup, animation, frame = animated("Fader", "Alpha")
    fade(animGroup, animation)
    local tex = frame:CreateTexture("FaderTex")
    tex:SetAllPoints()
    tex:SetIgnoreParentAlpha(true)
    animGroup:Play()
    w:advance(0.5)
    A.eq(S.snap(w, "FaderTex").alpha, 1)
  end)
end

local function test_a_snapshot_does_not_advance_the_clock()
  H.withRender(function(w)
    local animGroup, animation = animated("Still", "Alpha")
    fade(animGroup, animation)
    animGroup:Play()
    w:advance(0.25)
    local before = w.now
    local first, second = S.snap(w, "Still").alpha, S.snap(w, "Still").alpha
    A.same({ first, second, w.now }, { 0.75, 0.75, before })
  end)
end

return function()
  test_alpha_animation_multiplies_the_frame_alpha_assumed()
  test_alpha_animation_multiplies_the_frame_alpha_chain_assumed()
  test_a_fresh_widget_exports_no_animation_fields()
  test_final_alpha_is_kept_when_requested_assumed()
  test_final_alpha_comes_from_the_last_alpha_animation_assumed()
  test_stop_drops_the_final_alpha_assumed()
  test_stop_removes_the_effect_and_replay_restarts_it_assumed()
  test_pause_holds_the_effect_assumed()
  test_smoothing_bends_the_alpha_animation_assumed()
  test_alpha_animations_of_two_groups_multiply_assumed()
  test_target_picks_the_animated_widget_assumed()
  test_children_inherit_the_alpha_animation_assumed()
  test_ignore_parent_alpha_stops_the_inherited_animation_assumed()
  test_a_snapshot_does_not_advance_the_clock()
end
