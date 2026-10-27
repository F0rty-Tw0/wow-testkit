-- Combat actors: GUIDs, tokens, setters and the hooks they emit.
local A = require("assert")
local Actors = require("combat_actors")
local Combat = require("combat")
local H = require("tests.helpers.combat")
local World = require("world")

local function test_creature_guid_follows_the_client_format() -- (C6)
  H.withCombat("retail", function(w, c)
    local _, brute = H.pair(w)
    A.truthy(brute.guid:match("^Creature%-0%-4001%-1%-%d+%-4321%-%x%x%x%x%x%x%x%x%x%x$"))
    A.eq(c.actors[brute.guid], brute)
  end)
end

local function test_player_and_pet_guid_formats_assumed() -- (C6)
  H.withCombat("retail", function(w, c)
    local ann = H.pair(w)
    local pet = Actors.add(w, { kind = "pet", name = "Rex", npcId = 77 })
    A.truthy(ann.guid:match("^Player%-4001%-%x%x%x%x%x%x%x%x$"))
    A.truthy(pet.guid:match("^Pet%-0%-4001%-1%-%d+%-77%-%x%x%x%x%x%x%x%x%x%x$"))
    A.eq(c.actors[pet.guid], pet)
  end)
end

local function test_npc_id_defaults_to_1000_plus_the_sequence()
  H.withCombat("retail", function(w, c)
    local first = Actors.add(w, { kind = "npc", name = "A" })
    local second = Actors.add(w, { kind = "npc", name = "B" })
    A.eq(first.npcId, 1000 + c.seq - 1)
    A.eq(second.npcId, 1000 + c.seq)
  end)
end

local function test_unit_apis_answer_from_the_actor()
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    A.eq(_G.UnitName("party1"), "Ann")
    A.eq(_G.UnitGUID("boss1"), brute.guid)
    A.eq(_G.UnitHealth("boss1"), 5000)
    A.eq(_G.UnitTokenFromGUID(ann.guid), "party1")
    Actors.setHealth(w, brute, 4200)
    A.eq(_G.UnitHealth("boss1"), 4200) -- live: the actor is the fixture
  end)
end

local function test_hostility_fields_follow_the_hostile_flag()
  H.withCombat("retail", function(w)
    local ann, brute = H.pair(w)
    A.same({ ann.isFriend, ann.isEnemy, ann.canAttack, ann.isPlayer }, { true, false, false, true })
    A.same({ brute.isFriend, brute.isEnemy, brute.canAttack, brute.isPlayer }, { false, true, true, false })
    A.same({ _G.UnitIsEnemy("player", "boss1"), _G.UnitCanAttack("player", "boss1") }, { true, true })
  end)
end

local function test_power_type_comes_from_the_enum()
  for _, flavor in ipairs({ "retail", "vanilla" }) do
    H.withCombat(flavor, function(w)
      local mage = Actors.add(w, { kind = "player", name = "M", token = "party1", power = 50, powerMax = 100 })
      local rogue = Actors.add(w, { kind = "player", name = "R", token = "party2", powerType = "ENERGY", power = 100, powerMax = 100 })
      A.same({ _G.UnitPowerType("party1") }, { 0, "MANA" }, flavor)
      A.same({ _G.UnitPowerType("party2") }, { 3, "ENERGY" }, flavor)
      A.same({ _G.UnitPower("party1"), _G.UnitPowerMax("party1") }, { mage.power, mage.powerMax }, flavor)
      A.eq(rogue.powerToken, "ENERGY", flavor)
    end)
  end
end

local function test_install_adopts_existing_fixtures_and_creates_the_player()
  H.withScenario("retail", function(w)
    w:unit("target", { name = "Bob", health = 50, healthMax = 100 })
    Combat.install(w)
    A.eq(_G.UnitHealth("target"), 50)
    A.truthy(_G.UnitGUID("target"):match("^Creature%-0%-4001%-1%-%d+%-%d+%-%x%x%x%x%x%x%x%x%x%x$"))
    A.eq(w.combat.actors[_G.UnitGUID("target")], w.unitState.byToken.target)
    A.truthy(_G.UnitExists("player"))
    A.eq(w.combat.actors[_G.UnitGUID("player")].kind, "player")
  end)
