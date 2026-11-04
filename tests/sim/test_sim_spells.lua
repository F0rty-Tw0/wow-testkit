-- SimSpells: the cast pipeline (checks in order, instant and timed casts, interrupts), cooldowns and the GCD. Every record is
-- a kit literal (tests/helpers/sim_spells.lua); no extract is read. test_sim_spells_state.lua has the fakes, the seams, a
-- reset and a reload.
local A = require("assert")
local Actors = require("combat_actors")
local Auras = require("combat_auras")
local SH = require("tests.helpers.sim_combat")
local SP = require("tests.helpers.sim_spells")
local SimSpellData = require("sim_spell_data")
local SimSpells = require("sim_spells")

local KIT, OTHER, STUN = 900001, 900002, 900004

local function target(w, player, x, y)
  local foe = SH.foe(w, x or 0, y or 10)
  Actors.setTarget(w, player, foe)

  return foe
end

local function count(log, event)
  local n = 0
  for _, entry in ipairs(log) do
    if entry.event == event then
      n = n + 1
    end
  end

  return n
end

-- Casts spell id and asserts the failure name, one UI error carrying the client string, one FAILED and no cooldown.
local function failsWith(w, player, id, name, flavor)
  local log = SH.record(w, { "UNIT_SPELLCAST_FAILED", "UI_ERROR_MESSAGE", "UNIT_SPELLCAST_SUCCEEDED" })
  local ok, err = SimSpells.cast(w, player, id)
  A.same({ ok, err }, { false, name }, flavor)
  A.same(
    { count(log, "UI_ERROR_MESSAGE"), count(log, "UNIT_SPELLCAST_FAILED"), count(log, "UNIT_SPELLCAST_SUCCEEDED") },
    { 1, 1, 0 },
    flavor .. " " .. name
  )
  A.eq(log[1].event, "UI_ERROR_MESSAGE", flavor)
  A.same({ type(_G[name]), log[1][4] }, { "string", _G[name] }, flavor .. " " .. name .. ": the client string")
  A.same({ SimSpells.cooldown(w, id) }, { 0, 0 }, flavor .. " " .. name .. ": no cooldown")
end

local function test_instant_cast_sets_cooldown_and_gcd()
  for _, flavor in ipairs(SP.FLAVORS) do
    SP.withSpells(flavor, { SP.record({ cooldown = 10000, gcd = 1500 }) }, function(w, s, player)
      target(w, player)
      local log = SH.record(w, { "UNIT_SPELLCAST_SUCCEEDED", "ACTIONBAR_UPDATE_COOLDOWN", "UNIT_SPELLCAST_START" })
      A.eq(SimSpells.cast(w, player, KIT), true)
      A.same({ log[1].event, log[2].event, count(log, "UNIT_SPELLCAST_START") }, { "UNIT_SPELLCAST_SUCCEEDED", "ACTIONBAR_UPDATE_COOLDOWN", 0 })
      local info = _G.C_Spell.GetSpellCooldown(KIT)
      A.same({ info.startTime, info.duration, info.isEnabled }, { w.now, 10, true })
      A.same({ SimSpells.cooldown(w, KIT) }, { w.now, 10 })
      local ok, err = SimSpells.cast(w, player, KIT)
      A.same({ ok, err }, { false, "SPELL_FAILED_NOT_READY" })
      s:simStep(10.1)
      A.eq(SimSpells.cast(w, player, KIT), true, flavor .. ": ready again")
    end)
  end
end

