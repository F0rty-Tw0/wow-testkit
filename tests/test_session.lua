-- Session: one addon logged into a world and driven by wire requests (input, fire, slash, state), snapshots with the
-- session block, and errors that become replies instead of raises.
local A = require("assert")
local H = require("tests.helpers.session")
local Json = require("json")
local Session = require("session")

local function textOf(sess)
  return H.item(sess:call("snapshot"), "SessionDemoText").text
end

local function test_new_loads_the_addon_and_snapshots()
  H.withSession(nil, function(sess)
    local snap = sess:call("snapshot")
    A.eq(snap.ver, 1)
    A.eq(snap.session.addon, "SessionDemo")
    A.eq(snap.session.flavor, "retail")
    A.eq(snap.session.seq, 0)
    A.eq(snap.session.loads, 1)
    A.eq(snap.session.screen.width, 1920)
    A.truthy(H.item(snap, "SessionDemoFrame"))
    local label = H.item(snap, "SessionDemoText")
    A.eq(label.kind, "fontstring")
    A.eq(label.text, "idle")
  end)
end

local function test_click_by_id_toggles_a_check_button()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local reply = sess:call("input", { kind = "click", target = H.id(sess, "ClickyCheck") })
    A.eq(reply.ok, true)
    A.eq(reply.target.name, "ClickyCheck")
    A.eq(H.item(sess:call("snapshot"), "ClickyCheck").widget.checked, true)
    A.eq(sess:call("input", { kind = "click", target = "ClickyCheck" }).ok, true)
    A.eq(H.item(sess:call("snapshot"), "ClickyCheck").widget.checked, false)
  end)
end

local function test_click_at_a_point_hits_the_topmost_frame()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local reply = sess:call("input", { kind = "click", target = { x = 960, y = 540 } })
    A.eq(reply.ok, true)
    A.eq(reply.target.name, "ClickyCheck")
    A.same(sess:call("input", { kind = "click", target = { x = 1500, y = 900 } }), { ok = true })
    A.eq(sess:call("input", { kind = "type", target = { x = 1500, y = 900 }, text = "x" }).reason, "nothing at 1500, 900")
  end)
end

local function test_blocked_input_reports_the_reason()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    local blocked = sess:call("input", { kind = "click", target = "ClickyPanel" })
    A.eq(blocked.ok, false)
    A.eq(blocked.reason, "mouse disabled")
    A.eq(sess:call("input", { kind = "click", target = "f99999" }).reason, "unknown target f99999")
    local unknown = sess:call("input", { kind = "dance", target = "ClickyCheck" })
    A.eq(unknown.ok, false)
    A.contains(unknown.reason, "unknown input kind")
    A.eq(sess.seq, 0)
  end)
end

local function test_enter_and_leave_move_the_mouse()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    A.eq(sess:call("input", { kind = "enter", target = "ClickyCheck" }).ok, true)
    local misplaced = sess:call("input", { kind = "leave", target = "ClickyButton" })
    A.eq(misplaced.ok, false)
    A.contains(misplaced.reason, "does not have the mouse")
    A.eq(sess:call("input", { kind = "leave", target = "ClickyCheck" }).ok, true)
    A.same({ sess.s.ns.log[1], sess.s.ns.log[2] }, { "ClickyCheck:enter:true", "ClickyCheck:leave:true" })
  end)
end

