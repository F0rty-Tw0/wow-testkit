-- Screen and UI scale model: ui/screen.lua, w.screen, UIParent and WorldFrame sizes, the screen getters.
local A = require("assert")
local H = require("tests.helpers.world")
local HF = require("tests.helpers.framexml")
local Layout = require("ui.layout")
local World = require("world")

local SCALED = { screen = { width = 1920, height = 1080, useUiScale = true, uiScale = 0.5 } }

local function test_world_new_defaults_the_physical_screen_to_1920_by_1080_assumed() -- (LY8)
  H.withWorld("retail", function(w)
    A.same(w.screen, { width = 1920, height = 1080, useUiScale = false, uiScale = 1 })
  end)
end

local function test_world_new_stores_the_screen_option()
  H.withWorld("retail", function(w)
    A.eq(w.screen.width, 2560)
    A.eq(w.screen.height, 1440)
  end, { screen = { width = 2560, height = 1440 } })
end

local function test_world_new_rejects_a_non_positive_screen_size_and_leaves_no_world()
  A.errors(function()
    World.new({ flavor = "retail", screen = { width = 0, height = 1080 } })
  end, "screen.width")
  H.withWorld("retail", function() end) -- would raise "another world is active" if the failed call leaked one
end

local function test_default_ui_parent_is_the_physical_size_at_scale_one_assumed() -- (LY8)
  HF.withFrameXML("retail", function()
    A.same({ _G.UIParent:GetSize() }, { 1920, 1080 })
    A.eq(_G.UIParent:GetEffectiveScale(), 1)
    A.eq(_G.GetScreenWidth(), 1920)
    A.eq(_G.GetScreenHeight(), 1080)
    A.same({ _G.GetPhysicalScreenSize() }, { 1920, 1080 })
  end)
end

local function test_ui_scale_grows_the_ui_size_and_shrinks_the_effective_scale() -- (LY8)
  HF.withFrameXML("retail", function(w)
    -- 1920 / 0.5 = 3840 and 1080 / 0.5 = 2160 UI units; 3840 * 0.5 = 1920 pixels
    A.eq(_G.UIParent:GetEffectiveScale(), 0.5)
    A.same({ _G.UIParent:GetSize() }, { 3840, 2160 })
    A.eq(_G.GetScreenWidth(), 3840)
    A.eq(_G.GetScreenHeight(), 2160)
    A.same({ _G.GetPhysicalScreenSize() }, { 1920, 1080 })
    A.same(Layout.rect(w, _G.UIParent), { left = 0, bottom = 0, width = 3840, height = 2160 })
    A.same(Layout.pixelRect(w, _G.UIParent), { left = 0, bottom = 0, right = 1920, top = 1080 })
  end, SCALED)
end

local function test_ui_scale_is_ignored_while_use_ui_scale_is_off_assumed() -- (LY8)
  HF.withFrameXML("retail", function()
    A.eq(_G.UIParent:GetEffectiveScale(), 1)
    A.eq(_G.GetScreenWidth(), 1920)
  end, { screen = { width = 1920, height = 1080, useUiScale = false, uiScale = 0.5 } })
end

local function test_world_frame_is_the_physical_size_at_scale_one()
  HF.withFrameXML("retail", function()
    A.same({ _G.WorldFrame:GetSize() }, { 1920, 1080 })
    A.eq(_G.WorldFrame:GetEffectiveScale(), 1)
  end, SCALED)
end

local function test_a_ui_parent_child_gets_the_ui_scale() -- (LY7)
  HF.withFrameXML("retail", function(w)
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    f:SetSize(100, 50)
    f:SetPoint("BOTTOMLEFT", 10, 20)
    -- scale 0.5: pixels = (10 * 0.5, 20 * 0.5) = (5, 10), size (50, 25) -> (5..55, 10..35)
    A.same(Layout.pixelRect(w, f), { left = 5, bottom = 10, right = 55, top = 35 })
    A.same(Layout.rect(w, f), { left = 10, bottom = 20, width = 100, height = 50 })
  end, SCALED)
end

local function test_screen_functions_exist_on_every_flavor()
  for _, flavor in ipairs({ "vanilla", "tbc", "mists", "retail", "forever" }) do
    HF.withFrameXML(flavor, function()
      A.eq(_G.GetScreenWidth(), 1920, flavor)
      A.same({ _G.GetPhysicalScreenSize() }, { 1920, 1080 }, flavor)
    end)
  end
end

return function()
  test_world_new_defaults_the_physical_screen_to_1920_by_1080_assumed()
  test_world_new_stores_the_screen_option()
  test_world_new_rejects_a_non_positive_screen_size_and_leaves_no_world()
  test_default_ui_parent_is_the_physical_size_at_scale_one_assumed()
  test_ui_scale_grows_the_ui_size_and_shrinks_the_effective_scale()
  test_ui_scale_is_ignored_while_use_ui_scale_is_off_assumed()
  test_world_frame_is_the_physical_size_at_scale_one()
  test_a_ui_parent_child_gets_the_ui_scale()
  test_screen_functions_exist_on_every_flavor()
end
