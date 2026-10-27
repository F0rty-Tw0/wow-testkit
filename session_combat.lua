-- Session combat: the viewer's combat toolbar and log panel. combat runs the Scenario's combat steps (preset, pull, kill)
-- and moves the world clock (step); play and pause only record what the viewer is doing, because the viewer drives play
-- by posting a step every 100 ms. combatlog reads the kit's combat log (c.log) as text lines (combat_log_text.lua).
local M = {}

local Roster = require("combat_roster_data")
local Text = require("combat_log_text")

local SPEEDS = { 0.25, 0.5, 1, 2, 4, 8 }
local SPEED_TEXT = "0.25, 0.5, 1, 2, 4 or 8"
-- A longer step runs every AI timer it covers in one request, so the server would stall on a huge one.
local MAX_STEP = 60

local function fail(fmt, ...)
  error("combat: " .. string.format(fmt, ...), 0)
end

local function isSpeed(value)
  for _, speed in ipairs(SPEEDS) do
    if value == speed then
      return true
    end
  end
  return false
end

local function playState(sess)
  sess.combatPlay = sess.combatPlay or { playing = false, speed = 1 }
  return sess.combatPlay
end

-- Every live hostile actor, in spawn order.
local function enemiesOf(w)
  local out = {}
  local c = w.combat
  for _, guid in ipairs(c and c.order or {}) do
    local actor = c.actors[guid]
    if actor and actor.isEnemy and not actor.isDead then
      out[#out + 1] = actor
    end
  end
  return out
end

-- The reply every action gives: { ok, playing, speed, time, inCombat, enemies = { { guid, name } } }; time counts from
-- Combat.install (0 before). The viewer's Kill target picks from enemies, since a trash mob has no unit token.
local function status(sess)
  local w, play = sess.w, playState(sess)
  local c = w.combat
  local reply = { ok = true, playing = play.playing, speed = play.speed, inCombat = w.mock.combat == true }
  reply.time = c and (w.now - c.t0) or 0
  reply.enemies = {}
  for i, enemy in ipairs(enemiesOf(w)) do
    reply.enemies[i] = { guid = enemy.guid, name = enemy.name }
  end
  return reply
end

-- The flavor's classes ({ file, name }) and race names per faction, for the toolbar's pickers.
local function roster(flavor)
  local classes, races = {}, {}
  for i, file in ipairs(Roster.CLASSES[flavor]) do
    classes[i] = { file = file, name = Roster.CLASS_NAMES[file] }
  end
  for faction, list in pairs(Roster.RACES[flavor]) do
    races[faction] = {}
    for i, race in ipairs(list) do
      races[faction][i] = race.name
    end
  end
  return classes, races
end

-- Each action returns whether it changed the world.
local ACTIONS = {
  preset = function(sess, req)
    if req.opts ~= nil and type(req.opts) ~= "table" then
      fail("opts must be an object")
    end
    sess.s:preset(req.name, req.opts)
    return true
  end,
  -- target: a unit token; without one every unengaged hostile is pulled.
  pull = function(sess, req)
    if req.target ~= nil then
      sess.s:pull(req.target)
      return true
    end
    -- Checked as the loop goes: an enemy an earlier pull engaged is skipped.
    local pulled = false
    for _, enemy in ipairs(enemiesOf(sess.w)) do
      if not enemy.affectingCombat then
        sess.s:pull(enemy)
        pulled = true
      end
    end
    return pulled
  end,
  -- target: a unit token or an actor's GUID.
  kill = function(sess, req)
    if type(req.target) ~= "string" then
      fail("kill needs a target unit token or GUID")
    end
    sess.s:kill(req.target)
    return true
  end,
  step = function(sess, req)
    local seconds = req.seconds
    if type(seconds) ~= "number" or not (seconds > 0 and seconds <= MAX_STEP) then
      fail("seconds must be a number above 0 and at most %d", MAX_STEP)
    end
    sess.s:advance(seconds)
    return true
  end,
  play = function(sess, req)
    if not isSpeed(req.speed) then
      fail("speed must be %s, got %s", SPEED_TEXT, tostring(req.speed))
    end
    local play = playState(sess)
    play.playing, play.speed = true, req.speed
    return false
  end,
  pause = function(sess)
    playState(sess).playing = false
    return false
  end,
  -- A read: the status plus the flavor's classes and races.
  roster = function()
    return false
  end,
}

-- req = { action = "preset", name, opts? } | { action = "pull", target? } | { action = "kill", target }
-- | { action = "step", seconds } | { action = "play", speed } | { action = "pause" } | { action = "roster" }.
-- Replies the status (see status; roster adds classes and races) and whether the world changed. A bad request raises "combat: ...", which Session:call answers as { ok = false, error }.
function M.combat(sess, req)
  local run = ACTIONS[req.action]
  if not run then
    fail("unknown action '%s'; valid: preset, pull, kill, step, play, pause, roster", tostring(req.action))
  end
  local changed = run(sess, req)
  local reply = status(sess)
  if req.action == "roster" then
    reply.classes, reply.races = roster(sess.w.flavor)
  end
  return reply, changed
end

-- req = { since? = 0 }. Replies { ok, lines = { { seq, t, subevent, text } } } for the kept entries newer than since,
-- oldest first; none before the combat world is installed. A read.
function M.log(sess, req)
  local w, since = sess.w, tonumber(req.since) or 0
  local log = w.combat and w.combat.log
  local lines = {}
  for _, entry in ipairs(log and log.entries or {}) do
    if entry.seq > since then
      lines[#lines + 1] = { seq = entry.seq, t = Text.time(w, entry), subevent = entry[2], text = Text.line(w, entry) }
    end
  end
  return { ok = true, lines = lines }, false
end

return M
