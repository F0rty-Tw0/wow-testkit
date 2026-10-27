-- Combat nameplates: the plates of live actors, their tokens, events, CVar gates and ground projection.
local A = require("assert")
local Actors = require("combat_actors")
local Combat = require("combat")
local H = require("tests.helpers.combat")
local Layout = require("ui.layout")
local Nameplates = require("combat_nameplates")
local Resolve = require("combat_resolve")

local PLATE_EVENTS = { "NAME_PLATE_CREATED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

local function grunt(w, name, x, y)
  return Actors.add(w, { kind = "npc", name = name, hostile = true, pos = { x = x or 0, y = y or 0 } })
end

-- Brute at x = 8, y = 27: d = 27 + 5 = 32; x = 960 + 972 * 8 / 32 = 1203; y = 594 - 972 * 2 / 32 = 533.25.
-- The plate is 110 wide, anchored BOTTOM: left = 1203 - 55 = 1148.
local function test_plate_rect_follows_the_ground_projection()
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    Actors.setPos(w, brute, 8, 27)
    local plate = _G.C_NamePlate.GetNamePlateForUnit("nameplate1")
    local rect = Layout.rect(w, plate)
    A.same({ rect.left, rect.bottom, rect.width }, { 1148, 533.25, 110 })
    A.same({ Nameplates.project(w, brute) }, { 1203, 533.25 })
  end, true)
end

local function test_lifecycle_order_and_frame_reuse() -- (C13)
  H.withCombat("retail", function(w)
    local log = H.watch(w, PLATE_EVENTS)
    local _, brute = H.pair(w)
    A.same(H.names(log), { "NAME_PLATE_CREATED", "NAME_PLATE_UNIT_ADDED" })
    local frame = _G.C_NamePlate.GetNamePlateForUnit("nameplate1")
    A.eq(log[1][3], frame)
    A.eq(log[2][3], "nameplate1")
    A.eq(_G.UnitName("nameplate1"), "Brute")
    A.eq(_G.UnitTokenFromGUID(brute.guid), "nameplate1") -- nameplate# ranks before boss#
    Actors.remove(w, brute)
    A.eq(log[3].event, "NAME_PLATE_UNIT_REMOVED")
    A.eq(log[3][3], "nameplate1")
    A.eq(_G.C_NamePlate.GetNamePlateForUnit("nameplate1"), nil)
    A.eq(frame:IsShown(), false)
    grunt(w, "Grunt")
    A.same(H.names(log), { "NAME_PLATE_CREATED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "NAME_PLATE_UNIT_ADDED" })
    A.eq(log[4][3], "nameplate1")
    A.eq(_G.C_NamePlate.GetNamePlateForUnit("nameplate1"), frame)
    A.eq(frame:IsShown(), true)
  end, true)
end

local function test_a_dead_actor_loses_its_plate_and_a_revived_one_gets_it_back_assumed()
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    local log = H.watch(w, PLATE_EVENTS)
    Resolve.kill(w, brute)
    A.same(H.names(log), { "NAME_PLATE_UNIT_REMOVED" })
    A.eq(_G.C_NamePlate.GetNamePlateForUnit("nameplate1"), nil)
    Resolve.revive(w, brute, 100)
    A.same(H.names(log), { "NAME_PLATE_UNIT_REMOVED", "NAME_PLATE_UNIT_ADDED" })
  end, true)
end

local function test_removed_fires_while_the_token_still_maps() -- (C13)
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    local seen
    local frame = _G.CreateFrame("Frame")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:SetScript("OnEvent", function(_, _, token)
      seen = { _G.UnitExists(token), _G.UnitName(token), _G.C_NamePlate.GetNamePlateForUnit(token) ~= nil }
    end)
    Actors.remove(w, brute)
    A.same(seen, { true, "Brute", true })
    A.eq(_G.UnitExists("nameplate1"), false)
  end, true)
end

