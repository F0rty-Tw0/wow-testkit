-- Hand-written alpha, scale, frame level and strata: client defaults and inheritance from parents.
local A = require("assert")
local HW = require("tests.helpers.widgets")

local withWidgets = HW.withWidgets

local function test_fresh_frame_alpha_is_one()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    A.eq(f:GetAlpha(), 1)
    A.eq(w.unscripted["Frame:GetAlpha"], nil)
  end)
end

local function test_alpha_round_trips()
  withWidgets("retail", function()
    local f = _G.CreateFrame("Frame")
    f:SetAlpha(0.5)
    A.eq(f:GetAlpha(), 0.5)
  end)
end

local function test_effective_alpha_multiplies_parent_alphas()
  withWidgets("retail", function()
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, parent)
    A.eq(child:GetEffectiveAlpha(), 1)
    parent:SetAlpha(0.5)
    child:SetAlpha(0.5)
    A.eq(child:GetEffectiveAlpha(), 0.25)
  end)
end

local function test_fresh_frame_scale_is_one()
  withWidgets("retail", function()
    A.eq(_G.CreateFrame("Frame"):GetScale(), 1)
  end)
end

local function test_effective_scale_multiplies_parent_scales()
  withWidgets("retail", function()
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, parent)
    parent:SetScale(2)
    A.eq(child:GetScale(), 1)
    A.eq(child:GetEffectiveScale(), 2)
  end)
end

local function test_frame_level_is_one_above_parent()
  withWidgets("retail", function()
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, parent)
    A.eq(parent:GetFrameLevel(), 0)
    A.eq(child:GetFrameLevel(), 1)
    parent:SetFrameLevel(5)
    A.eq(child:GetFrameLevel(), 6)
    child:SetFrameLevel(2)
    A.eq(child:GetFrameLevel(), 2)
  end)
end

local function test_frame_strata_follows_parent_else_medium()
  withWidgets("retail", function()
    local parent = _G.CreateFrame("Frame")
    local child = _G.CreateFrame("Frame", nil, parent)
    A.eq(child:GetFrameStrata(), "MEDIUM")
    parent:SetFrameStrata("TOOLTIP")
    A.eq(child:GetFrameStrata(), "TOOLTIP")
  end)
end

local function test_unset_flags_are_false()
  withWidgets("retail", function(w)
    local f = _G.CreateFrame("Frame")
    A.eq(f:IsMouseEnabled(), false)
    A.eq(f:IsMouseWheelEnabled(), false)
    A.eq(f:IsMovable(), false)
    A.eq(next(w.unscripted), nil)
  end)
end

return function()
  test_fresh_frame_alpha_is_one()
  test_alpha_round_trips()
  test_effective_alpha_multiplies_parent_alphas()
  test_fresh_frame_scale_is_one()
  test_effective_scale_multiplies_parent_scales()
  test_frame_level_is_one_above_parent()
  test_frame_strata_follows_parent_else_medium()
  test_unset_flags_are_false()
end
