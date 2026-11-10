-- SimClasses: the Warrior and Mage kits per flavor group (known spells, action bar, proc rules), the swap on a class change
-- or a reload, an extract's name over the literal, and the kit played through the real flow (UseAction, key, cast).
-- No client extract is read: the one extract is a kit-authored mini one.
local A = require("assert")
local Actors = require("combat_actors")
local Client = require("tests.helpers.client")
local Scenario = require("scenario")
local SH = require("tests.helpers.sim_combat")
local Sim = require("sim")
local SimClasses = require("sim_classes")
local SimMelee = require("sim_melee")
local SimMobs = require("sim_mobs")
local SimSpellData = require("sim_spell_data")
local SP = require("tests.helpers.sim_spells")
local H = require("tests.helpers.session")
local Tmp = require("tests.helpers.tmp")

local GROUP_OF = { retail = "modern", forever = "modern", mists = "classic", tbc = "classic", vanilla = "classic" }
local BARS = {
  WARRIOR = { modern = { 100, 6343, 1464, 6572 }, classic = { 100, 6343, 78, 7384 } },
  MAGE = { modern = { 133, 122, 190356 }, classic = { 133, 122, 10 } },
}
local MODERN_ONLY = { 1464, 6572, 190356 }
local CLASSIC_ONLY = { 78, 7384, 10 }

local function barIds(w)
  local ids = {}
  for slot = 1, 12 do
    local entry = w.mock.actions[slot]
    ids[slot] = type(entry) == "table" and entry.id or nil
  end

  return ids
end

local function test_every_flavor_has_its_group_assumed()
  A.same(SimClasses.FLAVOR_GROUP, GROUP_OF)
end

local function test_each_flavor_knows_its_group_and_bars_it()
  for _, flavor in ipairs(SH.FLAVORS) do
    for class, groups in pairs(BARS) do
      SH.withSim(flavor, function(w)
        local ids = groups[GROUP_OF[flavor]]
        A.same(barIds(w), ids, flavor .. " " .. class)
        for slot, id in ipairs(ids) do
          A.eq(_G.C_Spell.GetSpellInfo(id).name ~= nil, true, flavor .. " " .. id)
          A.eq(w.mock.spells[id].known, true, flavor .. " " .. id)
          A.same({ _G.GetActionInfo(slot) }, { "spell", id, "spell" }, flavor .. " slot " .. slot)
          A.eq(w.mock.actions[slot].texture, SimSpellData.get(w, id).icon, flavor .. " texture " .. id)
        end
      end, { class = class })
    end
  end
end

local function test_an_id_never_crosses_groups()
  for _, flavor in ipairs(SH.FLAVORS) do
    for class in pairs(BARS) do
      SH.withSim(flavor, function(w)
        local foreign = GROUP_OF[flavor] == "modern" and CLASSIC_ONLY or MODERN_ONLY
        for _, id in ipairs(foreign) do
          A.same({ w.mock.spells[id], SimSpellData.get(w, id) }, {}, flavor .. " " .. class .. " " .. id)
        end
      end, { class = class })
    end
  end
end

-- source: assumed (spec 7.4; Task 5.5 rules) the modern Warrior's Revenge! comes after every fourth landed swing and lasts
-- 15 s with its aura; the classic Warrior's Overpower glows 5 s after a dodge, with no aura.
local function test_the_warriors_proc_rule_follows_its_group()
  local want = {
    modern = { { id = "revenge", onEvent = "swing_hit", every = 4, aura = 5302, overlay = 6572, duration = 15000 } },
    classic = { { id = "overpower", onEvent = "dodge", every = 1, overlay = 7384, duration = 5000 } },
  }
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w)
      A.same(w.sim.procRules, want[GROUP_OF[flavor]], flavor)
    end, { class = "WARRIOR" })
  end
end

