-- SessionHost: the JSON boundary both hosts relay through: request decoding and null rules, the outbox that survives a
-- reload, and the located field on snapshot assets.
local A = require("assert")
local H = require("tests.helpers.session")
local Json = require("json")

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
    local reply = Json.decode(host:handleJson("reload", '{"flavor":"nope"}'))
    A.eq(reply.ok, false)
    A.contains(reply.error, "flavor")
    A.eq(host.sess, before)
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

return function()
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
end
