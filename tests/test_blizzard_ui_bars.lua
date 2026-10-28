-- Blizzard-style action buttons and unit frames over the game-state fakes (Task 10.2): s:actions drives the slots, s:unit
-- the unit fixtures. The mini addons are kit-authored (tests/helpers/blizzard.lua).
local A = require("assert")
local B = require("tests.helpers.blizzard")
local Render = require("render")

-- The snapshot texture item whose file is the asset ref for fileID, or nil.
local function findTexture(snap, fileID)
  for _, item in ipairs(snap.items) do
    if item.kind == "texture" and item.file == "id:" .. fileID then
      return item
    end
  end
  return nil
end

local function test_action_slot_change_updates_the_blizzard_button()
  B.run(B.mini(), { targets = { "Blizzard_MiniButtons" } }, function(s)
    s:actions({ [1] = { type = "spell", id = 11, texture = 136235, count = 3 } })
    local button = _G.MiniBarButton1
    A.same({ button.Icon:GetTexture(), button.Count:GetText() }, { 136235, "3" })
    A.truthy(findTexture(Render.snapshot(s.w), 136235), "the icon is a texture item with file id:136235")
    s:actions({ [1] = false })
    A.same({ button.Icon:GetTexture(), button.Count:GetText() }, { nil, "" })
  end)
end

local SLOT_LOG = [[
SlotLog = {}
local f = CreateFrame("Frame")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
f:SetScript("OnEvent", function(_, _, slot) SlotLog[#SlotLog + 1] = slot end)
]]

local function test_actions_fires_one_event_per_patched_slot_in_ascending_order()
  B.run(B.mini(), { lua = SLOT_LOG }, function(s)
    s:actions({ [5] = { texture = 1 }, [2] = { texture = 2 }, [9] = false })
    A.same(_G.SlotLog, { 2, 5, 9 })
  end)
end

local function test_unit_frame_follows_the_unit_fixture()
  local opts = {
    targets = { "Blizzard_MiniUnit" },
    before = function(s)
      s:unit("player", { name = "Viewer", health = 50, healthMax = 100, role = "TANK", raidTarget = 8 })
    end,
  }
  B.run(B.mini(), opts, function(s)
    local f = _G.MiniPlayerFrame
    A.same({ f.Name:GetText(), f.HealthBar:GetValue(), f.Role, f.Mark }, { "Viewer", 50, "TANK", 8 })
    A.eq(select(2, f.HealthBar:GetMinMaxValues()), 100)
    A.eq(f.Portrait:GetTexture(), "Interface\\CharacterFrame\\TempPortrait")
    s:unit("player", { name = "Viewer", health = 20, healthMax = 100 })
    s.w:fire("UNIT_HEALTH", "player")
    A.eq(f.HealthBar:GetValue(), 20)
  end)
end

return function()
  test_action_slot_change_updates_the_blizzard_button()
  test_actions_fires_one_event_per_patched_slot_in_ascending_order()
  test_unit_frame_follows_the_unit_fixture()
end
