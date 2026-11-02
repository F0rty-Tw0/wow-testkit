-- Sim range: the distance rule (reach included), the coordinate swap, facing, and the position, range, interact, map,
-- spell and item fakes that answer from the actors' places.
local A = require("assert")
local Actors = require("combat_actors")
local Group = require("combat_group")
local H = require("tests.helpers.sim")
local Sim = require("sim")
local SimRange = require("sim_range")

local function at(x, y, extra)
  local actor = { pos = { x = x, y = y } }
  for key, value in pairs(extra or {}) do
    actor[key] = value
  end

  return actor
end

local function mob(w, y, token)
  return Actors.add(w, { kind = "npc", name = "Mob", hostile = true, token = token or "boss1", pos = { x = 0, y = y } })
end

local function ally(w, y)
  local ann = Actors.add(w, { kind = "player", name = "Ann", pos = { x = 0, y = y } })
  Group.set(w, { Actors.get(w, "player"), ann }, { raid = false })

  return ann
end

local function test_distance_subtracts_both_reaches_assumed()
  H.near(SimRange.distance(at(0, -10), at(0, 10)), 17)
  H.near(SimRange.distance(at(0, -10), at(0, 10, { reach = 0 })), 18.5)
  A.eq(SimRange.distance(at(0, -10), at(0, -9)), 0)
  A.eq(SimRange.REACH, 1.5)
end

local function test_to_wow_swaps_the_axes_assumed()
  A.same({ SimRange.toWow({ x = 3, y = 7 }) }, { 7, -3 })
end

local function test_to_map_follows_the_map_rect()
  H.each({}, function(w)
    A.same({ SimRange.toMap(w, { x = 25, y = 0 }) }, { 0.75, 0.5 })
  end)
end

local function test_in_front_follows_the_facing()
  local north = at(0, 0, { facing = 0 })
  local south = at(0, 0, { facing = math.pi })
  A.eq(SimRange.inFront(north, at(0, 10)), true)
  A.eq(SimRange.inFront(north, at(0, -30)), false)
  A.eq(SimRange.inFront(south, at(0, 10)), false)
  A.eq(SimRange.inFront(south, at(0, -30)), true)
  A.eq(SimRange.inFront(north, at(0, 0)), true)
end

local function test_unit_position_swaps_the_axes_for_the_player_only_assumed()
  H.each({}, function(w, s)
    mob(w, 10)
    s:place(3, 7)
    A.same({ _G.UnitPosition("player") }, { 7, -3, 0, Sim.MAP_ID })
    A.same({ _G.UnitPosition("boss1") }, {})
  end)
end

local function test_unit_position_of_a_party_member()
  H.each({}, function(w)
    ally(w, 20)
    A.same({ _G.UnitPosition("party1") }, { 20, 0, 0, Sim.MAP_ID })
  end)
end

local function test_unit_in_range_is_forty_yards_for_the_group_assumed()
  H.each({}, function(w)
    local ann = ally(w, 45)
    mob(w, 10)
    A.same({ _G.UnitInRange("party1") }, { false, true })
    Actors.setPos(w, ann, 0, 20)
    A.same({ _G.UnitInRange("party1") }, { true, true })
    A.same({ _G.UnitInRange("boss1") }, { false, false })
  end)
end

local function test_check_interact_distance_uses_the_index_range_assumed()
  H.each({}, function(w)
    local boss = mob(w, -10 + 3 + 8) -- 8 yd after both reaches
    A.eq(_G.CheckInteractDistance("boss1", 3), true)
    Actors.setPos(w, boss, 0, -10 + 3 + 12)
    A.eq(_G.CheckInteractDistance("boss1", 3), false)
    A.eq(_G.CheckInteractDistance("boss1", 2), false)
    Actors.setPos(w, boss, 0, -10 + 3 + 11.1)
    A.eq(_G.CheckInteractDistance("boss1", 2), true)
    Actors.setPos(w, boss, 0, -10 + 3 + 11.12)
    A.eq(_G.CheckInteractDistance("boss1", 2), false)
    A.eq(_G.CheckInteractDistance("boss1", 1), true)
  end)
end

local function test_player_map_position_follows_the_walk()
  H.each({}, function(_, s)
    if not (_G.C_Map and _G.C_Map.GetPlayerMapPosition) then
      return
    end
    A.same({ _G.C_Map.GetPlayerMapPosition(Sim.MAP_ID, "player"):GetXY() }, { 0.5, 0.6 })
    s:place(25, 0)
    s:simStep(0.02)
    A.same({ _G.C_Map.GetPlayerMapPosition(Sim.MAP_ID, "player"):GetXY() }, { 0.75, 0.5 })
  end)
end

local function spellInRange(spell, unit)
  if _G.C_Spell and _G.C_Spell.IsSpellInRange then
    return _G.C_Spell.IsSpellInRange(spell, unit)
  end

  return _G.IsSpellInRange(spell, unit) == 1
end

local function test_spell_range_reads_the_record()
  H.each({}, function(w, s)
    w:setMock({ spells = { [900101] = { name = "Kit Reach", minRange = 0, maxRange = 10 }, [900102] = { name = "Kit Free" } } })
    local target = mob(w, 10)
    Actors.setTarget(w, Actors.get(w, "player"), target)
    A.eq(spellInRange(900101, "target"), false)
    A.eq(spellInRange(900101), false)
    s:place(0, 0)
    A.eq(spellInRange(900101, "target"), true)
    A.eq(spellInRange("Kit Reach", "boss1"), true)
    A.eq(_G.C_Spell.IsSpellInRange(900102, "target"), nil)
    A.eq(_G.C_Spell.IsSpellInRange(900101, "nobody"), nil)
  end)
end

local function test_spell_min_range_and_the_global_form_assumed()
  H.each({}, function(w, s)
    w:setMock({ spells = { [900103] = { name = "Kit Far", minRange = 8, maxRange = 30 } } })
    mob(w, 10)
    s:place(0, 0)
    A.eq(spellInRange(900103, "boss1"), false) -- 7 yd, under minRange
    s:place(0, -10)
    A.eq(spellInRange(900103, "boss1"), true) -- 17 yd
    if _G.IsSpellInRange then
      A.eq(_G.IsSpellInRange(900103, "boss1"), 1)
      s:place(0, 7)
      A.eq(_G.IsSpellInRange(900103, "boss1"), 0)
    end
  end)
end

local function test_item_range_needs_a_max_range()
  H.each({}, function(w, s)
    mob(w, 10)
    A.eq(_G.C_Item.IsItemInRange(3, "boss1"), nil)
    w.mock.items[3] = { maxRange = 30 }
    A.eq(_G.C_Item.IsItemInRange(3, "boss1"), true)
    s:place(0, -45)
    A.eq(_G.C_Item.IsItemInRange(3, "boss1"), false)
  end)
end

return function()
  test_distance_subtracts_both_reaches_assumed()
  test_to_wow_swaps_the_axes_assumed()
  test_to_map_follows_the_map_rect()
  test_in_front_follows_the_facing()
  test_unit_position_swaps_the_axes_for_the_player_only_assumed()
  test_unit_position_of_a_party_member()
  test_unit_in_range_is_forty_yards_for_the_group_assumed()
  test_check_interact_distance_uses_the_index_range_assumed()
  test_player_map_position_follows_the_walk()
  test_spell_range_reads_the_record()
  test_spell_min_range_and_the_global_form_assumed()
  test_item_range_needs_a_max_range()
end
