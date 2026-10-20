-- AnimationGroup:CreateAnimation and :GetAnimations.
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets

local function test_create_animation_returns_an_animation_of_the_requested_type()
  withWidgets("retail", function()
    local group = _G.CreateFrame("Frame"):CreateAnimationGroup()
    local fadeIn = group:CreateAnimation("Alpha")
    A.eq(fadeIn:GetObjectType(), "Alpha")
    A.eq(fadeIn:IsObjectType("Animation"), true)
    A.eq(fadeIn:GetParent(), group)
    -- every method PulseGlow.lua:50-54 calls
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(0.8)
    fadeIn:SetDuration(0.5)
    fadeIn:SetEndDelay(0.1)
    fadeIn:SetOrder(1)
    A.eq(fadeIn:GetDuration(), 0.5)
    A.eq(fadeIn:GetFromAlpha(), 0)
  end)
end

local function test_create_animation_matches_the_type_case_insensitively_for_every_animation_type()
  withWidgets("retail", function()
    local group = _G.CreateFrame("Frame"):CreateAnimationGroup()
    for _, typeName in ipairs({ "Alpha", "Translation", "Scale", "Rotation", "Path", "FlipBook" }) do
      A.eq(group:CreateAnimation(typeName:lower()):GetObjectType(), typeName)
    end
  end)
end

local function test_get_animations_lists_them_in_creation_order()
  withWidgets("retail", function()
    local group = _G.CreateFrame("Frame"):CreateAnimationGroup()
    local first, second = group:CreateAnimation("Alpha"), group:CreateAnimation("Translation", "SlideUp")
    -- A.same compares widgets by pairs (empty tables), so it cannot see order: compare identities.
    local a, b = group:GetAnimations()
    A.eq(a, first)
    A.eq(b, second)
    A.eq(select("#", group:GetAnimations()), 2)
    A.eq(_G.SlideUp, second)
    A.eq(select("#", _G.CreateFrame("Frame"):CreateAnimationGroup():GetAnimations()), 0)
  end)
end

local function test_create_animation_rejects_an_unknown_or_non_animation_type()
  withWidgets("retail", function()
    local group = _G.CreateFrame("Frame"):CreateAnimationGroup()
    A.errors(function()
      group:CreateAnimation("Bogus")
    end, "unknown animation type 'Bogus' on retail")
    A.errors(function()
      group:CreateAnimation("Frame")
    end, "unknown animation type 'Frame' on retail")
  end)
end

local function test_unknown_animation_type_error_names_the_caller_line()
  withWidgets("retail", function()
    local group = _G.CreateFrame("Frame"):CreateAnimationGroup()
    local line
    local ok, err = pcall(function()
      line = debug.getinfo(1, "l").currentline + 1
      group:CreateAnimation("Bogus")
    end)
    A.eq(ok, false)
    local where = "test_behaviour_animation%.lua:" .. line .. ": "
    A.truthy(tostring(err):find(where .. "CreateAnimation: unknown animation type"), tostring(err))
  end)
end

local function test_create_animation_is_not_counted_as_unscripted()
  withWidgets("retail", function(w)
    local group = _G.CreateFrame("Frame"):CreateAnimationGroup()
    group:CreateAnimation("Alpha")
    group:GetAnimations()
    A.eq(w.unscripted["AnimationGroup:CreateAnimation"], nil)
    A.eq(w.unscripted["AnimationGroup:GetAnimations"], nil)
  end)
end

return function()
  test_create_animation_returns_an_animation_of_the_requested_type()
  test_create_animation_matches_the_type_case_insensitively_for_every_animation_type()
  test_get_animations_lists_them_in_creation_order()
  test_create_animation_rejects_an_unknown_or_non_animation_type()
  test_unknown_animation_type_error_names_the_caller_line()
  test_create_animation_is_not_counted_as_unscripted()
end
