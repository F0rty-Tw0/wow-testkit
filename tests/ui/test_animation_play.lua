-- AnimationGroup playback against the kit clock: Play, Stop, Finish, Pause, the group scripts and loops. Rule tags W<n>
-- name rows of docs/client-sources.md `## Widgets`.
local A = require("assert")
local AG = require("tests.helpers.anim_group")
local HW = require("tests.helpers.widgets")

local group, recorder = AG.group, AG.recorder
local withWidgets = HW.withWidgets

local function test_play_finish_events_and_flags() -- W59 W65
  withWidgets("retail", function(w)
    local _, animGroup = group()
    local log = recorder(animGroup)
    A.same({ animGroup:IsPlaying(), animGroup:IsDone() }, { false, false })
    animGroup:Play()
    A.eq(animGroup:IsPlaying(), true)
    w:advance(0.5)
    A.eq(animGroup:IsPlaying(), true)
    w:advance(0.75)
    A.same({ animGroup:IsPlaying(), animGroup:IsDone(), log }, { false, true, { "play", "fin:false" } })
  end)
end

local function test_play_while_playing_does_nothing_assumed()
  withWidgets("retail", function(w)
    local _, animGroup = group()
    local log = recorder(animGroup)
    animGroup:Play()
    w:advance(0.5)
    animGroup:Play()
    w:advance(0.75)
    A.same(log, { "play", "fin:false" })
  end)
end

local function test_play_restarts_a_finished_group_from_its_own_handler()
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group()
    local plays = 0
    animGroup:SetScript("OnFinished", function(self)
      plays = plays + 1
      if plays < 2 then
        self:Play()
      end
    end)
    animGroup:Play()
    w:advance(1.25)
    A.same({ plays, animGroup:IsPlaying(), alpha:GetProgress() }, { 1, true, 0.25 })
    w:advance(1)
    A.same({ plays, animGroup:IsPlaying(), animGroup:IsDone() }, { 2, false, true })
  end)
end

local function test_finish_waits_for_the_loop_cycle_to_end() -- W59
  withWidgets("retail", function(w)
    local _, animGroup = group("REPEAT")
    local log = recorder(animGroup)
    animGroup:Play()
    w:advance(0.5)
    animGroup:Finish()
    A.same({ animGroup:IsPendingFinish(), animGroup:IsPlaying(), log }, { true, true, { "play" } })
    w:advance(0.75)
    A.same({ animGroup:IsPlaying(), animGroup:IsDone(), animGroup:IsPendingFinish(), log }, { false, true, false, { "play", "fin:true" } })
    w:advance(5)
    A.same(log, { "play", "fin:true" })
  end)
end

local function test_finish_on_a_single_pass_group_ends_it_at_once_assumed() -- W59
  withWidgets("retail", function(w)
    local _, animGroup = group()
    local log = recorder(animGroup)
    animGroup:Play()
    animGroup:Finish()
    A.same({ animGroup:IsDone(), log }, { true, { "play", "fin:true" } })
    w:advance(2)
    A.same(log, { "play", "fin:true" })
  end)
end

local function test_stop_fires_on_stop_and_is_not_done_assumed() -- W59 W65
  withWidgets("retail", function(w)
    local _, animGroup = group()
    local log = recorder(animGroup)
    animGroup:Play()
    w:advance(0.25)
    animGroup:Stop()
    A.same({ animGroup:IsDone(), animGroup:IsPlaying(), animGroup:IsPaused(), log }, { false, false, false, { "play", "stop" } })
    w:advance(2)
    A.same(log, { "play", "stop" })
  end)
end

local function test_stop_without_playing_fires_nothing_assumed()
  withWidgets("retail", function()
    local _, animGroup = group()
    local log = recorder(animGroup)
    animGroup:Stop()
    A.same(log, {})
  end)
end

local function test_stop_on_a_finished_group_is_silent_assumed() -- W59
  withWidgets("retail", function(w)
    local _, animGroup = group()
    animGroup:Play()
    w:advance(2)
    local log = recorder(animGroup)
    animGroup:Stop()
    A.same({ animGroup:IsDone(), log }, { false, {} })
  end)
end

local function test_finish_and_pause_on_a_group_that_is_not_running_do_nothing_assumed() -- W59
  withWidgets("retail", function()
    local _, animGroup = group()
    local log = recorder(animGroup)
    animGroup:Finish()
    animGroup:Pause()
    A.same({ animGroup:IsDone(), animGroup:IsPaused(), animGroup:IsPendingFinish(), log }, { false, false, false, {} })
  end)
end

local function test_finish_on_a_paused_looping_group_ends_it_at_once_assumed() -- W59
  withWidgets("retail", function(w)
    local _, animGroup = group("REPEAT")
    animGroup:Play()
    w:advance(0.5)
    animGroup:Pause()
    local log = recorder(animGroup)
    animGroup:Finish()
    A.same({ animGroup:IsDone(), log }, { true, { "fin:true" } })
  end)
end

local function test_finish_on_a_zero_length_looping_group_ends_it_at_once_assumed() -- W59
  withWidgets("retail", function()
    local animGroup = _G.CreateFrame("Frame"):CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    animGroup:Play()
    animGroup:Finish()
    A.eq(animGroup:IsDone(), true)
  end)
