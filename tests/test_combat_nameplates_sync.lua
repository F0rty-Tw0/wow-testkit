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

return function()
  test_a_despawned_actor_gets_no_plate_from_a_late_hook()
end
