-- Edit Mode layouts moving a Blizzard-style frame (Task 10.3): the active layout is read at login and again on s:editMode.
-- The mini addons are kit-authored (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local Layout = require("ui.layout")
local Scenario = require("scenario")

local function layout(name, point, x, y)
  local anchor = { point = point, relativeTo = "UIParent", relativePoint = point, offsetX = x, offsetY = y }
  local system = { system = 0, isInDefaultPosition = false, anchorInfo = anchor, settings = {} }
  return { layoutName = name, layoutType = 1, systems = { system } }
end

local LAYOUTS = { layout("A", "BOTTOM", 0, 45), layout("B", "TOPLEFT", 10, -20) }
local TARGETS = { "Blizzard_MiniEditMode" }

local function test_active_layout_places_the_blizzard_frame_assumed()
  local opts = {
    targets = TARGETS,
    before = function(s)
      s.w:setMock({ editMode = { layouts = LAYOUTS, active = 3 } })
    end,
  }
  B.run(B.mini(), opts, function(s)
    -- Layout A: BOTTOM of a 200x40 frame at (0, 45) on a 1000x800 UIParent: left = 500 - 100 = 400, bottom = 45.
    A.same(Layout.rect(s.w, _G.MiniBar), { left = 400, bottom = 45, width = 200, height = 40 })
    s:editMode({ active = 4 })
    -- Layout B: TOPLEFT at (10, -20): left = 10, top = 800 - 20 = 780, bottom = 780 - 40 = 740.
    A.same(Layout.rect(s.w, _G.MiniBar), { left = 10, bottom = 740, width = 200, height = 40 })
  end)
end

local function test_no_layouts_means_no_login_event_assumed()
  local lua =
    'EmLog = 0; local f = CreateFrame("Frame"); f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED"); f:SetScript("OnEvent", function() EmLog = EmLog + 1 end)'
  B.run(B.mini(), { targets = TARGETS, lua = lua }, function(s)
    A.eq(_G.EmLog, 0)
    A.same(Layout.rect(s.w, _G.MiniBar), { left = 400, bottom = 45, width = 200, height = 40 })
  end)
end

local function test_login_fires_between_player_login_and_entering_world_assumed()
  local lua = [[
OrderLog = {}
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_ENTERING_WORLD" }) do f:RegisterEvent(e) end
f:SetScript("OnEvent", function(_, e) OrderLog[#OrderLog + 1] = e end)
]]
  local opts = {
    lua = lua,
    before = function(s)
      s.w:setMock({ editMode = { layouts = LAYOUTS, active = 3 } })
    end,
  }
  B.run(B.mini(), opts, function()
    A.same(_G.OrderLog, { "PLAYER_LOGIN", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_ENTERING_WORLD" })
  end)
end

local function test_edit_mode_fires_once_with_the_layouts_assumed()
  local lua = [[
EmSeen = {}
local f = CreateFrame("Frame")
f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
f:SetScript("OnEvent", function(_, _, info, reconcile) EmSeen[#EmSeen + 1] = { info.activeLayout, #info.layouts, reconcile } end)
]]
  B.run(B.mini(), { lua = lua }, function(s)
    s:editMode({ layouts = LAYOUTS, active = 4 })
    A.same(_G.EmSeen, { { 4, 2, false } })
  end)
end

local function test_a_patched_layouts_list_replaces_the_old_one_assumed()
  local opts = {
    before = function(s)
      s.w:setMock({ editMode = { layouts = LAYOUTS, active = 3 } })
    end,
  }
  B.run(B.mini(), opts, function(s)
    s:editMode({ layouts = { LAYOUTS[2] } })
    local info = _G.C_EditMode.GetLayouts()
    A.same({ #info.layouts, info.layouts[1].layoutName, info.activeLayout }, { 1, "B", 3 })
  end)
end

local function test_without_the_layer_login_fires_nothing_assumed()
  local lua =
    'EmLog = 0; local f = CreateFrame("Frame"); f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED"); f:SetScript("OnEvent", function() EmLog = EmLog + 1 end)'
  local report = Scenario.matrix({ "retail" }, function(s)
    s.w:setMock({ editMode = { layouts = LAYOUTS, active = 3 } })
    s:login()
    A.eq(_G.EmLog, 0)
  end, { addon = "Probe", root = B.probe(lua) }).retail
  A.eq(report.status, "pass")
end

return function()
  test_active_layout_places_the_blizzard_frame_assumed()
  test_no_layouts_means_no_login_event_assumed()
  test_login_fires_between_player_login_and_entering_world_assumed()
  test_edit_mode_fires_once_with_the_layouts_assumed()
  test_a_patched_layouts_list_replaces_the_old_one_assumed()
  test_without_the_layer_login_fires_nothing_assumed()
end
