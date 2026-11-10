-- Sim keys: s:key drives Keys.down and Keys.up, the fallback commands and default keys of SimKeys.install, and the
-- K3 rule that a command runs on down and a runOnUp one also on up.
local A = require("assert")
local Bindings = require("bindings")
local H = require("tests.helpers.sim")
local Keys = require("input_keys")
local Scenario = require("scenario")
local Sim = require("sim")
local SP = require("tests.helpers.sim_spells")

local DEFAULT_KEYS = {
  W = "MOVEFORWARD",
  S = "MOVEBACKWARD",
  A = "TURNLEFT",
  D = "TURNRIGHT",
  Q = "STRAFELEFT",
  E = "STRAFERIGHT",
  NUMLOCK = "TOGGLEAUTORUN",
  TAB = "TARGETNEARESTENEMY",
  B = "OPENALLBAGS",
  ESCAPE = "TOGGLEGAMEMENU",
}
local ACTION_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }

local function keyboardFrame(propagate)
  local seen = { down = 0, up = 0 }
  local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
  frame:EnableKeyboard(true)
  frame:SetPropagateKeyboardInput(propagate)
  frame:SetScript("OnKeyDown", function()
    seen.down = seen.down + 1
  end)
  frame:SetScript("OnKeyUp", function()
    seen.up = seen.up + 1
  end)

  return seen
end

local function test_default_keys_name_their_commands_assumed()
  H.each({}, function()
    for key, command in pairs(DEFAULT_KEYS) do
      A.eq(_G.GetBindingAction(key), command, key)
    end
    for i, key in ipairs(ACTION_KEYS) do
      A.eq(_G.GetBindingAction(key), "ACTIONBUTTON" .. i, key)
    end
  end)
end

-- source: confirmed (retail 70575 bindings_standard.xml:79,990,1200,1221) movement, action buttons and
-- TARGETNEARESTENEMY are runOnUp; TOGGLEAUTORUN, OPENALLBAGS and TOGGLEGAMEMENU are not.
local function test_movement_commands_run_on_up_and_toggles_do_not()
  H.withSim("retail", {}, function(w)
    local commands = w.bindings.commands
    A.eq(commands.MOVEFORWARD.runOnUp, true)
    A.eq(commands.ACTIONBUTTON12.runOnUp, true)
    A.eq(commands.TARGETNEARESTENEMY.runOnUp, true)
    A.eq(commands.OPENALLBAGS.runOnUp or false, false)
    A.eq(commands.TOGGLEAUTORUN.runOnUp or false, false)
    A.eq(commands.TOGGLEGAMEMENU.runOnUp or false, false)
  end)
end

local function test_a_toggle_runs_once_per_press()
  H.each({}, function(_, s)
    local calls = 0
    _G.ToggleAllBags = function()
      calls = calls + 1
    end
    s:key("B", "down")
    s:key("B", "up")
    A.eq(calls, 1)
  end)
end

local function test_a_missing_global_does_nothing()
  H.withSim("retail", {}, function(w, s)
    _G.ToggleAllBags = nil
    s:key("B", "down")
    s:key("B", "up")
    s:key("1", "down")
    s:key("1", "up")
    A.same(w.errors, {})
  end)
end

