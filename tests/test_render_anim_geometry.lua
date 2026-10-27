-- Animation playback in the render snapshot, geometry: translation, scale and rotation show through the item's rect
-- and rotation. Rule tags W<n> name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local AG = require("tests.helpers.anim_group")
local H = require("tests.helpers.render")
local S = require("tests.helpers.widget_snap")

local animated = AG.animated

local function test_translation_moves_the_rect_and_children_follow_assumed() -- W62
  H.withRender(function(w)
    local animGroup, animation, frame = animated("Slide", "Translation")
    animation:SetOffset(100, 50)
    local tex = frame:CreateTexture("SlideTex")
    tex:SetAllPoints()
    animGroup:Play()
    w:advance(0.5)
    A.same(S.snap(w, "Slide").rect, { x = 960, y = 490, width = 100, height = 50 })
    A.same(S.snap(w, "SlideTex").rect, { x = 960, y = 490, width = 100, height = 50 })
    w:advance(0.5)
    A.same(S.snap(w, "Slide").rect, { x = 910, y = 515, width = 100, height = 50 })
  end)
end

local function test_a_finished_translation_returns_to_the_anchor_assumed() -- W62
  H.withRender(function(w)
    local animGroup, animation = animated("Back", "Translation")
    animation:SetOffset(100, 50)
    animGroup:SetToFinalAlpha(true)
    animGroup:Play()
    w:advance(2)
    A.same(S.snap(w, "Back").rect, { x = 910, y = 515, width = 100, height = 50 })
  end)
end

local function test_scale_animation_scales_about_the_centre_assumed() -- W63
  H.withRender(function(w)
    local animGroup, animation = animated("Grow", "Scale")
    animation:SetScaleFrom(1, 1)
    animation:SetScaleTo(2, 2)
    animGroup:Play()
    w:advance(0.5)
    A.same(S.snap(w, "Grow").rect, { x = 885, y = 502.5, width = 150, height = 75 })
  end)
end

local function test_scale_origin_moves_the_pivot_assumed() -- W63
  H.withRender(function(w)
    local animGroup, animation = animated("Corner", "Scale")
    animation:SetScaleTo(2, 2)
    animation:SetOrigin("TOPLEFT", 0, 0)
    animGroup:Play()
    w:advance(0.5)
    A.same(S.snap(w, "Corner").rect, { x = 910, y = 515, width = 150, height = 75 })
  end)
end

local function test_scale_origin_offsets_shift_the_pivot_assumed() -- W63
  H.withRender(function(w)
    local animGroup, animation = animated("Offset", "Scale")
    animation:SetScaleTo(2, 2)
    animation:SetOrigin("BOTTOMRIGHT", 10, 4)
    animGroup:Play()
    w:advance(0.5)
    -- pivot (1010 + 10, 565 - 4); the rect grows 1.5 times about it
    A.same(S.snap(w, "Offset").rect, { x = 1020 + (910 - 1020) * 1.5, y = 561 + (515 - 561) * 1.5, width = 150, height = 75 })
  end)
end

local function test_scale_does_not_resize_the_children_assumed() -- W63
  H.withRender(function(w)
    local animGroup, animation, frame = animated("Big", "Scale")
    animation:SetScaleTo(2, 2)
    local tex = frame:CreateTexture("BigTex")
    tex:SetAllPoints()
    animGroup:Play()
    w:advance(0.5)
    A.same(S.snap(w, "BigTex").rect, { x = 910, y = 515, width = 100, height = 50 })
  end)
end

local function test_texture_rotation_is_exported_and_frames_do_not_rotate_assumed() -- W63
  H.withRender(function(w)
    local animGroup, animation, frame = animated("Spin", "Rotation")
    animation:SetRadians(math.pi)
    local tex = frame:CreateTexture("SpinTex")
    tex:SetAllPoints()
    animGroup:Play()
    w:advance(0.5)
    A.eq(S.snap(w, "Spin").rotation, nil)
    A.eq(S.snap(w, "SpinTex").rotation, nil)
    local texGroup = tex:CreateAnimationGroup()
    local texSpin = texGroup:CreateAnimation("Rotation")
    texSpin:SetRadians(math.pi)
    texSpin:SetDuration(1)
    tex:SetRotation(0.25)
    texGroup:Play()
    w:advance(0.5)
    A.eq(S.snap(w, "SpinTex").rotation, 0.25 + math.pi / 2)
  end)
end

local function test_rotation_animations_on_one_texture_add_up_assumed() -- W63
  H.withRender(function(w)
    local host = S.anchored("Frame", "Twirl")
    local tex = host:CreateTexture("TwirlTex")
    tex:SetAllPoints()
    local animGroup = tex:CreateAnimationGroup()
    for _, radians in ipairs({ 1, 2 }) do
      local spin = animGroup:CreateAnimation("Rotation")
      spin:SetRadians(radians)
      spin:SetDuration(1)
    end
    animGroup:Play()
    w:advance(0.5)
    A.eq(S.snap(w, "TwirlTex").rotation, 1.5)
  end)
end

return function()
  test_translation_moves_the_rect_and_children_follow_assumed()
  test_a_finished_translation_returns_to_the_anchor_assumed()
  test_scale_animation_scales_about_the_centre_assumed()
  test_scale_origin_moves_the_pivot_assumed()
  test_scale_origin_offsets_shift_the_pivot_assumed()
  test_scale_does_not_resize_the_children_assumed()
  test_texture_rotation_is_exported_and_frames_do_not_rotate_assumed()
  test_rotation_animations_on_one_texture_add_up_assumed()
end
