local A = require("assert")
local Resolve = require("combat_resolve")
local SH = require("tests.helpers.sim_combat")
local SimTarget = require("sim_target")

local function test_target_and_clear_fire_one_event_per_change()
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w, _, player)
      local foe = SH.foe(w, 0, 10)
      local log = SH.record(w, { "PLAYER_TARGET_CHANGED" })
      A.same({ SimTarget.target(w, foe), SimTarget.target(w, foe) }, { true, false })
      A.same({ _G.UnitGUID("target"), player.targetGuid, #log }, { foe.guid, foe.guid, 1 }, flavor)
      _G.ClearTarget()
      A.same({ _G.UnitExists("target"), #log }, { false, 2 }, flavor)
    end)
  end
end

local function test_hover_binds_mouseover_and_fires_on_change_only()
  SH.withSim("retail", function(w)
    local foe = SH.foe(w, 0, 10)
    local log = SH.record(w, { "UPDATE_MOUSEOVER_UNIT" })
    A.same({ SimTarget.hover(w, foe), SimTarget.hover(w, foe) }, { true, false })
    A.same({ _G.UnitGUID("mouseover"), #log }, { foe.guid, 1 })
    _G.TargetUnit("mouseover")
    A.eq(_G.UnitGUID("target"), foe.guid)
    SimTarget.hover(w, nil)
    A.same({ _G.UnitExists("mouseover"), #log }, { false, 2 })
  end)
end

-- Player (0,-10) faces north; reduced distance = centre distance - 3.
local function test_tab_picks_nearest_in_front_then_cycles()
  SH.withSim("retail", function(w, s)
    local far, near = SH.foe(w, 0, 5), SH.foe(w, 0, 0)
    SH.foe(w, 0, -30) -- behind
    SH.foe(w, 0, 45) -- centre 55 -> 52: beyond 40
    SH.foe(w, 0, -4, { hostile = false })
    Resolve.kill(w, SH.foe(w, 0, -6)) -- corpse
    for _, expected in ipairs({ near, far, near }) do
      s:key("TAB", "down")
      s:key("TAB", "up")
      A.eq(_G.UnitGUID("target"), expected.guid)
    end
  end)
end

local function test_tab_with_only_a_rear_foe_changes_nothing()
  SH.withSim("retail", function(w, s)
    SH.foe(w, 0, -30)
    local log = SH.record(w, { "PLAYER_TARGET_CHANGED" })
    s:key("TAB", "down")
    s:key("TAB", "up")
    A.same({ _G.UnitExists("target"), #log }, { false, 0 })
  end)
end

-- Spec 5.1 right-click table; loot range 5 reduced: a corpse at y=-2 (centre 8) is in, y=-1.9 is out.
local function test_right_click_rules()
  SH.withSim("retail", function(w)
    local calls = {}
    w.sim.actions.attack = function(_, a)
      calls[#calls + 1] = "attack:" .. a.name
    end
    w.sim.actions.loot = function(_, a)
      calls[#calls + 1] = "loot:" .. a.name
    end
    local hostile = SH.foe(w, 0, 10, { name = "Hostile" })
    local friend = SH.foe(w, 0, 0, { name = "Friend", hostile = false })
    SimTarget.interact(w, hostile, "RightButton")
    SimTarget.interact(w, friend, "RightButton")
    A.same({ calls, _G.UnitGUID("target") }, { { "attack:Hostile" }, friend.guid })
    local near, edge, bare = SH.foe(w, 0, -2, { name = "Near" }), SH.foe(w, 0, -1.9, { name = "Edge" }), SH.foe(w, 0, -3)
    for _, c in ipairs({ near, edge, bare }) do
      Resolve.kill(w, c)
      c.lootable = c ~= bare
    end
    local errors = SH.record(w, { "UI_ERROR_MESSAGE" })
    SimTarget.interact(w, near, "RightButton")
    A.same({ calls[2], #errors }, { "loot:Near", 0 })
    SimTarget.interact(w, edge, "RightButton")
    A.same({ #calls, #errors, errors[1][4], _G.UnitGUID("target") }, { 2, 1, _G.ERR_LOOT_TOO_FAR, edge.guid })
    SimTarget.interact(w, bare, "RightButton")
    A.same({ #calls, #errors, _G.UnitGUID("target") }, { 2, 1, bare.guid })
  end)
end

local function test_left_click_targets_without_acting()
  SH.withSim("retail", function(w)
    local calls = 0
    w.sim.actions.attack = function()
      calls = calls + 1
    end
    local foe = SH.foe(w, 0, 10)
    SimTarget.interact(w, foe)
    A.same({ _G.UnitGUID("target"), calls }, { foe.guid, 0 })
  end)
end

local function test_ui_error_carries_the_string_and_the_error_type()
  SH.withSim("retail", function(w)
    local log = SH.record(w, { "UI_ERROR_MESSAGE" })
    SimTarget.uiError(w, "ERR_LOOT_TOO_FAR")
    A.same({ log[1][3], log[1][4], type(_G.ERR_LOOT_TOO_FAR) }, { 0, _G.ERR_LOOT_TOO_FAR, "string" })
    w:set("LE_GAME_ERR_LOOT_TOO_FAR", 77)
    SimTarget.uiError(w, "ERR_LOOT_TOO_FAR")
    A.eq(log[2][3], 77)
  end)
end

local function test_pointer_click_on_ground_or_unknown_guid_clears_the_target()
  SH.withSim("retail", function(w)
    local foe = SH.foe(w, 0, 10)
    local ground = { ground = { x = 1, y = 2 } }
    for _, world in ipairs({ ground, { guid = "Creature-0-0-0-0-0-0" } }) do
      SimTarget.target(w, foe)
      A.same({ SimTarget.pointer(w, "click", world, "LeftButton"), _G.UnitExists("target") }, { true, false })
    end
    SimTarget.target(w, foe)
    A.same({ SimTarget.pointer(w, "click", ground, "RightButton"), _G.UnitGUID("target") }, { false, foe.guid })
    A.same({ SimTarget.pointer(w, "click", nil, "LeftButton"), _G.UnitGUID("target") }, { false, foe.guid })
  end)
end

local function test_click_unit_needs_a_sim_world()
  local Scenario = require("scenario")
  local s = Scenario.new({ addon = "T", root = "T", flavor = "retail" })
  A.errors(function()
    s:clickUnit({})
  end, "s:clickUnit: needs Scenario.new{sim=...}")
  A.errors(function()
    s:clickGround(0, 0)
  end, "needs Scenario.new{sim=...}")
  s.w:destroy()
end

local function test_click_unit_and_ground_drive_the_pointer()
  SH.withSim("retail", function(w, s)
    local foe = SH.foe(w, 0, 10)
    s:clickUnit(foe)
    A.eq(_G.UnitGUID("target"), foe.guid)
    s:clickGround(3, 4)
    A.eq(_G.UnitExists("target"), false)
  end)
end

return function()
  test_target_and_clear_fire_one_event_per_change()
  test_hover_binds_mouseover_and_fires_on_change_only()
  test_tab_picks_nearest_in_front_then_cycles()
  test_tab_with_only_a_rear_foe_changes_nothing()
  test_right_click_rules()
  test_left_click_targets_without_acting()
  test_ui_error_carries_the_string_and_the_error_type()
  test_pointer_click_on_ground_or_unknown_guid_clears_the_target()
  test_click_unit_needs_a_sim_world()
  test_click_unit_and_ground_drive_the_pointer()
end
