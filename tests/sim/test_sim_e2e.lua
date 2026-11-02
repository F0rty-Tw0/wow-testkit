-- Sim slice 1 end to end: a held W walks the player toward a hostile dummy, the spell range, the moving events, the
-- position, the map and the party range all follow the one place.
local A = require("assert")
local Actors = require("combat_actors")
local Group = require("combat_group")
local H = require("tests.helpers.sim")
local Sim = require("sim")

local SPELL = 900101

local function watchMoves()
  local log = {}
  local frame = _G.CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_STARTED_MOVING")
  frame:RegisterEvent("PLAYER_STOPPED_MOVING")
  frame:SetScript("OnEvent", function(_, event, ...)
    log[#log + 1] = { event, ... }
  end)

  return log
end

local function inRange()
  if _G.C_Spell and _G.C_Spell.IsSpellInRange then
    return _G.C_Spell.IsSpellInRange(SPELL, "target")
  end

  return _G.IsSpellInRange(SPELL, "target") == 1
end

local function setup(w)
  w:setMock({ spells = { [SPELL] = { name = "Kit Reach", minRange = 0, maxRange = 10 } } })
  local dummy = Actors.add(w, { kind = "npc", name = "Dummy", hostile = true, pos = { x = 0, y = 10 } })
  Actors.setTarget(w, Actors.get(w, "player"), dummy)
end

local function test_holding_w_walks_into_spell_range()
  H.each({}, function(w, s)
    setup(w)
    local log = watchMoves()
    A.eq(inRange(), false)
    s:key("W", "down")
    s:simStep(0.5)
    A.eq(inRange(), false)
    s:simStep(0.6)
    A.eq(inRange(), true)
    s:key("W", "up")
    s:simStep(0.1)
    A.same(H.names(log), { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" })
    H.near(select(1, _G.UnitPosition("player")), -2.3)
    A.eq(select(2, _G.UnitPosition("player")), 0)
    A.eq(select(4, _G.UnitPosition("player")), Sim.MAP_ID)
  end)
end

local function test_the_map_follows_the_walk()
  H.each({}, function(_, s)
    if not (_G.C_Map and _G.C_Map.GetPlayerMapPosition) then
      return
    end
    s:key("W", "down")
    s:simStep(1.1)
    s:key("W", "up")
    s:simStep(0.1)
    local x, y = _G.C_Map.GetPlayerMapPosition(Sim.MAP_ID, "player"):GetXY()
    H.near(x, 0.5)
    H.near(y, 0.523)
  end)
end

local function test_party_range_follows_the_member()
  H.each({}, function(w)
    local ann = Actors.add(w, { kind = "player", name = "Ann", pos = { x = 0, y = 45 } })
    Group.set(w, { Actors.get(w, "player"), ann }, { raid = false })
    A.same({ _G.UnitInRange("party1") }, { false, true })
    Actors.setPos(w, ann, 0, 20)
    A.same({ _G.UnitInRange("party1") }, { true, true })
  end)
end

return function()
  test_holding_w_walks_into_spell_range()
  test_the_map_follows_the_walk()
  test_party_range_follows_the_member()
end