local function test_action_button_keys_call_down_then_up()
  H.withSim("retail", {}, function(_, s)
    local log = {}
    _G.ActionButtonDown = function(n)
      log[#log + 1] = "down" .. n
    end
    _G.ActionButtonUp = function(n)
      log[#log + 1] = "up" .. n
    end
    s:key("3", "down")
    s:key("3", "up")
    A.same(log, { "down3", "up3" })
  end)
end

-- source: assumed (spec 7.6) a world without Blizzard's ActionButtonDown presses the bar's slot by UseAction on key down.
local function test_an_action_key_uses_the_slot_when_blizzards_action_button_is_missing()
  local strike = SP.record({ effects = { { type = "damage", base = 7, target = "enemy" } } })
  SP.withSpells("retail", { strike }, function(w, s, player)
    _G.ActionButtonDown, _G.ActionButtonUp = nil, nil
    w.mock.actions[1] = { type = "spell", id = strike.id }
    local foe = SP.target(w, player)
    s:key("1", "down")
    A.eq(SP.hitsOn(w, "SPELL_DAMAGE", foe.guid), 1)
    s:key("1", "up")
    A.same({ SP.hitsOn(w, "SPELL_DAMAGE", foe.guid), w.errors }, { 1, {} })
  end)
end

local function test_target_nearest_enemy_runs_on_down_only()
  H.withSim("retail", {}, function(_, s)
    local calls = 0
    _G.TargetNearestEnemy = function()
      calls = calls + 1
    end
    s:key("TAB", "down")
    s:key("TAB", "up")
    A.eq(calls, 1)
  end)
end

local function test_walk_key_moves_until_released()
  H.each({}, function(_, s, flavor)
    local seen = H.recordMoves()
    local p = s.w.sim.player
    s:key("W", "down")
    s:simStep(1)
    H.near(p.pos.y, -3, flavor)
    s:key("W", "up")
    s:simStep(1)
    H.near(p.pos.y, -3, flavor)
    A.same(seen, { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" })
  end)
end

local function test_every_move_key_sets_its_intent()
  H.withSim("retail", {}, function(w, s)
    local intents = { S = "backward", A = "turnLeft", D = "turnRight", Q = "strafeLeft", E = "strafeRight" }
    for key, intent in pairs(intents) do
      s:key(key, "down")
      A.eq(w.sim.intents[intent], true, key)
      s:key(key, "up")
      A.eq(w.sim.intents[intent], nil, key)
    end
  end)
end

local function test_autorun_key_toggles_once_per_press()
  H.withSim("retail", {}, function(w, s)
    s:key("NUMLOCK", "down")
    s:key("NUMLOCK", "up")
    A.eq(w.sim.intents.autorun, true)
    s:key("NUMLOCK", "down")
    s:key("NUMLOCK", "up")
    A.eq(w.sim.intents.autorun, nil)
  end)
end

-- source: assumed (spec 7.6) Esc cancels a cast or the targeting mode first and opens the menu only when neither was there,
-- as Blizzard's own handler does (SpellStopCasting() or SpellStopTargeting()).
local function test_escape_stops_a_cast_or_targeting_before_the_menu()
  H.withSim("retail", {}, function(_, s)
    local calls, answers = {}, { casting = false, targeting = false }
    _G.SpellStopCasting = function()
      calls[#calls + 1] = "casting"

      return answers.casting
    end
    _G.SpellStopTargeting = function()
      calls[#calls + 1] = "targeting"

      return answers.targeting
    end
    _G.ToggleGameMenu = function()
      calls[#calls + 1] = "menu"
    end
    s:key("ESCAPE", "down")
    s:key("ESCAPE", "up")
    A.same(calls, { "casting", "targeting", "menu" })
    calls, answers.targeting = {}, true
    s:key("ESCAPE", "down")
    s:key("ESCAPE", "up")
    A.same(calls, { "casting", "targeting" })
    calls, answers.casting = {}, true
    s:key("ESCAPE", "down")
    s:key("ESCAPE", "up")
    A.same(calls, { "casting" })
  end)
end

-- source: assumed (K3) the up half is the command the down resolved, so a modifier changed in between does not matter.
local function test_key_up_ignores_the_modifiers_it_is_given()
  H.withSim("retail", {}, function(w, s)
    s:key("W", "down", {})
    A.eq(w.sim.intents.forward, true)
    s:key("W", "up", { shift = true })
    A.eq(w.sim.intents.forward, nil)
    A.same({ _G.IsShiftKeyDown(), _G.IsControlKeyDown(), _G.IsAltKeyDown() }, { false, false, false })
  end)
end

local function test_modifiers_are_held_while_the_key_runs()
  H.withSim("retail", {}, function(w, s)
    local seen
    _G.TargetNearestEnemy = function()
      seen = _G.IsShiftKeyDown()
    end
    s:key("TAB", "down", { shift = true })
    A.eq(seen, nil, "SHIFT-TAB is not TAB")
    s:key("TAB", "up", { shift = true })
    A.eq(w.mock.modifiers.shift, nil)
  end)
end

local function test_a_held_key_ignores_a_second_down()
  H.withSim("retail", {}, function(w, s)
    local seen = keyboardFrame(true)
    A.eq(Keys.down(w, "W", {}).binding, "MOVEFORWARD")
    A.eq(Keys.down(w, "W", {}).ignored, true)
    A.eq(seen.down, 1)
    s:key("W", "up")
    A.eq(seen.up, 1)
    A.eq(Keys.down(w, "W", {}).ignored, nil, "released, so it can go down again")
    Keys.up(w, "W")
  end)
end

local function test_key_up_without_a_down_runs_nothing()
  H.withSim("retail", {}, function(w)
    local seen = keyboardFrame(true)
    local reply = Keys.up(w, "W")
    A.same({ reply.binding, reply.consumedBy }, {})
    A.eq(seen.up, 0)
    A.eq(w.sim.intents.forward, nil)
  end)
end

local function test_a_frame_that_stops_the_key_keeps_the_player_still()
  H.withSim("retail", {}, function(w, s)
    local seen = keyboardFrame(false)
    local reply = Keys.down(w, "W", {})
    A.truthy(reply.consumedBy, "a frame stopped it")
    A.eq(reply.binding, nil)
    A.eq(w.sim.intents.forward, nil)
    s:key("W", "up")
    A.eq(seen.up, 1, "its OnKeyUp still ran")
    A.eq(w.sim.intents.forward, nil)
  end)
end

local function test_press_is_down_then_up()
  H.withSim("retail", {}, function(w)
    local reply = Keys.press(w, "W", {})
    A.eq(reply.binding, "MOVEFORWARD")
    A.eq(w.sim.intents.forward, nil)
    A.eq(w.input.heldKeys.W, nil)
  end)
end

local function test_a_focused_edit_box_takes_the_whole_key()
  H.withSim("retail", {}, function(w)
    local box = _G.CreateFrame("EditBox", nil, _G.UIParent)
    box:SetFocus()
    local reply = Keys.down(w, "W", {})
    A.eq(reply.consumedBy, box)
    A.eq(w.input.heldKeys.W, nil, "nothing is held")
    A.eq(w.sim.intents.forward, nil)
  end)
end

local function test_a_user_binding_wins_over_a_default()
  H.withSim("retail", {}, function(w)
    _G.SetBinding("W", "USERCMD")
    Sim.restore(w, nil)
    A.eq(_G.GetBindingAction("W"), "USERCMD")
    A.eq(_G.GetBindingAction("Q"), "STRAFELEFT")
  end)
end

local function test_blizzards_command_wins_over_the_fallback()
  H.withSim("retail", {}, function(w, s)
    local xml = '<Bindings><Binding name="MOVEFORWARD" runOnUp="true">Marker = keystate</Binding></Bindings>'
    Bindings.loadXml(w, xml, "Blizzard_FrameXML")
    s:key("W", "down")
    A.eq(_G.Marker, "down")
    s:key("W", "up")
    A.eq(_G.Marker, "up")
    A.eq(w.sim.player.pos.y, -10)
    Sim.restore(w, nil)
    _G.Marker = nil
    s:key("W", "down")
    A.eq(_G.Marker, "down", "a second restore leaves Blizzard's command be")
    s:key("W", "up")
  end)
end

local function test_two_phase_installs_the_keys_on_restore()
  local s = Scenario.new({ addon = "T", root = "T", flavor = "retail", sim = { twoPhase = true } })
  A.eq(_G.GetBindingAction("W"), "")
  Sim.restore(s.w, nil)
  A.eq(_G.GetBindingAction("W"), "MOVEFORWARD")
  s.w:destroy()
end

local function test_key_needs_a_sim_world_and_a_state()
  local plain = Scenario.new({ addon = "T", root = "T", flavor = "retail" })
  A.errors(function()
    plain:key("W", "down")
  end, "needs Scenario.new { sim = true }")
  plain.w:destroy()
  H.withSim("retail", {}, function(_, s)
    A.errors(function()
      s:key("W", "sideways")
    end, "down")
  end)
end

return function()
  test_default_keys_name_their_commands_assumed()
  test_movement_commands_run_on_up_and_toggles_do_not()
  test_a_toggle_runs_once_per_press()
  test_a_missing_global_does_nothing()
  test_action_button_keys_call_down_then_up()
  test_an_action_key_uses_the_slot_when_blizzards_action_button_is_missing()
  test_target_nearest_enemy_runs_on_down_only()
  test_walk_key_moves_until_released()
  test_every_move_key_sets_its_intent()
  test_autorun_key_toggles_once_per_press()
  test_escape_stops_a_cast_or_targeting_before_the_menu()
  test_key_up_ignores_the_modifiers_it_is_given()
  test_modifiers_are_held_while_the_key_runs()
  test_a_held_key_ignores_a_second_down()
  test_key_up_without_a_down_runs_nothing()
  test_a_frame_that_stops_the_key_keeps_the_player_still()
  test_press_is_down_then_up()
  test_a_focused_edit_box_takes_the_whole_key()
  test_a_user_binding_wins_over_a_default()
  test_blizzards_command_wins_over_the_fallback()
  test_two_phase_installs_the_keys_on_restore()
  test_key_needs_a_sim_world_and_a_state()
end
