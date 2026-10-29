-- AnimationGroup playback: Play, Stop, Finish, Pause and the group scripts. The state is st.group (ui/anim.lua); the
-- boundary of the current pass (its end, or the end of a loop) is one timer on the world clock, cancelled by Stop,
-- Finish and Pause and scheduled again by Play, so nothing polls. Methods register through Typed.add for
-- "animationgroup", so M.methods stays empty; they are fn(w, obj, st, ...) like ui/behaviour.lua. Rule tags W<n> name rows of
-- docs/client-sources.md `## Widgets`.
local M = {}

local Anim = require("ui.anim")
local AnimEffects = require("ui.anim_effects")
local Typed = require("ui.typed")

M.methods = {}

local PLAYING, PAUSED, DONE, STOPPED = Anim.PLAYING, Anim.PAUSED, Anim.DONE, Anim.STOPPED

local function running(gs)
  return gs ~= nil and (gs.state == PLAYING or gs.state == PAUSED)
end

local function cancelTimer(gs)
  if gs.timer then
    gs.timer:Cancel()
    gs.timer = nil
  end
end

local onBoundary

-- Schedules the end of the current pass: after the timeline's length, or after the loop's when the group repeats.
local function schedule(w, group, st)
  local gs = st.group
  local total = Anim.timeline(w, group).total
  local looped = Anim.looping(st) ~= "NONE"
  local due = gs.startedAt + (looped and gs.loops + 1 or 1) * total
  gs.timer = w:schedule(due - w.now, function()
    onBoundary(w, group, st)
  end, 1)
end

-- source: W65 `IsDone` is true only after a finish, false after Stop; W59 OnFinished(group, requested) at the natural
-- end (false) and on Finish (true). The state and a kept final alpha (W60) are set before the script runs, so the script
-- may Play again and reads the final alpha.
local function finish(w, group, st, requested)
  cancelTimer(st.group)
  st.group.state = DONE
  st.group.pendingFinish = false
  AnimEffects.deactivate(w, group)
  if Anim.value(st, "ToFinalAlpha") then
    AnimEffects.keepFinalAlpha(w, group)
  end
  w:callScript(group, "OnFinished", requested)
end

-- source: W59 OnLoop(group, loopState), loopState the state the group is transitioning to; assumed: FORWARD on a
-- REPEAT, REVERSE on every odd pass of a BOUNCE.
function onBoundary(w, group, st)
  local gs = st.group
  gs.timer = nil
  local looping = Anim.looping(st)
  if looping == "NONE" or gs.pendingFinish or Anim.timeline(w, group).total <= 0 then
    return finish(w, group, st, gs.pendingFinish)
  end
  gs.loops = gs.loops + 1
  schedule(w, group, st)
  local reverse = looping == "BOUNCE" and gs.loops % 2 == 1
  w:callScript(group, "OnLoop", reverse and "REVERSE" or "FORWARD")
end

-- source: assumed (W65) Play on a paused group resumes it without OnPlay; Play on a playing group does nothing.
local function resume(w, group, st)
  local gs = st.group
  gs.startedAt = gs.startedAt + (w.now - gs.pausedAt)
  gs.pausedAt = nil
  gs.state = PLAYING
  schedule(w, group, st)
end

local function play(w, group, st)
  local gs = st.group
  if gs and gs.state == PLAYING then
    return
  end
  if gs and gs.state == PAUSED then
    return resume(w, group, st)
  end
  st.group = { state = PLAYING, startedAt = w.now, loops = 0, pendingFinish = false }
  AnimEffects.activate(w, group)
  schedule(w, group, st)
  w:callScript(group, "OnPlay")
end

local function pause(w, group, st)
  local gs = st.group
  if not (gs and gs.state == PLAYING) then
    return
  end
  cancelTimer(gs)
  gs.pausedAt = w.now
  gs.state = PAUSED
  w:callScript(group, "OnPause")
end

-- source: W59 OnStop on Stop(); assumed: Stop does not fire OnFinished, a Stop on a group that is not running fires
-- nothing, and a Stop on a finished group clears the state silently (a kept final alpha is the target's own by then).
local function stop(w, group, st)
  local gs = st.group
  if not gs then
    return
  end
  local wasRunning = running(gs)
  cancelTimer(gs)
  gs.state = STOPPED
  gs.pendingFinish = false
  AnimEffects.deactivate(w, group)
  if wasRunning then
    w:callScript(group, "OnStop")
  end
end

-- source: W59 wiki UIOBJECT_AnimationGroup "Finish: Notifies the animationgroup to stop playing once the current loop
-- cycle is done." A looping group that is playing finishes at the end of its pass; assumed: any other running group
-- finishes at once.
local function requestFinish(w, group, st)
  local gs = st.group
  if not running(gs) then
    return
  end
  local waits = gs.state == PLAYING and Anim.looping(st) ~= "NONE" and Anim.timeline(w, group).total > 0
  if waits then
    gs.pendingFinish = true
    return
  end
  finish(w, group, st, true)
end

local function stateIs(...)
  local names = { ... }

  return function(_, _, st)
    local state = st.group and st.group.state
    for _, name in ipairs(names) do
      if state == name then
        return true
      end
    end

    return false
  end
end

Typed.add("Play", "animationgroup", play)
Typed.add("Pause", "animationgroup", pause)
Typed.add("Stop", "animationgroup", stop)
Typed.add("Finish", "animationgroup", requestFinish)
Typed.add("IsPlaying", "animationgroup", stateIs(PLAYING))
Typed.add("IsPaused", "animationgroup", stateIs(PAUSED))
Typed.add("IsDone", "animationgroup", stateIs(DONE))
Typed.add("IsPendingFinish", "animationgroup", function(_, _, st)
  return st.group ~= nil and st.group.pendingFinish == true
end)
Typed.add("GetDuration", "animationgroup", function(w, group)
  return Anim.timeline(w, group).total
end)
Typed.add("GetLooping", "animationgroup", function(_, _, st)
  return Anim.value(st, "Looping")
end)
Typed.add("IsSetToFinalAlpha", "animationgroup", function(_, _, st)
  return Anim.value(st, "ToFinalAlpha")
end)

return M
