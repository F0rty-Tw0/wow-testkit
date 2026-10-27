-- Combat presets: solo, dungeon and raid worlds built from kit data, and the s:preset step.
local A = require("assert")
local Actors = require("combat_actors")
local H = require("tests.helpers.combat")
local Roster = require("combat_roster_data")

-- The tokens of the player and everyone in the group, in roster order.
local function memberTokens(count, raid)
  local tokens = { raid and "raid1" or "player" }
  for i = 2, count do
    tokens[i] = raid and ("raid" .. i) or ("party" .. (i - 1))
  end
  return tokens
end

local function roleCounts(tokens)
  local roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }
  for _, token in ipairs(tokens) do
    local role = _G.UnitGroupRolesAssigned(token)
    roles[role] = roles[role] + 1
  end
  return roles
end

local function test_dungeon_is_five_with_one_tank_one_healer_three_dps()
  H.withCombat("retail", function(w, _, s)
    s:preset("dungeon", {})
    A.same({ _G.IsInGroup(), _G.IsInRaid(), _G.GetNumGroupMembers() }, { true, false, 5 })
    A.same(roleCounts(memberTokens(5)), { TANK = 1, HEALER = 1, DAMAGER = 3 })
    A.eq(_G.UnitExists("party5"), false)
    A.eq(_G.UnitExists("boss1"), true)
    A.eq(_G.InCombatLockdown(), false)
    A.eq(#w.combat.preset.enemies, 5)
  end)
end

local function test_faction_race_class_pick()
  H.withCombat("retail", function(_, _, s)
    s:preset("solo", { faction = "Horde", race = "Orc", class = "WARLOCK" })
    A.same({ _G.UnitFactionGroup("player") }, { "Horde", "Horde" })
    A.same({ _G.UnitRace("player") }, { "Orc", "Orc" })
    A.same({ _G.UnitClass("player") }, { "Warlock", "WARLOCK" })
  end)
end

local function test_defaults_are_alliance_human_warrior_damager()
  H.withCombat("retail", function(_, _, s)
    s:preset("solo")
    A.same({ _G.UnitFactionGroup("player") }, { "Alliance", "Alliance" })
    A.same({ _G.UnitRace("player") }, { "Human", "Human" })
    A.same({ _G.UnitClass("player") }, { "Warrior", "WARRIOR" })
    A.eq(_G.UnitGroupRolesAssigned("player"), "DAMAGER")
  end)
end

local function test_a_race_with_a_space_keeps_its_file_name()
  H.withCombat("retail", function(_, _, s)
    s:preset("solo", { race = "Night Elf" })
    A.same({ _G.UnitRace("player") }, { "Night Elf", "NightElf" })
  end)
end

local function test_solo_has_no_group_and_fires_no_roster_event()
  H.withCombat("retail", function(_, _, s)
    local log = H.watch(nil, { "GROUP_ROSTER_UPDATE" })
    s:preset("solo", {})
    A.same({ #log, _G.IsInGroup(), _G.GetNumGroupMembers(), _G.UnitExists("boss1") }, { 0, false, 0, true })
  end)
end

local function test_raid_sizes_match_the_role_mix()
  for _, size in ipairs({ 10, 20, 25, 40 }) do
    H.withCombat("retail", function(_, _, s)
      s:preset("raid", { size = size })
      A.same({ _G.IsInRaid(), _G.GetNumGroupMembers() }, { true, size })
      A.eq(_G.UnitExists("raid" .. size), true)
      A.eq(_G.UnitExists("raid" .. (size + 1)), false)
      A.same(roleCounts(memberTokens(size, true)), Roster.ROLE_MIX[size])
    end)
  end
end

-- The player's role counts inside the mix: a tank player leaves one tank fewer to fill.
local function test_the_players_role_counts_inside_the_mix()
  H.withCombat("retail", function(_, _, s)
    s:preset("raid", { size = 10, role = "TANK" })
    A.same(roleCounts(memberTokens(10, true)), Roster.ROLE_MIX[10])
    A.eq(_G.UnitGroupRolesAssigned("player"), "TANK")
  end)
end

local function test_party_tokens_do_not_exist_in_a_raid_assumed() -- (C11)
  H.withCombat("retail", function(_, _, s)
    s:preset("raid", { size = 10 })
    A.same({ _G.UnitExists("party1"), _G.UnitExists("raid2") }, { false, true })
  end)
end

local function test_in_combat_toggle_pulls_the_pack()
  H.withCombat("retail", function(w, c, s)
    local log = H.watch(w, { "PLAYER_REGEN_DISABLED" })
    s:preset("dungeon", { inCombat = true })
    A.same({ #log, _G.InCombatLockdown() }, { 1, true })
    s:advance(3)
    local damage = 0
    for _, entry in ipairs(c.log.entries) do
      damage = damage + (entry[2]:find("_DAMAGE$") and 1 or 0)
    end
    A.truthy(damage > 0)
  end)
end

local function test_without_the_toggle_nothing_starts()
  H.withCombat("retail", function(w, c, s)
    s:preset("dungeon", {})
    s:advance(10)
    A.same({ #c.log.entries, _G.InCombatLockdown(), w.combat.preset.enemies[1].timers }, { 0, false, nil })
  end)
end

local function test_level_default_is_per_flavour()
  H.withCombat("retail", function(_, _, s)
    s:preset("solo")
    A.eq(_G.UnitLevel("player"), 90)
  end)
  H.withCombat("vanilla", function(_, _, s)
    s:preset("solo")
    A.eq(_G.UnitLevel("player"), 60)
  end)
  H.withCombat("tbc", function(_, _, s)
    s:preset("solo", { level = 65 })
    A.eq(_G.UnitLevel("player"), 65)
  end)
end

local function test_class_lists_follow_the_flavour()
  local function classes(size)
    local out = {}
    for i = 1, size do
      out[select(2, _G.UnitClass("raid" .. i))] = true
    end
    return out
  end
  H.withCombat("vanilla", function(_, _, s)
    s:preset("raid", { size = 40 })
    local seen = classes(40)
    A.eq(seen.WARRIOR, true)
    for _, class in ipairs({ "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }) do
      A.eq(seen[class], nil)
    end
  end)
  H.withCombat("retail", function(_, _, s)
    s:preset("raid", { size = 40 })
    A.eq(classes(40).DEATHKNIGHT, true)
  end)
end

local function test_members_are_named_by_class_and_share_the_players_level()
  H.withCombat("retail", function(_, _, s)
    s:preset("dungeon", { level = 70 })
    A.eq(_G.UnitName("party1"), "Kit " .. select(1, _G.UnitClass("party1")) .. " 1")
    A.eq(_G.UnitLevel("party4"), 70)
  end)
end

local function test_bad_name_and_size_raise_with_the_valid_values()
  H.withCombat("retail", function(_, _, s)
    A.errors(function()
      s:preset("arena")
    end, "solo, dungeon or raid")
    A.errors(function()
      s:preset("raid", { size = 7 })
    end, "10, 20, 25 or 40")
    A.errors(function()
      s:preset("solo", { class = "DEMONHUNTER", faction = "Pirate" })
    end, "Alliance or Horde")
  end)
  H.withCombat("vanilla", function(_, _, s)
    A.errors(function()
      s:preset("solo", { class = "DEATHKNIGHT" })
    end, "WARRIOR")
    A.errors(function()
      s:preset("solo", { race = "Goblin" })
    end, "Human")
  end)
end

local function test_a_bad_preset_raises_at_the_scenarios_line_and_builds_nothing()
  H.withCombat("retail", function(w, _, s)
    local message = A.errors(function()
      s:preset("raid", { size = 7 })
    end, "preset:")
    A.contains(message, "test_combat_presets.lua")
    A.eq(w.combat.preset, nil)
    A.eq(_G.IsInGroup(), false)
  end)
end

local function test_applying_a_preset_twice_replaces_the_first()
  H.withCombat("retail", function(w, _, s)
    s:preset("dungeon", {})
    local old = { w.combat.preset.enemies[1], w.combat.preset.members[2] }
    local log = H.watch(w, { "GROUP_ROSTER_UPDATE" })
    s:preset("solo", {})
    A.eq(#log, 1) -- the group disbands once, not once per member despawned
    A.same({ _G.UnitExists("party1"), _G.UnitExists("party4"), _G.IsInGroup() }, { false, false, false })
    A.eq(Actors.get(w, old[1].guid), nil)
    A.eq(Actors.get(w, old[2].guid), nil)
    local actors = 0
    for _ in pairs(w.combat.actors) do
      actors = actors + 1
    end
    A.eq(actors, 2) -- the player and the solo mob
  end)
end

local function test_replacing_an_in_combat_preset_stops_its_ai()
  H.withCombat("retail", function(w, c, s)
    s:preset("dungeon", { inCombat = true })
    s:preset("solo", {})
    local before = #c.log.entries
    s:advance(10)
    A.eq(#c.log.entries, before)
    A.eq(w.combat.preset.enemies[1].timers, nil)
  end)
end

local function test_preset_spells_are_kit_data_and_named()
  H.withCombat("retail", function(w, c, s)
    s:preset("dungeon", { inCombat = true })
    for id, spell in pairs(Roster.SPELLS) do
      A.eq(c.spells[id].name, spell.name)
    end
    A.eq(w.mock.spells[Roster.SPELL.HEAL].name, "Kit Preset Mend")
  end)
end

return function()
  test_dungeon_is_five_with_one_tank_one_healer_three_dps()
  test_faction_race_class_pick()
  test_defaults_are_alliance_human_warrior_damager()
  test_a_race_with_a_space_keeps_its_file_name()
  test_solo_has_no_group_and_fires_no_roster_event()
  test_raid_sizes_match_the_role_mix()
  test_the_players_role_counts_inside_the_mix()
  test_party_tokens_do_not_exist_in_a_raid_assumed()
  test_in_combat_toggle_pulls_the_pack()
  test_without_the_toggle_nothing_starts()
  test_level_default_is_per_flavour()
  test_class_lists_follow_the_flavour()
  test_members_are_named_by_class_and_share_the_players_level()
  test_bad_name_and_size_raise_with_the_valid_values()
  test_a_bad_preset_raises_at_the_scenarios_line_and_builds_nothing()
  test_applying_a_preset_twice_replaces_the_first()
  test_replacing_an_in_combat_preset_stops_its_ai()
  test_preset_spells_are_kit_data_and_named()
end
