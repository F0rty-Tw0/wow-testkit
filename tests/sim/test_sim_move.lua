-- Sim movement: intents, per-frame integration, the key fakes, Sim.step's clock and the shown-frame OnUpdate walk.
local A = require("assert")
local H = require("tests.helpers.sim")
local Sim = require("sim")
local SimMove = require("sim_move")

local function test_forward_walks_north_at_run_speed_assumed()
  H.each({}, function(_, s)
    local p = s.w.sim.player
    s:move({ forward = true })
    s:simStep(1)
    H.near(p.pos.y, -3)
    H.near(p.pos.x, 0)
    A.eq(_G.IsPlayerMoving(), true)
    local current, run = _G.GetUnitSpeed("player")
    A.same({ current, run }, { 7, 7 })
  end)
end

local function test_moving_events_fire_on_transitions_only_assumed()
  H.withSim("retail", {}, function(_, s)
    local seen = H.recordMoves()
    s:move({ forward = true })
    s:simStep(0.5)
    s:simStep(0.5)
    A.same(seen, { "PLAYER_STARTED_MOVING" })
    s:move({})
    s:simStep(0.1)
    A.same(seen, { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" })
    A.eq(_G.IsPlayerMoving(), false)
    A.same({ _G.GetUnitSpeed("player") }, { 0, 7, 7, 4.722222 })
  end)
end

local function test_turning_alone_is_not_moving_assumed()
  H.each({}, function(_, s)
    local p = s.w.sim.player
    local seen = H.recordMoves()
    s:move({ turnLeft = true })
    local changed = s:simStep(0.5)
    H.near(_G.GetPlayerFacing(), math.pi / 2)
    A.same({ p.pos.x, p.pos.y }, { 0, -10 })
    A.eq(changed, true)
    A.same(seen, {})
  end)
end

local function test_turn_right_wraps_to_the_circle()
  H.withSim("retail", {}, function(_, s)
    s:move({ turnRight = true })
    s:simStep(0.5)
    H.near(_G.GetPlayerFacing(), 2 * math.pi - math.pi / 2)
  end)
end

local function test_diagonal_is_normalized()
  H.withSim("retail", {}, function(_, s)
    local p = s.w.sim.player
    s:move({ forward = true, strafeRight = true })
    s:simStep(1)
    H.near(p.pos.x, 4.9497474683)
    H.near(p.pos.y, -5.0502525317)
  end)
end

local function test_strafe_left_goes_west()
  H.withSim("retail", {}, function(_, s)
    s:move({ strafeLeft = true })
    s:simStep(1)
    H.near(s.w.sim.player.pos.x, -7)
  end)
end

local function test_backward_and_walk_speeds_assumed()
  H.withSim("retail", {}, function(_, s)
    local p = s.w.sim.player
    s:move({ backward = true })
    s:simStep(1)
    H.near(p.pos.y, -14.5)
    A.eq((_G.GetUnitSpeed("player")), 4.5)
    s:move({})
    s:place(0, -10)
    _G.ToggleRun()
    s:move({ forward = true })
    s:simStep(1)
    H.near(p.pos.y, -7.5)
    A.eq((_G.GetUnitSpeed("player")), 2.5)
  end)
end

local function test_forward_and_backward_cancel_assumed()
  H.withSim("retail", {}, function(_, s)
    s:move({ forward = true, backward = true })
    s:simStep(1)
    H.near(s.w.sim.player.pos.y, -10)
    A.eq(_G.IsPlayerMoving(), false)
  end)
end

local function test_face_turns_the_forward_vector()
  H.withSim("retail", {}, function(_, s)
    local p = s.w.sim.player
    s:face(math.pi / 2)
    s:move({ forward = true })
    s:simStep(1)
    H.near(p.pos.x, -7)
    H.near(p.pos.y, -10)
  end)
end

local function test_place_and_walls_clamp()
  H.withSim("retail", {}, function(_, s)
    local p = s.w.sim.player
    s:place(0, 49)
    s:move({ forward = true })
    s:simStep(2)
    A.eq(p.pos.y, 50)
    s:place(99, 0)
    A.same({ p.pos.x, p.pos.y }, { 50, 0 })
  end)
end

local function test_key_fakes_drive_the_intents_assumed()
  H.withSim("retail", {}, function(_, s)
    local p = s.w.sim.player
    _G.MoveForwardStart()
    s:simStep(1)
    H.near(p.pos.y, -3)
    _G.MoveForwardStop()
    s:simStep(1)
    H.near(p.pos.y, -3)
    _G.ToggleAutoRun()
    s:simStep(0.5)
    H.near(p.pos.y, 0.5)
    _G.MoveBackwardStart()
    A.eq(s.w.sim.intents.autorun, nil)
    _G.MoveBackwardStop()
    _G.TurnLeftStart()
    _G.TurnLeftStop()
    _G.TurnRightStart()
    _G.TurnRightStop()
    _G.StrafeLeftStart()
    _G.StrafeLeftStop()
    _G.StrafeRightStart()
    A.eq(s.w.sim.intents.strafeRight, true)
    _G.StrafeRightStop()
    A.same(s.w.sim.intents, {})
  end)
end

local function test_unknown_intent_raises()
  H.withSim("retail", {}, function(w)
    A.errors(function()
      SimMove.intent(w, "fly", true)
    end, "unknown intent 'fly'; valid:")
  end)
end

local function test_other_units_do_not_move()
  H.withSim("retail", {}, function(_, s)
    s:move({ forward = true })
    s:simStep(0.1)
    A.same({ _G.GetUnitSpeed("target") }, { 0, 7, 7, 4.722222 })
  end)
end

local function test_step_time_and_carry()
  H.each({}, function(w, s)
    local fired = false
    _G.C_Timer.After(0.05, function()
      fired = true
    end)
    local t0 = _G.GetTime()
    s:simStep(0.1)
    H.near(_G.GetTime() - t0, 0.1)
    A.eq(fired, true)
    s:simStep(0.033)
    s:simStep(0.033)
    A.eq(w.sim.clock.carry < 1 / 60, true)
  end)
end

local function test_step_rejects_a_bad_duration()
  H.withSim("retail", {}, function(w)
    A.errors(function()
      Sim.step(w, -1)
    end, "seconds")
    A.errors(function()
      Sim.step(w, "1")
    end, "seconds")
  end)
end

local function test_idle_step_changes_nothing()
  H.withSim("retail", {}, function(_, s)
    local changed, updates = s:simStep(0.1)
    A.same({ changed, updates }, { false, 0 })
  end)
end

local function test_on_update_walks_shown_frames_in_order_assumed()
  H.each({}, function(_, s)
    local calls = {}
    local function track(name)
      return function(_, elapsed)
        calls[#calls + 1] = { name, elapsed }
      end
    end
    local f1 = _G.CreateFrame("Frame", nil, _G.UIParent)
    local f2 = _G.CreateFrame("Frame", nil, f1)
    local hidden = _G.CreateFrame("Frame", nil, _G.UIParent)
    local under = _G.CreateFrame("Frame", nil, hidden)
    local hooked = _G.CreateFrame("Frame", nil, _G.UIParent)
    f1:SetScript("OnUpdate", track("f1"))
    f2:SetScript("OnUpdate", track("f2"))
    hidden:SetScript("OnUpdate", track("hidden"))
    under:SetScript("OnUpdate", track("under"))
    hooked:HookScript("OnUpdate", track("hooked"))
    hidden:Hide()
    local changed, updates = s:simStep(0.1)
    A.same(calls, { { "f1", 0.1 }, { "f2", 0.1 }, { "hooked", 0.1 } })
    A.same({ changed, updates }, { true, 3 })
  end)
end

local function test_advance_is_guarded_on_a_sim_world()
  H.withSim("retail", {}, function(_, s)
    A.errors(function()
      s:advance(1)
    end, "sim clock owns time")
  end)
end

local function test_transmog_opener_does_not_trip_the_guard()
  H.withSim("retail", {}, function(_, s)
    s:openWindow("transmog", {})
    A.eq(_G.C_Transmog.IsAtTransmogNPC(), true)
  end)
end

return function()
  test_forward_walks_north_at_run_speed_assumed()
  test_moving_events_fire_on_transitions_only_assumed()
  test_turning_alone_is_not_moving_assumed()
  test_turn_right_wraps_to_the_circle()
  test_diagonal_is_normalized()
  test_strafe_left_goes_west()
  test_backward_and_walk_speeds_assumed()
  test_forward_and_backward_cancel_assumed()
  test_face_turns_the_forward_vector()
  test_place_and_walls_clamp()
  test_key_fakes_drive_the_intents_assumed()
  test_unknown_intent_raises()
  test_other_units_do_not_move()
  test_step_time_and_carry()
  test_step_rejects_a_bad_duration()
  test_idle_step_changes_nothing()
  test_on_update_walks_shown_frames_in_order_assumed()
  test_advance_is_guarded_on_a_sim_world()
  test_transmog_opener_does_not_trip_the_guard()
end
