-- Scenario combat steps: s:pull, s:combat and s:kill.
local A = require("assert")
local Actors = require("combat_actors")
local Combat = require("combat")
local Group = require("combat_group")
local H = require("tests.helpers.combat")
local Log = require("combat_log")
local Threat = require("combat_threat")

-- Combat installed, Ann in the player's party, Brute (boss1) with a swing rule and threat on Ann.
local function setup(w)
  local c = Combat.install(w)
  local ann, brute = H.pair(w)
  Group.set(w, { Actors.get(w, "player"), ann })
  brute.ai = { swing = { every = 2, damage = 100 } }
  Threat.add(w, brute, ann, 10)
  return c, ann, brute
end

local function test_pull_engages_and_starts_combat()
  H.withScenario("retail", function(w, s)
    local c, ann, brute = setup(w)
    local log = H.watch(w, { "PLAYER_REGEN_DISABLED" })
    s:pull("boss1")
    A.same({ #log, _G.InCombatLockdown(), ann.affectingCombat, brute.affectingCombat }, { 1, true, true, true })
    s:advance(2)
    A.same({ c.log.entries[1][2], c.log.entries[1][8], ann.health }, { "SWING_DAMAGE", ann.guid, 900 })
  end)
end

local function test_pull_a_new_enemy_from_a_spec()
  H.withScenario("retail", function(w, s)
    s:pull({ name = "Gob", token = "boss1", health = 300, ai = { swing = { every = 1, damage = 5 } } })
    local gob = Actors.get(w, "boss1")
    A.same({ gob.name, gob.isEnemy, gob.healthMax, _G.InCombatLockdown() }, { "Gob", true, 300, true })
    s:advance(1)
    A.same({ _G.UnitHealth("player"), w.combat.log.entries[1][8] }, { 95, Actors.get(w, "player").guid })
  end)
end

local function test_combat_timeline_runs_on_advance()
  H.withScenario("retail", function(w, s)
    local c, ann = setup(w)
    local t0 = Log.timestamp(w)
    s:combat({
      { at = 1, damage = { from = "boss1", to = "party1", amount = 10 } },
      { at = 3, damage = { from = "boss1", to = "party1", amount = 30 } },
    })
    A.eq(#c.log.entries, 0)
    s:advance(1)
    A.same({ #c.log.entries, c.log.entries[1][1] - t0 }, { 1, 1 })
    s:advance(2)
    A.same({ #c.log.entries, c.log.entries[2][1] - t0, ann.health }, { 2, 3, 960 })
  end)
end

local function test_kill_step_ends_combat_after_the_delay()
  H.withScenario("retail", function(w, s)
    setup(w)
    s:pull("boss1")
    local log = H.watch(w, { "PLAYER_REGEN_ENABLED" })
    s:kill("boss1")
    A.same({ Actors.get(w, "boss1").isDead, _G.UnitIsDead("boss1") }, { true, true })
    s:advance(4)
    A.eq(#log, 0)
    s:advance(1)
    A.same({ #log, _G.InCombatLockdown() }, { 1, false })
  end)
end

local function test_unknown_token_raises_at_the_call_site()
  H.withScenario("retail", function(w, s)
    setup(w)
    A.errors(function()
      s:kill("nobody")
    end, "s:kill")
    A.errors(function()
      s:pull("nobody")
    end, "s:pull")
    A.errors(function()
      s:combat({ { at = 1, kill = "nobody" } })
    end, "s:combat")
    A.errors(function()
      s:pull("party1")
    end, "not hostile")
  end)
end

local function test_addon_error_in_a_handler_does_not_stop_the_timeline()
  H.withScenario("retail", function(w, s)
    local _, ann = setup(w)
    local thrown = false
    local frame = _G.CreateFrame("Frame")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:SetScript("OnEvent", function()
      if not thrown then
        thrown = true
        error("boom")
      end
    end)
    s:combat({
      { at = 1, damage = { from = "boss1", to = "party1", amount = 10 } },
      { at = 2, damage = { from = "boss1", to = "party1", amount = 20 } },
    })
    s:advance(2)
    A.same({ #w.errors, ann.health }, { 1, 970 })
  end)
end

return function()
  test_pull_engages_and_starts_combat()
  test_pull_a_new_enemy_from_a_spec()
  test_combat_timeline_runs_on_advance()
  test_kill_step_ends_combat_after_the_delay()
  test_unknown_token_raises_at_the_call_site()
  test_addon_error_in_a_handler_does_not_stop_the_timeline()
end