local function test_range_and_cvars_gate_plates()
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    Actors.setPos(w, brute, 0, 70)
    A.eq(_G.C_NamePlate.GetNamePlateForUnit("nameplate1"), nil)
    local log = H.watch(w, PLATE_EVENTS)
    Actors.setPos(w, brute, 0, 30)
    A.same(H.names(log), { "NAME_PLATE_UNIT_ADDED" }) -- the frame from the first add is pooled, not created again
    _G.SetCVar("nameplateShowEnemies", "0")
    A.same(H.names(log), { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" })
    A.eq(_G.C_NamePlate.GetNamePlateForUnit("nameplate1"), nil)
    _G.SetCVar("nameplateShowEnemies", "1")
    A.eq(log[3].event, "NAME_PLATE_UNIT_ADDED")
    Actors.setPos(w, ann, 0, 10)
    A.eq(_G.UnitExists("nameplate2"), false)
    _G.SetCVar("nameplateShowFriends", "1")
    A.eq(_G.UnitName("nameplate2"), "Ann")
    _G.C_CVar.SetCVar("nameplateMaxDistance", "20")
    A.eq(_G.UnitName("nameplate2"), "Ann")
    A.eq(_G.UnitExists("nameplate1"), false) -- Brute at 30 is now out of range
  end, true)
end

local function test_cvar_defaults_are_filled_in_the_cvar_store() -- (C14)
  H.withCombat("retail", function()
    A.eq(_G.GetCVar("nameplateShowEnemies"), "1")
    A.eq(_G.GetCVarBool("nameplateShowFriends"), false)
    A.eq(_G.GetCVar("nameplateShowFriends"), "0")
    A.eq(tonumber(_G.GetCVar("nameplateMaxDistance")), 60)
  end, true)
end

local function test_set_cvar_emits_the_cvar_hook_with_the_lowercase_name()
  H.withCombat("retail", function(w)
    local names = {}
    Combat.listen(w, "cvar", function(name)
      names[#names + 1] = name
    end)
    _G.SetCVar("nameplateShowEnemies", "0")
    _G.C_CVar.SetCVar("NamePlateMaxDistance", "40")
    A.same(names, { "nameplateshowenemies", "nameplatemaxdistance" })
  end, true)
end

local function test_forbidden_plates_in_instances_assumed() -- (C13)
  H.withCombat("retail", function(w)
    w:setMock({ instance = { type = "party" } })
    local ann = H.pair(w)
    local log = H.watch(w, {
      "NAME_PLATE_CREATED",
      "NAME_PLATE_UNIT_ADDED",
      "FORBIDDEN_NAME_PLATE_CREATED",
      "FORBIDDEN_NAME_PLATE_UNIT_ADDED",
      "FORBIDDEN_NAME_PLATE_UNIT_REMOVED",
    })
    _G.SetCVar("nameplateShowFriends", "1")
    -- Brute holds nameplate1 from before; Ann is a friend in an instance, so her plate is forbidden.
    A.same(H.names(log), { "FORBIDDEN_NAME_PLATE_CREATED", "FORBIDDEN_NAME_PLATE_UNIT_ADDED" })
    A.eq(log[2][3], "nameplate2")
    A.eq(_G.C_NamePlate.GetNamePlateForUnit("nameplate2"), nil)
    A.eq(_G.C_NamePlate.GetNamePlateForUnit("nameplate2", true), log[1][3])
    A.eq(#_G.C_NamePlate.GetNamePlates(), 1)
    A.eq(#_G.C_NamePlate.GetNamePlates(true), 2)
    Actors.remove(w, ann)
    A.eq(log[3].event, "FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
    A.eq(log[3][3], "nameplate2")
  end, true)
end

local function test_get_name_plates_lists_plates_by_index()
  H.withCombat("retail", function(w)
    local first = grunt(w, "One")
    grunt(w, "Two")
    grunt(w, "Three")
    Actors.remove(w, first)
    grunt(w, "Four") -- takes the lowest free index, 1
    local plates = _G.C_NamePlate.GetNamePlates()
    A.eq(#plates, 3)
    A.same({ plates[1].namePlateUnitToken, plates[2].namePlateUnitToken, plates[3].namePlateUnitToken }, { "nameplate1", "nameplate2", "nameplate3" })
    A.eq(_G.UnitName("nameplate1"), "Four")
    A.eq(_G.UnitName("nameplate3"), "Three")
  end, true)
end

local function test_plate_health_bar_and_name_follow_the_actor()
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    local unitFrame = _G.C_NamePlate.GetNamePlateForUnit("nameplate1").UnitFrame
    A.eq(unitFrame.name:GetText(), "Brute")
    A.eq(unitFrame.healthBar:GetValue(), 5000)
    Actors.setHealth(w, brute, 1200)
    A.eq(unitFrame.healthBar:GetValue(), 1200)
    Actors.setHealthMax(w, brute, 2000)
    A.same({ unitFrame.healthBar:GetMinMaxValues() }, { 0, 2000 })
    A.eq(unitFrame.healthBar:GetValue(), 1200)
  end, true)
end

local function test_plate_unit_frame_unit_is_the_token()
  H.withCombat("retail", function(w)
    H.pair(w)
    local plate = _G.C_NamePlate.GetNamePlateForUnit("nameplate1")
    A.eq(plate.namePlateUnitToken, "nameplate1")
    A.eq(plate.UnitFrame.unit, "nameplate1")
    A.eq(plate.UnitFrame.displayedUnit, "nameplate1")
    A.eq(plate.UnitFrame:GetParent(), plate)
    A.eq(plate:GetParent(), _G.WorldFrame)
    A.eq(plate:GetName(), "NamePlate1")
    A.same({ plate:GetWidth(), plate:GetHeight() }, { 110, 45 }) -- (C14, assumed)
    A.same({ _G.C_NamePlate.GetNamePlateSize() }, { 110, 45 })
  end, true)
end

local function test_actor_behind_the_camera_has_no_projection()
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    local plate = _G.C_NamePlate.GetNamePlateForUnit("nameplate1")
    Actors.setPos(w, brute, 0, -6)
    A.eq(Nameplates.project(w, brute), nil)
    A.eq(plate:IsShown(), false)
    Actors.setPos(w, brute, 0, 10)
    A.eq(plate:IsShown(), true)
  end, true)
end

local function test_the_player_has_no_plate()
  H.withCombat("retail", function(w)
    _G.SetCVar("nameplateShowFriends", "1")
    A.eq(_G.UnitExists("nameplate1"), false)
    A.eq(#_G.C_NamePlate.GetNamePlates(), 0)
    A.eq(w.combat.actors[_G.UnitGUID("player")] ~= nil, true)
  end, true)
end

return function()
  test_plate_rect_follows_the_ground_projection()
  test_lifecycle_order_and_frame_reuse()
  test_a_dead_actor_loses_its_plate_and_a_revived_one_gets_it_back_assumed()
  test_removed_fires_while_the_token_still_maps()
  test_range_and_cvars_gate_plates()
  test_cvar_defaults_are_filled_in_the_cvar_store()
  test_set_cvar_emits_the_cvar_hook_with_the_lowercase_name()
  test_forbidden_plates_in_instances_assumed()
  test_get_name_plates_lists_plates_by_index()
  test_plate_health_bar_and_name_follow_the_actor()
  test_plate_unit_frame_unit_is_the_token()
  test_actor_behind_the_camera_has_no_projection()
  test_the_player_has_no_plate()
end
