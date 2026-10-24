-- The MotLike fixture (MouseOverTooltip's minimap-button geometry) under scn_motlike_preview.lua, rendered at 1920x1080,
-- UI scale 1. y = 1080 - (bottom + height), origin top-left.
local A = require("assert")
local H = require("tests.helpers.render")
local Render = require("render")
local Scenario = require("scenario")

local TEST_DIR = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local MOTLIKE_ROOT = TEST_DIR .. "/fixtures/addons/MotLike"
local SCENARIO_FILE = TEST_DIR .. "/fixtures/scenarios/scn_motlike_preview.lua"
local SCREEN = { width = 1920, height = 1080 }

-- Runs the scenario's run on MotLike, then reads the render snapshot and the tooltip's line count before the world
-- is destroyed.
local function snapshotAndLines()
  local file = assert(loadfile(SCENARIO_FILE))()
  local snap, lines
  local report = Scenario.matrix({ "retail" }, function(s)
    file.run(s)
    snap = Render.snapshot(s.w)
    lines = _G.GameTooltip:NumLines()
  end, { addon = "MotLike", root = MOTLIKE_ROOT, screen = SCREEN }).retail
  A.eq(report.status, "pass")
  return snap, lines
end

-- UIParent is the whole screen.
-- Minimap 140x140 CENTER of UIParent: x = 960 - 70 = 890; bottom = 540 - 70 = 470, top = 610, y = 1080 - 610 = 470.
local function test_ui_parent_and_minimap_rects()
  local snap = snapshotAndLines()
  A.same(H.rect(snap, "UIParent"), { x = 0, y = 0, width = 1920, height = 1080 })
  A.same(H.rect(snap, "Minimap"), { x = 890, y = 470, width = 140, height = 140 })
end

-- Radius = 140 / 2 + 5 = 75, angle 0: offset (75 * cos 0, 75 * sin 0) = (75, 0). Button centre = (960 + 75, 540) =
-- (1035, 540); 31x31: x = 1035 - 15.5 = 1019.5, bottom = 540 - 15.5 = 524.5, top = 555.5, y = 1080 - 555.5 = 524.5.
local function test_button_sits_on_the_ring_right_of_the_minimap()
  local snap = snapshotAndLines()
  A.same(H.rect(snap, "MotLikeMinimapButton"), { x = 1019.5, y = 524.5, width = 31, height = 31 })
end

-- BACKGROUND 20x20 CENTER: x = 1035 - 10 = 1025; top = 540 + 10 = 550, y = 530.
-- ARTWORK 18x18 CENTER: x = 1035 - 9 = 1026; top = 540 + 9 = 549, y = 531.
-- OVERLAY 53x53 TOPLEFT to the button's TOPLEFT: x = 1019.5; top = 555.5, y = 1080 - 555.5 = 524.5.
local function test_textures_sit_on_the_button()
  local snap = snapshotAndLines()
  A.same(H.rect(snap, "MotLikeBg"), { x = 1025, y = 530, width = 20, height = 20 })
  A.same(H.rect(snap, "MotLikeArt"), { x = 1026, y = 531, width = 18, height = 18 })
  A.same(H.rect(snap, "MotLikeBorder"), { x = 1019.5, y = 524.5, width = 53, height = 53 })
end

local function test_button_draws_before_its_regions_in_layer_order()
  local snap = snapshotAndLines()
  A.same(H.names(snap, "MotLike"), { "MotLikeMinimapButton", "MotLikeBg", "MotLikeArt", "MotLikeBorder" })
end

-- Shim tooltip, N lines: 220 x (20 + 14 N), BOTTOMRIGHT of UIParent + (-13, 64): right = 1920 - 13 = 1907,
-- x = 1907 - 220 = 1687; bottom = 64, top = 64 + height, y = 1080 - 64 - height = 1016 - height.
local function test_tooltip_sits_bottom_right_with_the_shim_size()
  local snap, lines = snapshotAndLines()
  local height = 20 + 14 * lines
  A.truthy(lines > 0, "the hover put lines on the tooltip")
  A.same(H.rect(snap, "GameTooltip"), { x = 1687, y = 1016 - height, width = 220, height = height })
end

return function()
  test_ui_parent_and_minimap_rects()
  test_button_sits_on_the_ring_right_of_the_minimap()
  test_textures_sit_on_the_button()
  test_button_draws_before_its_regions_in_layer_order()
  test_tooltip_sits_bottom_right_with_the_shim_size()
end
