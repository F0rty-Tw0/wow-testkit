-- Player safety: mobs cannot kill the sim player (health floor 1, spec 5.7) and the floor survives a reload.
local A = require("assert")
local H = require("tests.helpers.session")
local SH = require("tests.helpers.sim_combat")
local SimMobs = require("sim_mobs")

local function test_mob_hits_cannot_kill_the_player_and_the_floor_survives_a_reload()
  H.withSession({ addonDir = H.CLICKY, sim = {} }, function(sess)
    local w = sess.w
    local player = w.sim.player
    player.health = 5
    SimMobs.spawn(w, { pos = { x = 0, y = -2 } }) -- in range: swings 3 at ~2.02 s and ~4.02 s
    for _ = 1, 18 do
      sess:call("sim", { action = "step", seconds = 0.25 })
    end
    A.same({ player.health, player.isDead }, { 1, false })
    local hits = {}
    for _, e in ipairs(w.combat.log.entries) do
      if e[2] == "SWING_DAMAGE" and e[8] == player.guid then
        hits[#hits + 1] = e[12]
      end
    end
    A.same(hits, { 3, 3 }) -- logged in full though only 2 and then 1 point went
    SH.reloaded(sess, function(fresh)
      A.eq(fresh.w.sim.player.healthFloor, 1)
    end)
  end)
end

return function()
  test_mob_hits_cannot_kill_the_player_and_the_floor_survives_a_reload()
end