local function test_type_and_press_reach_the_edit_box()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    A.eq(sess:call("input", { kind = "type", target = "ClickyBox", text = "hi" }).ok, true)
    A.eq(sess:call("input", { kind = "press", target = "ClickyBox", key = "ENTER" }).ok, true)
    local log = sess.s.ns.log
    A.same({ log[#log - 1], log[#log] }, { "ClickyBox:text:hi:true", "ClickyBox:enter-pressed:hi" })
  end)
end

local function test_malformed_input_replies_errors()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    A.contains(sess:call("input", { kind = "type", target = "ClickyBox" }).error, "text must be a string")
    A.contains(sess:call("input", { kind = "press", target = "ClickyBox", key = "ENTER" }).reason, "does not have focus")
    sess:call("input", { kind = "type", target = "ClickyBox", text = "x" })
    A.contains(sess:call("input", { kind = "press", target = "ClickyBox", key = "F13" }).error, "unknown key")
    A.contains(sess:call("input", { kind = "click" }).error, "target")
  end)
end

local function test_fire_runs_OnEvent_and_unknown_events_reply_errors()
  H.withSession(nil, function(sess)
    A.eq(sess:call("fire", { event = "PLAYER_REGEN_DISABLED", args = {}, n = 0 }).ok, true)
    A.eq(textOf(sess), "event:PLAYER_REGEN_DISABLED")
    local reply = sess:call("fire", { event = "NOPE" })
    A.eq(reply.ok, false)
    A.contains(reply.error, "unknown event")
  end)
end

local function test_slash_runs_handlers_and_reports_unknown_commands()
  H.withSession(nil, function(sess)
    local reply = sess:call("slash", { text = "/sdemo hi" })
    A.eq(reply.ok, true)
    A.eq(reply.handled, true)
    A.eq(textOf(sess), "slash:hi")
    A.eq(sess:call("slash", { text = "/nope" }).handled, false)
    A.eq(sess:call("slash", { text = "/sdemo boom" }).ok, true)
    A.contains(sess:call("snapshot").errors[1].message, "boom")
  end)
end

local function test_state_sets_units_and_mouseover()
  H.withSession(nil, function(sess)
    local reply = sess:call("state", { units = { target = { name = "Bob" } }, mouseover = "target" })
    A.eq(reply.ok, true)
    A.eq(_G.UnitName("target"), "Bob")
    A.eq(_G.UnitName("mouseover"), "Bob")
  end)
end

local function test_seq_counts_mutations_only()
  H.withSession({ addonDir = H.CLICKY }, function(sess)
    sess:call("input", { kind = "click", target = "ClickyCheck" })
    A.eq(sess.seq, 1)
    sess:call("fire", { event = "PLAYER_REGEN_DISABLED" })
    A.eq(sess.seq, 2)
    sess:call("slash", { text = "/nope" })
    A.eq(sess.seq, 3)
    sess:call("state", { mouseover = "target" })
    A.eq(sess.seq, 4)
    sess:call("snapshot")
    sess:call("info")
    A.eq(sess.seq, 4)
    A.eq(sess:call("snapshot").session.seq, 4)
  end)
end

local function test_info_reports_the_session_block()
  H.withSession(nil, function(sess)
    local info = sess:call("info")
    A.eq(info.ok, true)
    A.eq(info.addon, "SessionDemo")
    A.eq(info.loads, 1)
    A.truthy(#info.flavors > 1)
  end)
end

local function test_handle_never_raises()
  H.withSession(nil, function(sess)
    local reply = Json.decode(sess:handle("nope", {}))
    A.eq(reply.ok, false)
    A.contains(reply.error, "unknown method")
    A.eq(Json.decode(sess:handle("snapshot", {})).ver, 1)
    A.eq(Json.decode(sess:handle("fire", { event = 5 })).ok, false)
  end)
end

local function test_a_skipped_addon_is_an_empty_world_not_a_raise()
  local root = H.tempAddon("Skippy", 'CreateFrame("Frame", "SkippyFrame", UIParent)', { ["Skippy.toc"] = "## Interface-Vanilla: 11509\nMain.lua\n" })
  H.withSession({ addonDir = root }, function(sess)
    local snap = sess:call("snapshot")
    A.eq(snap.session.skipped, "not declared")
    A.eq(H.item(snap, "SkippyFrame"), nil)
  end)
end

local function test_a_folder_without_a_toc_is_a_recorded_error()
  H.withSession({ addonDir = H.DEMO .. "/.." }, function(sess)
    local snap = sess:call("snapshot")
    A.contains(snap.errors[1].message, "cannot tell which TOC")
  end)
end

local function test_reload_swaps_in_a_fresh_world_and_counts_loads()
  H.withSession(nil, function(sess)
    sess:call("slash", { text = "/sdemo hi" })
    local fresh = Session.reload(sess, nil)
    local ok, err = pcall(function()
      A.eq(fresh.loads, 2)
      A.truthy(fresh.seq > sess.seq)
      A.eq(textOf(fresh), "idle")
    end)
    fresh:shutdown()
    if not ok then
      error(err, 0)
    end
  end)
end

-- The world is single and global: if the old one were destroyed first, its addon's slash command would be gone.
local function test_reload_with_an_unusable_option_keeps_the_session_whole()
  H.withSession(nil, function(sess)
    A.errors(function()
      Session.reload(sess, { flavor = "nope" })
    end, "flavor")
    A.errors(function()
      Session.reload(sess, { screen = { width = -1 } })
    end, "opts.screen.width")
    A.eq(sess:call("slash", { text = "/sdemo alive" }).handled, true)
    A.eq(textOf(sess), "slash:alive")
  end)
end

return function()
  test_new_loads_the_addon_and_snapshots()
  test_click_by_id_toggles_a_check_button()
  test_click_at_a_point_hits_the_topmost_frame()
  test_blocked_input_reports_the_reason()
  test_enter_and_leave_move_the_mouse()
  test_type_and_press_reach_the_edit_box()
  test_malformed_input_replies_errors()
  test_fire_runs_OnEvent_and_unknown_events_reply_errors()
  test_slash_runs_handlers_and_reports_unknown_commands()
  test_state_sets_units_and_mouseover()
  test_seq_counts_mutations_only()
  test_info_reports_the_session_block()
  test_handle_never_raises()
  test_a_skipped_addon_is_an_empty_world_not_a_raise()
  test_a_folder_without_a_toc_is_a_recorded_error()
  test_reload_swaps_in_a_fresh_world_and_counts_loads()
  test_reload_with_an_unusable_option_keeps_the_session_whole()
end
