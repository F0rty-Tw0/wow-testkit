local A = require("assert")
local H = require("tests.helpers.session")
local SH = require("tests.helpers.sim_combat")

-- Clicky: button at {960,490}; empty space {1500,900} (tests/test_session_input.lua header).
local function test_session_pointer_applies_world_only_over_empty_space()
  local BUTTON, EMPTY = { x = 960, y = 490 }, { x = 1500, y = 900 }
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    local foe = SH.foe(sess.w, 0, 10)
    local world = { guid = foe.guid }
    sess:call("input", { kind = "enter", target = EMPTY, world = world })
    A.eq(_G.UnitGUID("mouseover"), foe.guid)
    sess:call("input", { kind = "enter", target = BUTTON, world = world }) -- a frame is under the point
    A.eq(_G.UnitExists("mouseover"), false)
    sess:call("input", { kind = "click", target = BUTTON, world = world })
    A.eq(_G.UnitExists("target"), false)
    sess:call("input", { kind = "click", target = EMPTY, world = world })
    A.eq(_G.UnitGUID("target"), foe.guid)
    local bad = sess:call("input", { kind = "click", target = EMPTY, world = { guid = 5 } })
    A.contains(bad.error, "input: world.guid must be a string")
  end)
end

local function test_session_world_rejects_a_malformed_ground()
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    local reply = sess:call("input", { kind = "click", target = { x = 1500, y = 900 }, world = { ground = { x = 1 } } })
    A.contains(reply.error, "input: world.ground needs numbers x and y")
  end)
end

local function test_session_reload_keeps_the_world_pointer_working()
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    SH.reloaded(sess, function(fresh)
      local foe = SH.foe(fresh.w, 0, 10)
      fresh:call("input", { kind = "click", target = { x = 1500, y = 900 }, world = { guid = foe.guid } })
      A.eq(_G.UnitGUID("target"), foe.guid)
    end)
  end)
end

return function()
  test_session_pointer_applies_world_only_over_empty_space()
  test_session_world_rejects_a_malformed_ground()
  test_session_reload_keeps_the_world_pointer_working()
end