local function test_the_mage_casts_a_ground_blizzard_and_has_no_proc_rule()
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w)
      local blizzard = SimSpellData.get(w, BARS.MAGE[GROUP_OF[flavor]][3])
      local area = blizzard.effects[1]
      A.same({ blizzard.ground, area.type, area.target, area.radius > 0, #w.sim.procRules }, { true, "persistent", "areaDest", true, 0 }, flavor)
      A.same({ SimSpellData.get(w, 133).ground, SimSpellData.get(w, 122).ground }, { false, false }, flavor)
    end, { class = "MAGE" })
  end
end

local function test_a_world_reset_to_another_class_swaps_spells_bar_and_rules()
  SH.withSim("retail", function(w)
    A.same({ barIds(w)[1], #w.sim.procRules, w.mock.spells[100].known }, { 100, 1, true })
    Sim.reset(w, "MAGE")
    A.same(barIds(w), { 133, 122, 190356 })
    A.same({ #w.sim.procRules, w.mock.spells[100].known, w.mock.spells[133].known }, { 0, nil, true })
    Sim.reset(w, "WARRIOR")
    A.same({ barIds(w)[4], #w.sim.procRules, w.mock.spells[133].known }, { 6572, 1, nil })
  end, { class = "WARRIOR" })
end

local function test_a_reload_gives_the_restored_class_its_own_kit()
  H.withSession({ sim = { class = "WARRIOR" } }, function(sess)
    local reply = sess:call("sim", { action = "reset", class = "MAGE" })
    A.eq(reply.ok, true, reply.error)
    SH.reloaded(sess, function(fresh)
      local w = fresh.w
      A.same({ w.sim.class, barIds(w), #w.sim.procRules }, { "MAGE", { 133, 122, 190356 }, 0 })
      A.same({ _G.GetActionInfo(1) }, { "spell", 133, "spell" })
    end)
  end)
end

local function test_an_extracts_name_wins_over_the_literal_name()
  local files = { ["db2/spellname.lua"] = "return { [133] = { Name_lang = 'Kit Name' } }" }
  local extract = Client.extract(Tmp.dir("classes"), "retail", "1", files)
  local s = Scenario.new({ addon = "T", root = "T", flavor = "retail", sim = { class = "MAGE" }, client = extract })
  local ok, err = pcall(function()
    A.same({ _G.C_Spell.GetSpellInfo(133).name, SimSpellData.get(s.w, 133).name }, { "Kit Name", "Kit Name" })
    A.eq(_G.C_Spell.GetSpellInfo(122).name, "Frost Nova")
  end)
  s.w:destroy()
  A.eq(ok, true, err)
end

-- A foe `yards` ahead of the player (at (0, -10) facing north) that becomes its target.
local function foeAhead(w, player, yards)
  return SP.target(w, player, 0, -10 + yards)
end

local function test_charge_by_the_bar_runs_to_melee_energizes_and_stuns()
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w, s, player)
      local foe = foeAhead(w, player, 20)
      _G.UseAction(1)
      s:simStep(1.2)
      A.eq(SimMelee.inRange(player, foe), true, flavor)
      A.same({ SP.hitsOn(w, "SPELL_ENERGIZE", player.guid), player.power >= 19 }, { 1, true }, flavor)
      local auras = SP.effectsOfKind(w, "aura")
      A.same({ auras[1].guid, auras[1].style, auras[1].spellID }, { foe.guid, "stun", 100 }, flavor)
    end, { class = "WARRIOR" })
  end
end

local function test_fireball_by_the_bar_costs_mana_and_damages()
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w, s, player)
      local foe = foeAhead(w, player, 20)
      _G.UseAction(1)
      A.eq(player.casting.spellID, 133, flavor)
      s:simStep(4)
      A.same({ player.power < 100, player.power > 60, foe.health < foe.healthMax }, { true, true, true }, flavor)
    end, { class = "MAGE" })
  end
end

local function test_frost_nova_roots_a_foe_at_five_yards_and_not_one_at_twelve()
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w, s, player)
      local near = SH.foe(w, 0, -5)
      local far = SH.foe(w, 0, 2)
      _G.UseAction(2)
      s:simStep(0.1)
      local auras = SP.effectsOfKind(w, "aura")
      A.same({ #auras, auras[1].guid, auras[1].style }, { 1, near.guid, "root" }, flavor)
      A.eq(far.health, far.healthMax, flavor)
      A.eq(player.power < 100, true, flavor)
    end, { class = "MAGE" })
  end
end

local function test_thunder_clap_hits_foes_within_eight_yards_only()
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w, s, player)
      local near = SH.foe(w, 0, -5)
      local far = SH.foe(w, 0, 2)
      Actors.setPower(w, player, 50)
      _G.UseAction(2)
      s:simStep(0.1)
      A.same({ SP.hitsOn(w, "SPELL_DAMAGE", near.guid), SP.hitsOn(w, "SPELL_DAMAGE", far.guid), player.power }, { 1, 0, 30 }, flavor)
    end, { class = "WARRIOR" })
  end
end

local function test_blizzard_by_the_bar_enters_targeting_and_a_click_drops_the_area()
  for _, flavor in ipairs(SH.FLAVORS) do
    SH.withSim(flavor, function(w, s)
      _G.UseAction(3)
      A.eq(_G.SpellIsTargeting(), true, flavor)
      s:clickGround(0, 10)
      s:simStep(3)
      local ground = SP.effectsOfKind(w, "ground")
      A.same({ #ground, ground[1].radius > 0 }, { 1, true }, flavor)
    end, { class = "MAGE" })
  end
end

local function test_the_first_action_key_casts_without_blizzards_action_button()
  SH.withSim("retail", function(w, s, player)
    _G.ActionButtonDown, _G.ActionButtonUp = nil, nil
    foeAhead(w, player, 20)
    s:key("1", "down")
    A.eq(player.casting.spellID, 133)
    s:key("1", "up")
  end, { class = "MAGE" })
end

-- A mob that never swings back, 1 yard ahead of the player and its target: the one foe that can dodge.
local function dummyAhead(w, player)
  local mob = SimMobs.spawn(w, { pos = { x = 0, y = -9 }, health = 100000, ai = false })
  Actors.setTarget(w, player, mob)

  return mob
end

local function test_the_warriors_swings_light_their_groups_overlay_by_hits_or_by_a_dodge()
  for _, flavor in ipairs({ "retail", "tbc" }) do
    SH.withSim(flavor, function(w, s, player)
      local overlay = BARS.WARRIOR[GROUP_OF[flavor]][4]
      dummyAhead(w, player)
      SimMelee.start(w)
      local guard = 0
      while not _G.C_SpellActivationOverlay.IsSpellOverlayed(overlay) and guard < 80 do
        s:simStep(0.5)
        guard = guard + 1
      end
      SimMelee.stop(w)
      A.eq(_G.C_SpellActivationOverlay.IsSpellOverlayed(overlay), true, flavor)
    end, { class = "WARRIOR" })
  end
end

return function()
  test_every_flavor_has_its_group_assumed()
  test_each_flavor_knows_its_group_and_bars_it()
  test_an_id_never_crosses_groups()
  test_the_warriors_proc_rule_follows_its_group()
  test_the_mage_casts_a_ground_blizzard_and_has_no_proc_rule()
  test_a_world_reset_to_another_class_swaps_spells_bar_and_rules()
  test_a_reload_gives_the_restored_class_its_own_kit()
  test_an_extracts_name_wins_over_the_literal_name()
  test_charge_by_the_bar_runs_to_melee_energizes_and_stuns()
  test_fireball_by_the_bar_costs_mana_and_damages()
  test_frost_nova_roots_a_foe_at_five_yards_and_not_one_at_twelve()
  test_thunder_clap_hits_foes_within_eight_yards_only()
  test_blizzard_by_the_bar_enters_targeting_and_a_click_drops_the_area()
  test_the_first_action_key_casts_without_blizzards_action_button()
  test_the_warriors_swings_light_their_groups_overlay_by_hits_or_by_a_dodge()
end