end

local function test_looping_defaults_to_none() -- W58
  withWidgets("retail", function()
    local _, animGroup = group()
    A.eq(animGroup:GetLooping(), "NONE")
    animGroup:SetLooping("BOUNCE")
    A.eq(animGroup:GetLooping(), "BOUNCE")
  end)
end

local function test_an_unknown_looping_plays_once_assumed() -- W58
  withWidgets("retail", function(w)
    local _, animGroup = group("WOBBLE")
    local log = recorder(animGroup)
    animGroup:Play()
    w:advance(1.25)
    A.same(log, { "play", "fin:false" })
  end)
end

local function test_a_loop_boundary_reads_as_the_start_of_the_next_pass_assumed() -- W58
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group("REPEAT")
    alpha:SetDuration(0.3)
    local seen
    animGroup:SetScript("OnLoop", function()
      seen = alpha:GetProgress()
    end)
    animGroup:Play()
    w:advance(0.3)
    A.eq(seen, 0)
  end)
end

local function test_a_zero_length_looping_group_plays_once_assumed() -- W58
  withWidgets("retail", function(w)
    local animGroup = _G.CreateFrame("Frame"):CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    local log = recorder(animGroup)
    animGroup:Play()
    w:advance(0)
    A.same({ animGroup:IsDone(), log, #w.errors }, { true, { "play", "fin:false" }, 0 })
  end)
end

local function test_repeat_loops_restart_the_progress_assumed() -- W58
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group("REPEAT")
    local log = recorder(animGroup)
    animGroup:Play()
    w:advance(1.5)
    A.same({ alpha:GetProgress(), log, animGroup:IsPlaying() }, { 0.5, { "play", "loop:FORWARD" }, true })
    w:advance(1)
    A.same(log, { "play", "loop:FORWARD", "loop:FORWARD" })
  end)
end

local function test_bounce_loops_alternate_direction_assumed() -- W58
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group("BOUNCE")
    local log = recorder(animGroup)
    animGroup:Play()
    w:advance(1.25)
    A.same({ alpha:GetProgress(), log }, { 0.75, { "play", "loop:REVERSE" } })
    w:advance(1)
    A.same({ alpha:GetProgress(), log }, { 0.25, { "play", "loop:REVERSE", "loop:FORWARD" } })
  end)
end

local function test_pause_freezes_progress() -- W65
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group()
    animGroup:Play()
    w:advance(0.5)
    animGroup:Pause()
    A.same({ animGroup:IsPaused(), animGroup:IsPlaying() }, { true, false })
    w:advance(5)
    A.same({ alpha:GetProgress(), animGroup:IsDone() }, { 0.5, false })
  end)
end

local function test_play_resumes_a_paused_group_assumed() -- W65
  withWidgets("retail", function(w)
    local _, animGroup, alpha = group()
    local log = recorder(animGroup)
    animGroup:Play()
    w:advance(0.5)
    animGroup:Pause()
    w:advance(5)
    animGroup:Play()
    A.same({ animGroup:IsPaused(), animGroup:IsPlaying(), log }, { false, true, { "play" } })
    w:advance(0.25)
    A.eq(alpha:GetProgress(), 0.75)
    w:advance(0.25)
    A.same({ animGroup:IsDone(), log }, { true, { "play", "fin:false" } })
  end)
end

local function test_a_failing_script_is_recorded_and_playback_goes_on()
  withWidgets("retail", function(w)
    local _, animGroup = group()
    animGroup:SetScript("OnPlay", function()
      error("boom")
    end)
    animGroup:Play()
    A.eq(#w.errors, 1)
    w:advance(1.5)
    A.same({ animGroup:IsDone(), #w.errors }, { true, 1 })
  end)
end

return function()
  test_play_finish_events_and_flags()
  test_play_while_playing_does_nothing_assumed()
  test_play_restarts_a_finished_group_from_its_own_handler()
  test_finish_waits_for_the_loop_cycle_to_end()
  test_finish_on_a_single_pass_group_ends_it_at_once_assumed()
  test_stop_fires_on_stop_and_is_not_done_assumed()
  test_stop_without_playing_fires_nothing_assumed()
  test_stop_on_a_finished_group_is_silent_assumed()
  test_finish_and_pause_on_a_group_that_is_not_running_do_nothing_assumed()
  test_finish_on_a_paused_looping_group_ends_it_at_once_assumed()
  test_finish_on_a_zero_length_looping_group_ends_it_at_once_assumed()
  test_looping_defaults_to_none()
  test_an_unknown_looping_plays_once_assumed()
  test_a_loop_boundary_reads_as_the_start_of_the_next_pass_assumed()
  test_a_zero_length_looping_group_plays_once_assumed()
  test_repeat_loops_restart_the_progress_assumed()
  test_bounce_loops_alternate_direction_assumed()
  test_pause_freezes_progress()
  test_play_resumes_a_paused_group_assumed()
  test_a_failing_script_is_recorded_and_playback_goes_on()
end