end

local function test_install_twice_returns_the_same_world()
  H.withCombat("retail", function(w, c)
    A.truthy(Combat.install(w) == c)
    local count = 0
    for _ in pairs(c.actors) do
      count = count + 1
    end
    A.eq(count, 1) -- the player, once
  end)
end

local function test_one_actor_many_tokens_resolves_in_token_order()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Actors.bind(w, ann, "target")
    A.eq(_G.UnitTokenFromGUID(ann.guid), "party1")
    A.same(Actors.tokens(w, ann), { "party1", "target" })
    A.eq(_G.UnitIsUnit("target", "party1"), true)
    A.eq(Actors.get(w, "target"), ann)
    A.eq(Actors.get(w, ann.guid), ann)
  end)
end

local function test_setters_clamp_and_emit_only_on_change()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local seen = {}
    Combat.listen(w, "health", function(actor, old)
      seen[#seen + 1] = { actor, old }
    end)
    Actors.setHealth(w, ann, 1500)
    A.eq(ann.health, 1000)
    A.eq(#seen, 0) -- 1000 -> 1000 is not a change
    Actors.setHealth(w, ann, -20)
    A.eq(ann.health, 0)
    A.same({ #seen, seen[1][1] == ann, seen[1][2] }, { 1, true, 1000 })
    Actors.setHealth(w, ann, 0)
    A.eq(#seen, 1)
  end)
end

local function test_health_max_reclamps_health_and_emits_both()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local kinds = {}
    for _, kind in ipairs({ "health", "healthmax" }) do
      Combat.listen(w, kind, function(_, old)
        kinds[#kinds + 1] = kind .. ":" .. old
      end)
    end
    Actors.setHealthMax(w, ann, 400)
    A.same(kinds, { "healthmax:1000", "health:1000" })
    A.same({ ann.health, ann.healthMax }, { 400, 400 })
  end)
end

local function test_power_clamps_and_emits_the_power_type()
  H.withCombat("retail", function(w)
    local mage = Actors.add(w, { kind = "player", name = "M", power = 30, powerMax = 100 })
    local seen = {}
    Combat.listen(w, "power", function(actor, powerType)
      seen[#seen + 1] = { actor, powerType }
    end)
    Actors.setPower(w, mage, 250)
    A.eq(mage.power, 100)
    Actors.setPower(w, mage, 100)
    A.same({ #seen, seen[1][1] == mage, seen[1][2] }, { 1, true, "MANA" })
  end)
end

local function test_dead_flag_answers_unit_is_dead()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local deaths = 0
    Combat.listen(w, "death", function()
      deaths = deaths + 1
    end)
    A.eq(_G.UnitIsDead("party1"), false)
    Actors.setDead(w, ann, true)
    Actors.setDead(w, ann, true)
    A.same({ _G.UnitIsDead("party1"), _G.UnitIsDeadOrGhost("party1"), deaths }, { true, true, 1 })
    Actors.setDead(w, ann, false)
    A.eq(_G.UnitIsDead("party1"), false)
  end)
end

local function test_position_emits_moved_only_on_change()
  H.withCombat("retail", function(w)
    local _, brute = H.pair(w)
    local moves = 0
    Combat.listen(w, "moved", function()
      moves = moves + 1
    end)
    Actors.setPos(w, brute, 10, 5)
    Actors.setPos(w, brute, 10, 5)
    A.same({ brute.pos.x, brute.pos.y, moves }, { 10, 5, 1 })
  end)
end

local function test_unbind_removes_the_token()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    Actors.unbind(w, "party1")
    A.eq(_G.UnitExists("party1"), false)
    A.eq(Actors.get(w, "party1"), nil)
    A.eq(Actors.get(w, ann.guid), ann) -- still in the world, only unbound
  end)
end

local function test_remove_unbinds_every_token_and_emits_despawn()
  H.withCombat("retail", function(w, c)
    local ann = H.pair(w)
    Actors.bind(w, ann, "target")
    local order = {}
    Combat.listen(w, "despawn", function(actor)
      order[#order + 1] = #Actors.tokens(w, actor) -- the tokens still map while listeners run
    end)
    Actors.remove(w, ann)
    A.same(order, { 2 })
    A.same({ _G.UnitExists("party1"), _G.UnitExists("target"), c.actors[ann.guid] }, { false, false, nil })
  end)
end

local function test_add_emits_spawn_after_binding()
  H.withCombat("retail", function(w)
    local seen
    Combat.listen(w, "spawn", function(actor)
      seen = { actor.name, _G.UnitName("party1") }
    end)
    Actors.add(w, { kind = "player", name = "Ann", token = "party1" })
    A.same(seen, { "Ann", "Ann" })
  end)
end

local function test_add_rejects_an_unknown_kind()
  H.withCombat("retail", function(w)
    A.errors(function()
      Actors.add(w, { kind = "dragon", name = "X" })
    end, "unknown kind 'dragon'")
  end)
end

local function test_a_failing_listener_is_recorded_and_the_rest_still_run()
  H.withCombat("retail", function(w)
    local ann = H.pair(w)
    local ran = 0
    Combat.listen(w, "health", function()
      error("listener boom")
    end)
    Combat.listen(w, "health", function()
      ran = ran + 1
    end)
    Actors.setHealth(w, ann, 10)
    A.eq(ran, 1)
    A.eq(#w.errors, 1)
    A.contains(w.errors[1].message, "listener boom")
  end)
end

local function test_later_runs_once_under_blizzard_context_on_the_world_clock()
  H.withCombat("retail", function(w)
    local runs, context = 0, nil
    local timer = Combat.later(w, 2, function()
      runs = runs + 1
      context = w:context()
    end)
    A.truthy(timer)
    w:advance(1)
    A.eq(runs, 0)
    w:advance(1)
    A.same({ runs, context }, { 1, "blizzard" })
    w:advance(10)
    A.eq(runs, 1)
  end)
end

local function test_static_answers_unchanged_without_a_combat_world()
  H.withScenario("retail", function(w)
    A.eq(w.combat, nil)
    w:unit("target", { health = 5 })
    A.eq(_G.UnitHealth("target"), 5)
  end)
end

local function test_install_raises_without_a_scenario_world()
  local w = World.new({ flavor = "retail" })
  local ok, err = pcall(Combat.install, w)
  w:destroy()
  A.eq(ok, false)
  A.contains(err, "needs a Scenario world")
end

local function test_watch_logs_events_in_order_with_their_arguments()
  H.withCombat("retail", function(w)
    local log = H.watch(w, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    w:fire("PLAYER_REGEN_DISABLED")
    w:fire("PLAYER_REGEN_ENABLED")
    A.same(H.names(log), { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
    A.eq(log[1].n, 0)
  end)
end

return function()
  test_creature_guid_follows_the_client_format()
  test_player_and_pet_guid_formats_assumed()
  test_npc_id_defaults_to_1000_plus_the_sequence()
  test_unit_apis_answer_from_the_actor()
  test_hostility_fields_follow_the_hostile_flag()
  test_power_type_comes_from_the_enum()
  test_install_adopts_existing_fixtures_and_creates_the_player()
  test_install_twice_returns_the_same_world()
  test_one_actor_many_tokens_resolves_in_token_order()
  test_setters_clamp_and_emit_only_on_change()
  test_health_max_reclamps_health_and_emits_both()
  test_power_clamps_and_emits_the_power_type()
  test_dead_flag_answers_unit_is_dead()
  test_position_emits_moved_only_on_change()
  test_unbind_removes_the_token()
  test_remove_unbinds_every_token_and_emits_despawn()
  test_add_emits_spawn_after_binding()
  test_add_rejects_an_unknown_kind()
  test_a_failing_listener_is_recorded_and_the_rest_still_run()
  test_later_runs_once_under_blizzard_context_on_the_world_clock()
  test_static_answers_unchanged_without_a_combat_world()
  test_install_raises_without_a_scenario_world()
  test_watch_logs_events_in_order_with_their_arguments()
end
