-- Unit frame fakes: the portrait stand-in, role, raid marker, vehicle and tap answers. Defaults are assumed: no source
-- settles what a fixture without these fields answers.
local A = require("assert")
local G = require("tests.helpers.game")

local PLACEHOLDER = "Interface\\CharacterFrame\\TempPortrait"

local function test_portrait_is_a_labelled_stand_in_assumed()
  G.withGame("retail", function(w)
    local frame = _G.CreateFrame("Frame")
    local texture = frame:CreateTexture()
    _G.SetPortraitTexture(texture, "player")
    A.eq(texture:GetTexture(), PLACEHOLDER)
    A.eq(w.unscripted.SetPortraitTexture, nil) -- a stand-in on purpose, not an unanswered call
  end)
end

local function test_role_and_raid_target_follow_the_fixture_assumed()
  G.withGame("retail", function(w)
    w:unit("player", { role = "TANK", raidTarget = 8 })
    w:unit("target", { name = "Other" })
    A.same({ _G.UnitGroupRolesAssigned("player"), _G.GetRaidTargetIndex("player") }, { "TANK", 8 })
    A.same({ _G.UnitGroupRolesAssigned("target"), _G.GetRaidTargetIndex("target") }, { "NONE", nil })
    A.eq(w.unscripted.GetRaidTargetIndex, nil) -- an unmarked unit is an answer
  end)
end

local function test_roleless_flavors_answer_none_assumed()
  G.withGame("vanilla", function(w)
    w:unit("player", { role = "TANK" })
    A.eq(_G.UnitGroupRolesAssigned("player"), "NONE")
  end)
end

local function test_vehicle_and_tap_defaults_assumed()
  G.withGame("retail", function(w)
    w:unit("player", { name = "Viewer" })
    w:unit("target", { tapDenied = true })
    A.same({ _G.UnitHasVehicleUI("player"), _G.UnitInVehicle("player") }, { false, false })
    A.same({ _G.UnitIsTapDenied("player"), _G.UnitIsTapDenied("target") }, { false, true })
    A.eq(w.unscripted.UnitIsTapDenied, nil) -- an unset field is the kit default, not an unanswered call
  end)
end

return function()
  test_portrait_is_a_labelled_stand_in_assumed()
  test_role_and_raid_target_follow_the_fixture_assumed()
  test_roleless_flavors_answer_none_assumed()
  test_vehicle_and_tap_defaults_assumed()
end