local function test_timed_cast_runs_the_cast_bar()
  for _, flavor in ipairs(SP.FLAVORS) do
    SP.withSpells(flavor, { SP.record({ castTime = 2500, cooldown = 6000 }) }, function(w, s, player)
      target(w, player)
      local log = SH.record(w, { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "ACTIONBAR_UPDATE_COOLDOWN" })
      A.eq(SimSpells.cast(w, player, KIT), true)
      A.same({ log[1].event, #log }, { "UNIT_SPELLCAST_START", 1 }, flavor)
      A.eq(select(9, _G.UnitCastingInfo("player")), KIT, flavor)
      A.same({ player.casting.spellID, player.casting.endTime - player.casting.start }, { KIT, 2.5 }, flavor)
      s:simStep(2.4)
      A.same({ count(log, "UNIT_SPELLCAST_SUCCEEDED"), (SimSpells.cooldown(w, KIT)) }, { 0, 0 }, flavor .. ": not before 2.4")
      s:simStep(0.1)
      A.eq(count(log, "UNIT_SPELLCAST_SUCCEEDED"), 1, flavor)
      A.same({ player.casting, player.cast }, { nil, nil }, flavor)
      local began, lasts = SimSpells.cooldown(w, KIT)
      A.same({ began > w.now - 0.01 and began <= w.now, lasts }, { true, 6 }, flavor .. ": the cooldown starts at the end")
    end)
  end
end

local function test_each_failure_names_itself_once()
  for _, flavor in ipairs(SP.FLAVORS) do
    local recs = { SP.record(), SP.record({ id = OTHER, name = "Kit Near", minRange = 8 }), SP.record({ id = 900003, castTime = 2000 }) }
    SP.withSpells(flavor, recs, function(w, s, player)
      failsWith(w, player, KIT, "SPELL_FAILED_BAD_IMPLICIT_TARGETS", flavor)
      failsWith(w, player, 424242, "SPELL_FAILED_NOT_READY", flavor)
      local foe = target(w, player, 0, 60)
      failsWith(w, player, KIT, "SPELL_FAILED_OUT_OF_RANGE", flavor)
      Actors.setPos(w, foe, 0, -2)
      failsWith(w, player, OTHER, "SPELL_FAILED_TOO_CLOSE", flavor)
      Actors.setPos(w, foe, 0, -30)
      failsWith(w, player, KIT, "SPELL_FAILED_UNIT_NOT_INFRONT", flavor)
      Actors.setPos(w, foe, 0, 10)
      s:key("W", "down")
      s:simStep(0.1)
      failsWith(w, player, 900003, "SPELL_FAILED_MOVING", flavor)
      A.eq(SimSpells.cast(w, player, KIT), true, flavor .. ": an instant spell casts on the move")
      s:key("W", "up")
      A.eq(SimSpells.cast(w, player, 900003), true)
      failsWith(w, player, 900003, "SPELL_FAILED_SPELL_IN_PROGRESS", flavor)
    end)
  end
end

local function test_a_spell_off_the_spellbook_is_not_ready()
  SP.withSpells("retail", { SP.record() }, function(w, _, player)
    target(w, player)
    w.mock.spells[KIT].known = false
    failsWith(w, player, KIT, "SPELL_FAILED_NOT_READY", "retail")
  end)
end

local function test_stun_and_power_fail_by_name()
  local recs = {
    SP.record({ id = OTHER, cost = { type = "RAGE", amount = 10 } }),
    SP.record({ id = 900003, cost = { type = "MANA", amount = 30 } }),
  }
  SP.withSpells("retail", recs, function(w, _, player)
    target(w, player)
    failsWith(w, player, OTHER, "ERR_OUT_OF_RAGE", "warrior")
    failsWith(w, player, 900003, "ERR_OUT_OF_MANA", "warrior")
    Auras.apply(w, player, { spellID = STUN, duration = 5, stun = true, harmful = true })
    failsWith(w, player, OTHER, "SPELL_FAILED_STUNNED", "stunned before power")
  end)
  SP.withSpells("retail", recs, function(w, _, player)
    Actors.setPower(w, player, 40)
    A.eq(SimSpells.cast(w, player, OTHER), false, "enough rage still needs a target")
    failsWith(w, player, 900003, "ERR_OUT_OF_MANA", "a warrior has no mana")
  end)
end

local function test_checks_run_in_the_documented_order()
  local recs = { SP.record({ cooldown = 5000, cost = { type = "RAGE", amount = 10 } }) }
  SP.withSpells("retail", recs, function(w, _, player)
    local rec = SimSpellData.get(w, KIT)
    A.eq(SimSpells.check(w, player, rec, nil), "ERR_OUT_OF_RAGE", "power is checked before the target")
    Actors.setPower(w, player, 50)
    local foe = SH.foe(w, 0, 60)
    A.eq(SimSpells.check(w, player, rec, foe), "SPELL_FAILED_OUT_OF_RANGE")
    local friend = SH.foe(w, 0, 60, { hostile = false })
    A.eq(SimSpells.check(w, player, rec, friend), "SPELL_FAILED_BAD_IMPLICIT_TARGETS", "the target is checked before the range")
    Actors.setPos(w, foe, 0, -30)
    A.eq(SimSpells.check(w, player, rec, foe), "SPELL_FAILED_UNIT_NOT_INFRONT")
    A.eq(SimSpells.cast(w, player, KIT, SH.foe(w, 0, 10)), true)
    A.eq(SimSpells.check(w, player, rec, foe), "SPELL_FAILED_NOT_READY", "cooldown is checked before everything else")
  end)
end

local function test_moving_or_a_stun_interrupts_a_timed_cast()
  for _, kind in ipairs({ "move", "stun" }) do
    SP.withSpells(
      "retail",
      { SP.record({ castTime = 2500, cooldown = 9000, gcd = 1500 }), SP.record({ id = OTHER, gcd = 1500 }) },
      function(w, s, player)
        target(w, player)
        local log = SH.record(w, { "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" })
        A.eq(SimSpells.cast(w, player, KIT), true)
        s:simStep(0.5)
        if kind == "move" then
          s:key("W", "down")
        else
          Auras.apply(w, player, { spellID = STUN, duration = 5, stun = true, harmful = true })
        end
        s:simStep(0.1)
        A.same({ count(log, "UNIT_SPELLCAST_INTERRUPTED"), count(log, "UNIT_SPELLCAST_SUCCEEDED") }, { 1, 0 }, kind)
        A.same({ player.cast, player.casting, (SimSpells.cooldown(w, KIT)) }, { nil, nil, 0 }, kind)
        s:key("W", "up")
        s:simStep(3)
        A.same({ count(log, "UNIT_SPELLCAST_SUCCEEDED"), (SimSpells.cooldown(w, KIT)) }, { 0, 0 }, kind .. ": the dropped timer does nothing")
      end
    )
  end
end

local function test_an_interrupted_cast_gives_back_the_gcd()
  SP.withSpells("retail", { SP.record({ castTime = 2500, gcd = 1500 }), SP.record({ id = OTHER, gcd = 1500 }) }, function(w, s, player)
    target(w, player)
    A.eq(SimSpells.cast(w, player, KIT), true)
    local ok, err = SimSpells.cast(w, player, OTHER)
    A.same({ ok, err }, { false, "SPELL_FAILED_NOT_READY" }, "the GCD runs while the bar fills")
    A.eq(SimSpells.stop(w, player), true)
    A.eq(SimSpells.cast(w, player, OTHER), true, "an interrupted cast leaves no GCD")
    A.eq(SimSpells.stop(w, player), false)
    s:simStep(0.1)
  end)
end

local function test_an_interrupted_cast_takes_the_gcd_off_the_cooldown_readers()
  SP.withSpells("retail", { SP.record({ castTime = 2500, gcd = 1500 }) }, function(w, _s, player)
    target(w, player)
    local log = SH.record(w, { "SPELL_UPDATE_COOLDOWN" })
    SimSpells.cast(w, player, KIT)
    A.eq(_G.C_Spell.GetSpellCooldown(KIT).duration, 1.5, "the bar shows the GCD while it fills")
    local before = #log
    SimSpells.stop(w, player)
    A.same({ _G.C_Spell.GetSpellCooldown(KIT).duration, #log > before }, { 0, true })
  end)
end

local function test_gcd_blocks_spells_that_have_one()
  SP.withSpells(
    "retail",
    { SP.record({ gcd = 1500 }), SP.record({ id = OTHER, gcd = 1500 }), SP.record({ id = 900003, gcd = 0 }) },
    function(w, s, player)
      target(w, player)
      A.eq(SimSpells.cast(w, player, KIT), true)
      local ok, err = SimSpells.cast(w, player, OTHER)
      A.same({ ok, err }, { false, "SPELL_FAILED_NOT_READY" })
      A.eq(SimSpells.cast(w, player, 900003), true, "a spell with no GCD casts at once")
      s:simStep(1.4)
      A.eq(SimSpells.cast(w, player, OTHER), false)
      s:simStep(0.2)
      A.eq(SimSpells.cast(w, player, OTHER), true)
    end
  )
end

return function()
  test_instant_cast_sets_cooldown_and_gcd()
  test_timed_cast_runs_the_cast_bar()
  test_each_failure_names_itself_once()
  test_a_spell_off_the_spellbook_is_not_ready()
  test_stun_and_power_fail_by_name()
  test_checks_run_in_the_documented_order()
  test_moving_or_a_stun_interrupts_a_timed_cast()
  test_an_interrupted_cast_gives_back_the_gcd()
  test_an_interrupted_cast_takes_the_gcd_off_the_cooldown_readers()
  test_gcd_blocks_spells_that_have_one()
end
