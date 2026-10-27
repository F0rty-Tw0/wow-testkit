-- Threat: per-enemy lists, the statuses UnitThreatSituation and UnitDetailedThreatSituation answer, and their events.
local A = require("assert")
local Actors = require("combat_actors")
local Group = require("combat_group")
local H = require("tests.helpers.combat")
local Threat = require("combat_threat")

local EVENTS = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }

-- Ann (party1), Cal (party2) and Brute (boss1, targeting Ann).
local function trio(w)
  local ann, brute = H.pair(w)
  local cal = Actors.add(w, { kind = "player", name = "Cal", token = "party2" })
  Actors.setTarget(w, brute, ann)
  return ann, cal, brute
end

local function test_top_threat_and_percentages() -- (C12)
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    Threat.add(w, brute, ann, 500)
    Threat.add(w, brute, cal, 250)
    A.same({ _G.UnitDetailedThreatSituation("party1", "boss1") }, { true, 3, 100, 100, 500 })
    A.same({ _G.UnitDetailedThreatSituation("party2", "boss1") }, { false, 0, 50, 50, 250 })
    A.same({ Threat.get(brute, ann), Threat.get(brute, cal), Threat.top(brute) == ann }, { 500, 250, true })
  end)
end

local function test_status_climbs_with_the_tanks_threat() -- (C12)
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    Threat.add(w, brute, ann, 500)
    Threat.add(w, brute, cal, 700) -- above the tank, not yet primary
    A.same({ _G.UnitThreatSituation("party1", "boss1"), _G.UnitThreatSituation("party2", "boss1") }, { 2, 1 })
    A.same({ _G.UnitDetailedThreatSituation("party2", "boss1") }, { false, 1, 140, 140, 700 })
    Actors.setTarget(w, brute, cal)
    A.same({ _G.UnitThreatSituation("party1", "boss1"), _G.UnitThreatSituation("party2", "boss1") }, { 0, 3 })
  end)
end

local function test_unit_threat_situation_is_nil_off_the_list() -- (C12)
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    Threat.add(w, brute, ann, 100)
    A.eq(_G.UnitThreatSituation("party2", "boss1"), nil)
    A.eq(cal.threatOn, nil)
  end)
end

local function test_detailed_threat_is_empty_off_the_list_assumed() -- (C12)
  H.withCombat("retail", function(w)
    local ann, _, brute = trio(w)
    Threat.add(w, brute, ann, 100)
    A.eq(select("#", _G.UnitDetailedThreatSituation("party2", "boss1")), 0)
  end)
end

local function test_events_fire_on_list_and_status_change() -- (C12)
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    local log = H.watch(w, EVENTS)
    Threat.add(w, brute, ann, 500)
    A.same(H.names(log), { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" })
    A.eq(log[1][3], "boss1")
    A.eq(log[2][3], "party1")
    Threat.add(w, brute, ann, 100) -- the list changes, no status does
    A.same(H.names(log), { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" })
    Threat.add(w, brute, cal, 10) -- Cal joins the list at status 0
    A.eq(log[#log][3], "party2")
    A.eq(log[#log - 1].event, "UNIT_THREAT_LIST_UPDATE")
    local count = #log
    Threat.add(w, brute, cal, 0)
    A.eq(#log, count)
  end)
end

local function test_a_target_switch_changes_statuses_without_a_list_event() -- (C12)
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    Threat.add(w, brute, ann, 500)
    Threat.add(w, brute, cal, 250)
    local log = H.watch(w, EVENTS)
    Actors.setTarget(w, brute, cal)
    A.same(H.names(log), { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" })
    A.same({ log[1][3], log[2][3] }, { "party1", "party2" })
  end)
end

local function test_clear_drops_the_list()
  H.withCombat("retail", function(w)
    local ann, _, brute = trio(w)
    Threat.add(w, brute, ann, 500)
    local log = H.watch(w, EVENTS)
    Threat.clear(w, brute)
    A.same(H.names(log), { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" })
    A.same({ Threat.get(brute, ann), Threat.top(brute), _G.UnitThreatSituation("party1", "boss1") }, { 0, nil, nil })
    Threat.clear(w, brute) -- empty already: no event
    A.eq(#log, 2)
  end)
end

local function test_threat_situation_without_a_mob_is_the_highest() -- (C12)
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    Threat.add(w, brute, ann, 500)
    Threat.add(w, brute, cal, 250)
    A.eq(_G.UnitThreatSituation("party1"), 3)
    A.eq(_G.UnitThreatSituation("party1", "boss1"), 3)
    A.eq(_G.UnitThreatSituation("party2", "boss1"), 0)
  end)
end

local function test_highest_status_over_several_mobs()
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    local imp = Actors.add(w, { kind = "npc", name = "Imp", token = "boss2", hostile = true })
    Actors.setTarget(w, imp, cal)
    Threat.add(w, brute, ann, 500)
    Threat.add(w, brute, cal, 100)
    Threat.add(w, imp, ann, 50)
    Threat.add(w, imp, cal, 60)
    A.same({ _G.UnitThreatSituation("party1"), _G.UnitThreatSituation("party2") }, { 3, 3 })
    A.same({ _G.UnitThreatSituation("party1", "boss2"), _G.UnitThreatSituation("party2", "boss2") }, { 0, 3 })
    Threat.clear(w, brute)
    A.same({ _G.UnitThreatSituation("party1"), _G.UnitThreatSituation("party2") }, { 0, 3 })
  end)
end

local function test_ties_go_to_the_first_on_the_list()
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    Threat.add(w, brute, cal, 100)
    Threat.add(w, brute, ann, 100)
    A.eq(Threat.top(brute), cal)
  end)
end

local function test_a_despawned_source_leaves_every_list()
  H.withCombat("retail", function(w)
    local ann, cal, brute = trio(w)
    Threat.add(w, brute, ann, 500)
    Threat.add(w, brute, cal, 250)
    Actors.remove(w, ann)
    A.eq(Threat.top(brute), cal)
    Actors.remove(w, brute)
    A.eq(cal.threat, nil)
  end)
end

local function test_threat_rejects_a_value_that_is_not_an_actor()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    A.errors(function()
      Threat.add(w, {}, ann, 1)
    end, "not an actor")
    A.errors(function()
      Threat.add(w, ann, ann, "x")
    end, "number")
  end)
end

local function test_group_members_keep_threat_across_a_roster_change()
  H.withCombat("retail", function(w)
    local ann, _, brute = trio(w)
    Threat.add(w, brute, ann, 500)
    Group.set(w, { Actors.get(w, "player"), ann }, { raid = false })
    A.same({ _G.UnitDetailedThreatSituation("party1", "boss1") }, { true, 3, 100, 100, 500 })
  end)
end

return function()
  test_top_threat_and_percentages()
  test_status_climbs_with_the_tanks_threat()
  test_unit_threat_situation_is_nil_off_the_list()
  test_detailed_threat_is_empty_off_the_list_assumed()
  test_events_fire_on_list_and_status_change()
  test_a_target_switch_changes_statuses_without_a_list_event()
  test_clear_drops_the_list()
  test_threat_situation_without_a_mob_is_the_highest()
  test_highest_status_over_several_mobs()
  test_ties_go_to_the_first_on_the_list()
  test_a_despawned_source_leaves_every_list()
  test_threat_rejects_a_value_that_is_not_an_actor()
  test_group_members_keep_threat_across_a_roster_change()
end
