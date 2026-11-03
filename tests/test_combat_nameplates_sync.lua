-- Combat nameplates, single-actor sync: what a moved or flags hook may and may not do to one plate.
local A = require("assert")
local Actors = require("combat_actors")
local Combat = require("combat")
local H = require("tests.helpers.combat")

local function grunt(w, name, x, y)
  return Actors.add(w, { kind = "npc", name = name, hostile = true, pos = { x = x, y = y } })
end

local function test_a_despawned_actor_gets_no_plate_from_a_late_hook()
  H.withCombat("retail", function(w)
    local c = w.combat
    local gone = grunt(w, "Gone", 0, 10)
    Actors.remove(w, gone)
    local before = #_G.C_NamePlate.GetNamePlates()
    Actors.setPos(w, gone, 1, 11)
    Combat.emit(w, "flags", gone)
    A.eq(c.plateOf[gone], nil)
    A.eq(#_G.C_NamePlate.GetNamePlates(), before)
    A.eq(_G.UnitExists("nameplate1"), false)
  end, true)
end

local function test_a_moved_friend_swaps_its_plate_for_a_forbidden_one_after_an_instance_flip()
  H.withCombat("retail", function(w)
    _G.SetCVar("nameplateShowFriends", "1")
    local friend = Actors.add(w, { kind = "npc", name = "Friend", hostile = false, pos = { x = 0, y = 10 } })
    local plate = _G.C_NamePlate.GetNamePlateForUnit("nameplate1")
    A.eq(plate ~= nil, true)
    local log = H.watch(w, { "NAME_PLATE_UNIT_REMOVED", "FORBIDDEN_NAME_PLATE_UNIT_ADDED" })
    w:setMock({ instance = { type = "party" } })
    Actors.setPos(w, friend, 1, 10)
    A.same(H.names(log), { "NAME_PLATE_UNIT_REMOVED", "FORBIDDEN_NAME_PLATE_UNIT_ADDED" })
    A.same({ #_G.C_NamePlate.GetNamePlates(), #_G.C_NamePlate.GetNamePlates(true) }, { 0, 1 })
    A.eq(w.combat.plateOf[friend].forbidden, true)
  end, true)
end

return function()
  test_a_despawned_actor_gets_no_plate_from_a_late_hook()
  test_a_moved_friend_swaps_its_plate_for_a_forbidden_one_after_an_instance_flip()
end
