-- Session flavours and screens: the flavor "auto" picks from the TOC, and a reload through the host can change the
-- flavor or the screen size (a preset or WxH) while keeping SavedVariables and mock state; a bad request changes nothing.
local A = require("assert")
local H = require("tests.helpers.session")
local Json = require("json")
local Session = require("session")

local RETAIL_ONLY = H.DEMO .. "/../RetailOnly"

local function call(host, method, req)
  return Json.decode(host:handleJson(method, Json.encode(req or {})))
end

local function tocOnly(name, toc)
  return H.tempAddon(name, "", { [name .. ".toc"] = toc })
end

local function test_auto_flavor_picks_the_flavor_the_toc_declares()
  A.eq(Session.autoFlavor(H.CLICKY), "retail")
  A.eq(Session.autoFlavor(tocOnly("OnlyVanilla", "## Interface-Vanilla: 11509\nMain.lua\n")), "vanilla")
  -- 20000 is an older TBC build: outdated there, not declared anywhere else.
  A.eq(Session.autoFlavor(tocOnly("OldTbc", "## Interface: 20000\nMain.lua\n")), "tbc")
  A.eq(Session.autoFlavor(tocOnly("NoInterface", "## Title: NoInterface\nMain.lua\n")), "retail")
end

local function test_new_with_auto_uses_the_detected_flavor()
  local root = tocOnly("AutoVanilla", "## Interface-Vanilla: 11509\nMain.lua\n")
  H.withSession({ addonDir = root, flavor = "auto" }, function(sess)
    A.eq(sess:call("info").flavor, "vanilla")
    A.eq(sess:call("info").skipped, nil)
  end)
end

local function test_reload_with_a_flavor_rebuilds_the_world()
  H.withHost(nil, function(host)
    A.eq(call(host, "state", { combat = true }).ok, true)
    local reply = call(host, "reload", { flavor = "vanilla" })
    A.same(reply, { ok = true, loads = 2, flavor = "vanilla", screen = { width = 1920, height = 1080 } })
    local snap = call(host, "snapshot")
    A.eq(snap.session.flavor, "vanilla")
    A.eq(snap.session.loads, 2)
    A.eq(_G.SessionDemoDB.runs, 2)
    A.eq(call(host, "state").state.combat, true)
  end)
end

local function test_reload_with_a_preset_changes_the_screen()
  H.withHost(nil, function(host)
    local reply = call(host, "reload", { size = "4k" })
    A.same(reply.screen, { width = 3840, height = 2160 })
    local snap = call(host, "snapshot")
    A.eq(snap.screen.width, 3840)
    A.eq(snap.session.screen.height, 2160)
    local rect = H.item(snap, "SessionDemoFrame").rect
    A.same({ rect.x, rect.y }, { 1820, 1050 })
    A.eq(snap.session.flavor, "retail")
  end)
end

local function test_reload_with_a_custom_size_and_auto()
  H.withHost(nil, function(host)
    local reply = call(host, "reload", { flavor = "auto", size = { width = 2560, height = 1440 } })
    A.same({ reply.ok, reply.flavor, reply.screen.width, reply.screen.height }, { true, "retail", 2560, 1440 })
    reply = call(host, "reload", { screen = { width = 1280, height = 720 } })
    A.same({ reply.ok, reply.screen.width, reply.screen.height }, { true, 1280, 720 })
  end)
end

local function test_bad_reload_requests_leave_the_session_alone()
  H.withHost(nil, function(host)
    local before = host.sess
    local bad = {
      { flavor = "pandaria" },
      { flavor = 3 },
      { size = "8k" },
      { size = { width = 100, height = 100 } },
      { size = { width = 7681, height = 1080 } },
      { size = { width = 1920.5, height = 1080 } },
      { size = { width = 1920 } },
      { size = 1080 },
      { screen = { width = 100, height = 100 } },
      { screen = { width = 1920, height = 4321 } },
      { screen = { width = 1920.5, height = 1080 } },
      { screen = "4k" },
    }
    for _, req in ipairs(bad) do
      local reply = call(host, "reload", req)
      A.eq(reply.ok, false, Json.encode(req))
      A.truthy(reply.error and reply.error ~= "", Json.encode(req))
    end
    A.eq(host.sess, before)
    local snap = call(host, "snapshot")
    A.eq(snap.session.loads, 1)
    A.eq(snap.screen.width, 1920)
    A.eq(call(host, "slash", { text = "/sdemo alive" }).handled, true)
  end)
end

local function test_skipped_addon_keeps_the_session_alive()
  H.withHost({ addonDir = RETAIL_ONLY }, function(host)
    local reply = call(host, "reload", { flavor = "vanilla" })
    A.eq(reply.ok, true)
    local snap = call(host, "snapshot")
    for _, item in ipairs(snap.items) do
      A.truthy(item.name == "UIParent" or item.name == "WorldFrame", tostring(item.name))
    end
    A.eq(snap.session.flavor, "vanilla")
    A.truthy(type(snap.session.skipped) == "string" and snap.session.skipped ~= "")
    A.eq(call(host, "input", { kind = "click", target = { x = 10, y = 10 } }).ok, true)
    A.eq(call(host, "fire", { event = "PLAYER_REGEN_DISABLED" }).ok, true)
  end)
end

return function()
  test_auto_flavor_picks_the_flavor_the_toc_declares()
  test_new_with_auto_uses_the_detected_flavor()
  test_reload_with_a_flavor_rebuilds_the_world()
  test_reload_with_a_preset_changes_the_screen()
  test_reload_with_a_custom_size_and_auto()
  test_bad_reload_requests_leave_the_session_alone()
  test_skipped_addon_keeps_the_session_alive()
end
