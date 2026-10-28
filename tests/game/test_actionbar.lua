-- Action bar reads: slots come from w.mock.actions at call time, through the retail C_ActionBar names (and the one bare
-- global GetActionInfo). Defaults are assumed: no source settles what an unscripted slot answers.
local A = require("assert")
local G = require("tests.helpers.game")

local SLOT = { type = "spell", id = 11, texture = 136235, count = 4, usable = true }

local function test_slot_reads_the_mock_assumed()
  G.withGame("retail", function(w)
    w:setMock({ actions = { [3] = SLOT } })
    A.same({ _G.C_ActionBar.HasAction(3), _G.C_ActionBar.HasAction(4) }, { true, false })
    A.same({ _G.GetActionInfo(3) }, { "spell", 11, "spell" })
    A.same({ _G.C_ActionBar.GetActionTexture(3), _G.C_ActionBar.GetActionTexture(4) }, { 136235, nil })
    A.same({ _G.C_ActionBar.GetActionText(3), _G.C_ActionBar.GetActionText(4) }, { nil, nil })
    A.same({ _G.C_ActionBar.IsUsableAction(3) }, { true, false })
    w:setMock({ actions = { [5] = { type = "spell", id = 1, usable = false } } })
    A.same({ _G.C_ActionBar.IsUsableAction(5) }, { false, false })
  end)
end

local function test_item_and_macro_slots_answer_their_type_assumed()
  G.withGame("retail", function(w)
    w:setMock({ actions = { [1] = { type = "item", id = 5 }, [2] = { type = "macro", id = 7, text = "Hello" } } })
    A.same({ _G.GetActionInfo(1) }, { "item", 5 })
    A.same({ _G.GetActionInfo(2) }, { "macro", 7 })
    A.eq(_G.C_ActionBar.GetActionText(2), "Hello")
  end)
end

local function test_false_empties_a_slot_assumed()
  G.withGame("retail", function(w)
    w:setMock({ actions = { [3] = { type = "item", id = 5, texture = 1 } } })
    w:setMock({ actions = { [3] = false } })
    A.same({ _G.C_ActionBar.HasAction(3), _G.GetActionInfo(3) }, { false })
    A.same({ _G.C_ActionBar.IsUsableAction(3) }, { false, false })
  end)
end

-- source: assumed the field names come from the api/retail SpellCooldownInfo struct; an idle slot is 0 / 0 / enabled.
local function test_cooldown_is_a_table_assumed()
  G.withGame("retail", function(w)
    w:setMock({ actions = { [3] = SLOT, [4] = { type = "spell", id = 12, start = 10.5, duration = 8 } } })
    A.same(_G.C_ActionBar.GetActionCooldown(3), { startTime = 0, duration = 0, isEnabled = true, modRate = 1 })
    A.same(_G.C_ActionBar.GetActionCooldown(4), { startTime = 10.5, duration = 8, isEnabled = true, modRate = 1 })
  end)
end

local function test_display_count_shows_more_than_one_assumed()
  G.withGame("retail", function(w)
    w:setMock({ actions = { [1] = { count = 4 }, [2] = { count = 1 }, [3] = { count = 12000 }, [4] = { type = "spell", id = 1 } } })
    A.same({ _G.C_ActionBar.GetActionDisplayCount(1), _G.C_ActionBar.GetActionDisplayCount(2) }, { "4", "" })
    A.same({ _G.C_ActionBar.GetActionDisplayCount(3), _G.C_ActionBar.GetActionDisplayCount(4) }, { "*", "" })
    A.eq(_G.C_ActionBar.GetActionDisplayCount(3, 99999), "12000")
    A.eq(_G.C_ActionBar.GetActionDisplayCount(3, 100, "+"), "+")
  end)
end

local function test_state_flags_are_false_by_default_assumed()
  G.withGame("retail", function(w)
    w:setMock({ actions = { [3] = SLOT } })
    for _, name in ipairs({ "IsCurrentAction", "IsAutoRepeatAction", "IsAttackAction" }) do
      A.eq(_G.C_ActionBar[name](3), false, name)
    end
  end)
end

local function test_other_flavors_use_the_same_names_assumed()
  G.withGame("vanilla", function(w)
    w:setMock({ actions = { [3] = SLOT } })
    A.same({ _G.C_ActionBar.HasAction(3), _G.C_ActionBar.GetActionTexture(3) }, { true, 136235 })
    A.eq(_G.HasAction, nil) -- no flavor's API data holds the bare name
  end)
end

return function()
  test_slot_reads_the_mock_assumed()
  test_item_and_macro_slots_answer_their_type_assumed()
  test_false_empties_a_slot_assumed()
  test_cooldown_is_a_table_assumed()
  test_display_count_shows_more_than_one_assumed()
  test_state_flags_are_false_by_default_assumed()
  test_other_flavors_use_the_same_names_assumed()
end
