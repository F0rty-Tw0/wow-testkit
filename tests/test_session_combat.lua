-- Session combat: the viewer's combat toolbar over sess:call (preset, pull, kill, step, play, pause, roster), the combat
-- log as text lines (combatlog, combat_log_text.lua) and the host's combatlog event, on the CombatDemo session.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.session")

local COMBAT_DEMO = H.DEMO:gsub("SessionDemo$", "CombatDemo")
local DAMAGE_LINE = "^%[%d+%.%d%] .+ hits .+ for %d+$"

local function withDemo(fn)
  H.withSession({ addonDir = COMBAT_DEMO }, fn)
end

local function combat(sess, req)
  return sess:call("combat", req)
end

local function dungeon(sess)
  local reply = combat(sess, { action = "preset", name = "dungeon" })
  A.eq(reply.ok, true, reply.error)
end

local function test_preset_over_the_session_builds_the_group()
  withDemo(function(sess)
    local seq = sess.seq
    dungeon(sess)
    A.eq(_G.GetNumGroupMembers(), 5)
    A.eq(sess.seq, seq + 1)
    local snap = sess:call("snapshot")
    for i = 1, 5 do
      A.truthy(H.item(snap, "CombatDemoMember" .. i), "CombatDemoMember" .. i)
    end
  end)
end

local function test_step_advances_the_clock_and_fills_the_log()
  withDemo(function(sess)
    dungeon(sess)
    A.eq(combat(sess, { action = "pull" }).ok, true)
    local seq = sess.seq
    local reply = combat(sess, { action = "step", seconds = 3 })
    A.same({ reply.ok, reply.time, reply.inCombat }, { true, 3, true })
    A.eq(sess.seq, seq + 1)
    local lines = sess:call("combatlog", { since = 0 }).lines
    A.truthy(#lines > 0, "no log lines")
    local damage
    for i, line in ipairs(lines) do
      A.eq(line.seq, lines[1].seq + i - 1)
      A.truthy(i == 1 or line.t >= lines[i - 1].t, "t went back at line " .. i)
      damage = damage or (line.text:match(DAMAGE_LINE) and line)
    end
    A.truthy(damage, "no damage line in " .. lines[#lines].text)
  end)
end

local function test_combatlog_since_returns_only_newer_lines()
  withDemo(function(sess)
    dungeon(sess)
    combat(sess, { action = "pull" })
    combat(sess, { action = "step", seconds = 3 })
    local all = sess:call("combatlog", { since = 0 }).lines
    local newer = sess:call("combatlog", { since = all[2].seq }).lines
    A.same({ #newer, newer[1].seq }, { #all - 2, all[3].seq })
  end)
end

local function test_pull_without_a_target_engages_every_hostile()
  withDemo(function(sess)
    dungeon(sess)
    A.eq(combat(sess, { action = "pull" }).inCombat, true)
    for _, enemy in ipairs(sess.w.combat.preset.enemies) do
      A.eq(enemy.affectingCombat, true, enemy.name)
    end
  end)
end

local function test_kill_kills_the_named_unit()
  withDemo(function(sess)
    dungeon(sess)
    local seq = sess.seq
    A.eq(combat(sess, { action = "kill", target = "boss1" }).ok, true)
    A.eq(Actors.get(sess.w, "boss1").isDead, true)
    A.eq(sess.seq, seq + 1)
  end)
end

-- A trash mob has no unit token, so the viewer kills by the GUID the reply lists; the dead leave the list.
local function test_kill_by_guid_from_the_enemies_list()
  withDemo(function(sess)
    dungeon(sess)
    local enemies = combat(sess, { action = "roster" }).enemies
    A.same({ #enemies, enemies[1].name, enemies[5].name }, { 5, "Kit Trash 1", "Kit Boss" })
    local reply = combat(sess, { action = "kill", target = enemies[1].guid })
    A.eq(Actors.get(sess.w, enemies[1].guid).isDead, true)
    A.same({ #reply.enemies, reply.enemies[1].name }, { 4, "Kit Trash 2" })
  end)
end

local function test_pause_stops_stepping_and_bad_speed_is_refused()
  withDemo(function(sess)
    local seq = sess.seq
    local reply = combat(sess, { action = "play", speed = 4 })
    A.same({ reply.ok, reply.playing, reply.speed }, { true, true, 4 })
    reply = combat(sess, { action = "play", speed = 3 })
    A.eq(reply.ok, false)
    A.contains(reply.error, "0.25, 0.5, 1, 2, 4 or 8")
    reply = combat(sess, { action = "pause" })
    A.same({ reply.ok, reply.playing, reply.speed }, { true, false, 4 })
    A.eq(sess.seq, seq)
  end)
end

local function test_bad_requests_are_refused()
  withDemo(function(sess)
    local seq = sess.seq
    A.contains(combat(sess, { action = "dance" }).error, "unknown action 'dance'")
    A.contains(combat(sess, { action = "step", seconds = 0 }).error, "seconds")
    A.contains(combat(sess, { action = "step", seconds = 61 }).error, "seconds")
    A.contains(combat(sess, { action = "kill" }).error, "target")
    A.contains(combat(sess, { action = "preset", name = "arena" }).error, "unknown preset 'arena'")
    A.eq(sess.seq, seq)
  end)
end

local function test_roster_lists_the_flavors_classes_and_races()
  withDemo(function(sess)
    local reply = combat(sess, { action = "roster" })
    A.same({ reply.ok, reply.time, reply.playing, reply.speed }, { true, 0, false, 1 })
    A.same(reply.classes[1], { file = "WARRIOR", name = "Warrior" })
    A.eq(#reply.classes, 13)
    A.same({ reply.races.Alliance[1], reply.races.Horde[1] }, { "Human", "Orc" })
    A.eq(sess.w.combat, nil)
  end)
end

local function test_plates_appear_in_the_snapshot()
  withDemo(function(sess)
    dungeon(sess)
    local snap = sess:call("snapshot")
    local screen = snap.screen
    for i = 1, 5 do
      local item = H.item(snap, "NamePlate" .. i)
      A.truthy(item and item.rect, "NamePlate" .. i)
      local rect = item.rect
      local inside = rect.x >= 0 and rect.y >= 0 and rect.x + rect.width <= screen.width and rect.y + rect.height <= screen.height
      A.truthy(inside, "NamePlate" .. i .. " off screen")
    end
  end)
end

return function()
  test_preset_over_the_session_builds_the_group()
  test_step_advances_the_clock_and_fills_the_log()
  test_combatlog_since_returns_only_newer_lines()
  test_pull_without_a_target_engages_every_hostile()
  test_kill_kills_the_named_unit()
  test_kill_by_guid_from_the_enemies_list()
  test_pause_stops_stepping_and_bad_speed_is_refused()
  test_bad_requests_are_refused()
  test_roster_lists_the_flavors_classes_and_races()
  test_plates_appear_in_the_snapshot()
end
