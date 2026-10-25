-- SessionHost: the JSON boundary both hosts relay through: request decoding and null rules, the outbox that survives a
-- reload, and the located field on snapshot assets.
local A = require("assert")
local H = require("tests.helpers.session")
local Json = require("json")
local Saved = require("session_saved")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local function drained(host)
  return Json.decode(host:drain())
end

-- Replaces host.sess.handle with a recorder of the last request; returns a function that reads it.
local function spyOnHandle(host)
  local seen
  local real = host.sess.handle
  host.sess.handle = function(self, method, req, decorate)
    seen = req
    return real(self, method, req, decorate)
  end
  return function()
    return seen
  end
end

local function test_mutations_queue_a_snapshot_event()
  H.withHost(nil, function(host)
    host:drain()
    host:handleJson("fire", '{"event":"PLAYER_REGEN_DISABLED"}')
    A.same(drained(host), { { event = "snapshot", data = { seq = 1 } } })
    host:handleJson("snapshot", "{}")
    A.eq(#drained(host), 0)
  end)
end

local function test_drain_clears_the_outbox()
  H.withHost(nil, function(host)
    host:drain()
    host:handleJson("fire", '{"event":"PLAYER_REGEN_DISABLED"}')
    A.eq(#drained(host), 1)
    A.eq(#drained(host), 0)
    A.eq(host:drain(), "[]")
  end)
end

local function test_outbox_survives_a_reload_swap()
  H.withHost(nil, function(host)
    local before = host.sess
    host:drain()
    host:handleJson("fire", '{"event":"PLAYER_REGEN_DISABLED"}')
    local reply = Json.decode(host:handleJson("reload", "{}"))
    A.same(reply, { ok = true, loads = 2, flavor = "retail", screen = { width = 1920, height = 1080 } })
    A.truthy(host.sess ~= before)
    A.eq(host.sess.loads, 2)
    local events = drained(host)
    A.same({ events[1].event, events[2].event, events[3].event }, { "snapshot", "reload", "snapshot" })
    A.eq(events[1].data.seq, 1)
    A.eq(events[2].data.loads, 2)
    A.truthy(events[3].data.seq > 1)
  end)
end

local function test_fire_counts_trailing_nulls()
  H.withHost(nil, function(host)
    local seen = spyOnHandle(host)
    host:handleJson("fire", '{"event":"PLAYER_REGEN_DISABLED","args":[1,null,null]}')
    A.eq(seen().n, 3)
    A.eq(seen().args[1], 1)
    A.eq(seen().args[2], nil)
  end)
end

local function test_nulls_are_removed_outside_fire()
  H.withHost(nil, function(host)
    local seen = spyOnHandle(host)
    host:handleJson("state", '{"units":{"target":null},"mouseover":null}')
    A.eq(seen().units.target, nil)
    A.eq(seen().mouseover, nil)
  end)
end

local function test_malformed_json_replies_an_error()
  H.withHost(nil, function(host)
    local reply = Json.decode(host:handleJson("slash", "{"))
    A.eq(reply.ok, false)
    A.eq(reply.error:sub(1, #"malformed request: json:"), "malformed request: json:")
    A.eq(Json.decode(host:handleJson("slash", "[1]")).ok, false)
    A.eq(#drained(host), 0)
  end)
end

local function test_snapshot_assets_carry_located()
  local body = table.concat({
    'local f = CreateFrame("Frame", "TFrame", UIParent)',
    "f:SetSize(10, 10)",
    'f:SetPoint("CENTER")',
    "local t = f:CreateTexture()",
    "t:SetAllPoints()",
    't:SetTexture("Interface\\\\AddOns\\\\T\\\\pic")',
  }, "\n")
  local root = H.tempAddon("T", body, { ["pic.png"] = "" })
  H.withHost({ addonDir = root }, function(host)
    local snap = Json.decode(host:handleJson("snapshot", "{}"))
    A.same(snap.assets["path:interface/addons/t/pic"].located, { source = "addon", path = "pic.png" })
  end)
  H.withHost(nil, function(host)
    local snap = Json.decode(host:handleJson("snapshot", "{}"))
    local font = snap.assets["font:fonts/frizqt__.ttf"]
    A.truthy(font)
    A.eq(font.located, nil)
  end)
end

local function test_a_bad_reload_flavor_replies_an_error_and_keeps_the_session()
  H.withHost(nil, function(host)
    local before = host.sess
    host:drain()
    local reply = Json.decode(host:handleJson("reload", '{"flavor":"nope"}'))
    A.eq(reply.ok, false)
    A.contains(reply.error, "flavor")
    A.eq(host.sess, before)
    local events = drained(host)
    A.same({ #events, events[1].event, events[1].data.text }, { 1, "console", "Reload failed: " .. reply.error })
    A.eq(Json.decode(host:handleJson("slash", '{"text":"/sdemo alive"}')).handled, true)
  end)
end

local function test_console_lines_reach_the_outbox()
  H.withHost(nil, function(host)
    host:drain()
    host:handleJson("slash", '{"text":"/sdemo hi"}')
    local events = drained(host)
    A.eq(#events, 2)
    A.same(events[1], { event = "snapshot", data = { seq = 1 } })
    A.eq(events[2].event, "console")
    A.same({ events[2].data.kind, events[2].data.text }, { "print", "slash hi" })
    A.eq(type(events[2].data.seq), "number")
    host:handleJson("snapshot", "{}")
    A.eq(#drained(host), 0)
  end)
end

local function test_slash_reload_is_honoured_by_the_host()
  H.withHost(nil, function(host)
    host:handleJson("slash", '{"text":"/sdemo hi"}')
    host:drain()
    local reply = Json.decode(host:handleJson("slash", '{"text":"/reload"}'))
    A.same(reply, { ok = true, handled = true })
    A.eq(host.sess.loads, 2)
    A.eq(host.sess.pendingReload, nil)
    local names = {}
    for i, entry in ipairs(drained(host)) do
      names[i] = entry.event
    end
    A.contains(names, "reload")
    host:handleJson("slash", '{"text":"/sdemo again"}')
    local events = drained(host)
    A.eq(events[#events].data.text, "slash again")
  end)
end

local function test_a_failed_slash_reload_keeps_the_session_and_says_why()
  local Session = require("session")
  local real = Session.reload
  H.withHost(nil, function(host)
    local before = host.sess
    host:drain()
    Session.reload = function()
      error("cannot reload", 0)
    end
    local ok, text = pcall(host.handleJson, host, "slash", '{"text":"/reload"}')
    Session.reload = real
    A.truthy(ok, text)
    A.eq(host.sess, before)
    A.eq(host.sess.pendingReload, nil)
    local events = drained(host)
    A.same({ events[#events].event, events[#events].data.kind }, { "console", "system" })
    A.eq(events[#events].data.text, "Reload failed: cannot reload")
  end)
  Session.reload = real
end

-- Runs fn with Scenario.new raising "no world" for its next `failures` calls; Scenario.new is always restored.
local function withFailingWorlds(failures, fn)
  local Scenario = require("scenario")
  local real = Scenario.new
  Scenario.new = function(...)
    failures = failures - 1
    if failures >= 0 then
      error("no world", 0)
    end
    return real(...)
  end
  local ok, err = pcall(fn)
  Scenario.new = real
  if not ok then
    error(err, 0)
  end
end

local function test_a_reload_whose_world_fails_reopens_the_previous_options()
  H.withHost(nil, function(host)
    local before = host.sess
    local reply
    withFailingWorlds(1, function()
      reply = Json.decode(host:handleJson("reload", '{"flavor":"vanilla"}'))
    end)
    A.same(reply, { ok = false, error = "no world (reopened with the previous options)" })
    A.truthy(host.sess ~= before and not host.sess.closed)
    A.same({ host.sess.w.flavor, host.sess.loads }, { "retail", 2 })
    A.eq(Json.decode(host:handleJson("slash", '{"text":"/sdemo alive"}')).handled, true)
  end)
end

local function test_a_reload_that_cannot_rebuild_any_world_loses_the_session()
  H.withHost(nil, function(host)
    host:drain()
    local reply
    withFailingWorlds(2, function()
      reply = Json.decode(host:handleJson("reload", "{}"))
    end)
    A.same(reply, { ok = false, error = "session lost: no world" })
    A.same(Json.decode(host:handleJson("snapshot", "{}")), { ok = false, error = "session lost: no world" })
    A.eq(Json.decode(host:handleJson("slash", '{"text":"/sdemo hi"}')).error, "session lost: no world")
    local events = drained(host)
    A.same({ events[#events].event, events[#events].data.text }, { "console", "Reload failed: session lost: no world" })
  end)
end

local function test_a_lost_session_reloads_once_a_world_can_be_built_again()
  H.withHost(nil, function(host)
    withFailingWorlds(2, function()
      host:handleJson("reload", "{}")
    end)
    A.eq(Json.decode(host:handleJson("reload", '{"flavor":"nope"}')).ok, false)
    A.eq(Json.decode(host:handleJson("snapshot", "{}")).error, "session lost: no world")
    local reply = Json.decode(host:handleJson("reload", "{}"))
    A.same({ reply.ok, host.lost, host.sess.closed }, { true, nil, nil })
    A.eq(Json.decode(host:handleJson("slash", '{"text":"/sdemo alive"}')).handled, true)
  end)
end

-- A WtfDemo account file holding `WtfDemoDB = { n = <n> }`; returns its path.
local function accountFile(n)
  local path = Tmp.dir("wtfhost") .. "/acc.lua"
  fs.writeFile(path, "WtfDemoDB = { n = " .. n .. " }")
  return path
end

-- The names of the events in the outbox, console lines left out.
local function eventNames(host)
  local names = {}
  for _, entry in ipairs(drained(host)) do
    if entry.event ~= "console" then
      names[#names + 1] = entry.event
    end
  end
  return names
end

local function test_wtf_import_copies_once()
  local dir, acc = Tmp.dir("wtfsession"), accountFile(1)
  H.withHost({ addonDir = H.WTF, sessionDir = dir, wtf = { account = acc } }, function(host)
    A.eq(host.wtf.account, acc)
    A.same(Saved.read(dir), { WtfDemoDB = { n = 1 } })
    A.eq(_G.WtfDemoDB.n, 1)
  end)
  fs.writeFile(acc, "WtfDemoDB = { n = 5 }")
  H.withHost({ addonDir = H.WTF, sessionDir = dir, wtf = { account = acc } }, function()
    A.eq(_G.WtfDemoDB.n, 1)
  end)
end

local function test_reimport_overwrites_and_discards_live_changes()
  local dir, acc = Tmp.dir("wtfsession"), accountFile(1)
  H.withHost({ addonDir = H.WTF, sessionDir = dir, wtf = { account = acc } }, function(host)
    host:handleJson("slash", '{"text":"/run WtfDemoDB.n = 99"}')
    A.eq(_G.WtfDemoDB.n, 99)
    fs.writeFile(acc, "WtfDemoDB = { n = 7 }")
    host:drain()
    local reply = Json.decode(host:handleJson("reimport", "{}"))
    A.same({ reply.ok, reply.loads, reply.warnings }, { true, 2, 0 })
    A.eq(_G.WtfDemoDB.n, 7)
    A.same(Saved.read(dir), { WtfDemoDB = { n = 7 } })
    A.same(eventNames(host), { "reload", "snapshot" })
  end)
end

local function test_reimport_without_wtf_replies_an_error()
  H.withHost(nil, function(host)
    A.same(Json.decode(host:handleJson("reimport", "{}")), { ok = false, error = "no WTF folder picked" })
  end)
end

local function test_reimport_needs_a_session_folder()
  local SessionHost = require("session_host")
  local host = SessionHost.new({ addonDir = H.WTF, flavor = "retail", wtf = { account = accountFile(1) } })
  local reply = Json.decode(host:handleJson("reimport", "{}"))
  host:shutdown()
  A.same(reply, { ok = false, error = "no session folder" })
end

local function test_wtf_warnings_reach_the_console()
  local acc = accountFile(1)
  fs.writeFile(acc, "WtfDemoDB = {")
  H.withHost({ addonDir = H.WTF, wtf = { account = acc } }, function(host)
    local first
    for _, entry in ipairs(drained(host)) do
      first = first or (entry.event == "console" and entry.data.text:sub(1, 4) == "wtf:" and entry.data.text)
    end
    A.truthy(first, "no wtf: console line")
  end)
end

local function test_a_lost_session_accepts_reimport()
  H.withHost({ addonDir = H.WTF, wtf = { account = accountFile(3) } }, function(host)
    withFailingWorlds(2, function()
      host:handleJson("reload", "{}")
    end)
    A.truthy(host.lost)
    local reply = Json.decode(host:handleJson("reimport", "{}"))
    A.same({ reply.ok, host.lost }, { true, nil })
    A.eq(_G.WtfDemoDB.n, 3)
  end)
end

return function()
  test_a_reload_whose_world_fails_reopens_the_previous_options()
  test_a_reload_that_cannot_rebuild_any_world_loses_the_session()
  test_a_lost_session_reloads_once_a_world_can_be_built_again()
  test_console_lines_reach_the_outbox()
  test_slash_reload_is_honoured_by_the_host()
  test_a_failed_slash_reload_keeps_the_session_and_says_why()
  test_mutations_queue_a_snapshot_event()
  test_drain_clears_the_outbox()
  test_outbox_survives_a_reload_swap()
  test_fire_counts_trailing_nulls()
  test_nulls_are_removed_outside_fire()
  test_malformed_json_replies_an_error()
  test_snapshot_assets_carry_located()
  test_a_bad_reload_flavor_replies_an_error_and_keeps_the_session()
  test_wtf_import_copies_once()
  test_reimport_overwrites_and_discards_live_changes()
  test_reimport_without_wtf_replies_an_error()
  test_reimport_needs_a_session_folder()
  test_wtf_warnings_reach_the_console()
  test_a_lost_session_accepts_reimport()
end
