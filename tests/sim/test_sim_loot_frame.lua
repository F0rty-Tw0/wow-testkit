-- Sim loot frame contract: a frame wired the way Blizzard's two LootFrames are (retail registers three events in OnShow,
-- classic all at creation) shows the rows, drops a taken one, closes the corpse when the player hides it and reopens it.
local A = require("assert")
local LH = require("tests.helpers.sim_loot")
local SH = require("tests.helpers.sim_combat")
local SimTarget = require("sim_target")

local function test_frame(style)
  return function(w)
    local frame = LH.miniLootFrame(w, style)
    local ev = SH.record(w, { "LOOT_CLOSED" })
    local mob = LH.corpse(w, 0, -8)
    SimTarget.interact(w, mob, "RightButton")
    A.same({ frame:IsShown(), frame.rows[1], frame.rows[2], frame.rows[3] }, { true, string.format(_G.COPPER_AMOUNT, 37), "Kit Scrap", "Kit Linen" })
    _G.LootSlot(2)
    A.same({ frame.rows[2], frame:IsShown() }, { nil, true })
    frame:Hide() -- the player closes the frame: OnHide -> CloseLoot
    A.same({ #ev, w.sim.loot.window, mob.lootable }, { 1, nil, true }) -- one LOOT_CLOSED, the corpse keeps 2 drops
    SimTarget.interact(w, mob, "RightButton")
    A.eq(frame.rows[1], string.format(_G.COPPER_AMOUNT, 37)) -- reopened
    _G.LootSlot(1)
    _G.LootSlot(2) -- slots renumber after a close: money, then the white item
    A.same({ frame:IsShown(), #ev, mob.lootable }, { false, 2, false }) -- LOOT_CLOSED hid the frame; its OnHide re-entered CloseLoot
    A.eq(#w.warnings, 0)
  end
end

local function main()
  for _, flavor in ipairs(LH.FLAVORS) do
    for _, style in ipairs({ "retail", "classic" }) do
      SH.withSim(flavor, test_frame(style))
    end
  end
end

main()
