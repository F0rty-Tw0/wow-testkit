-- Real-extract proof (a script, not a suite test): a sim session with Blizzard's UI loaded from a client extract loads the
-- flavor's default bindings and walks 7 yards when W goes down for one second through Blizzard's MOVEFORWARD chunk.
-- Usage (python tools/run51.py --script): proof_extract.lua <flavor> <extract-dir>
-- Prints `PROOF <flavor> ok`, then the layer's load error count: the layer is best effort and raises errors with or
-- without the sim, so the count is reported, not asserted.
local flavor, extract = ...
local Session = require("session")
local Tmp = require("tests.helpers.tmp")

local print = print
local ADDON_DIR = "tests/fixtures/addons/SessionDemo"
local EPSILON = 1e-6
local SPAWN_Y = -10

local function check(sess)
  local blizzard = sess.w.blizzard
  local errors = #blizzard.errors
  assert(blizzard.defaultBindings, "no default bindings loaded: " .. table.concat(blizzard.notes, "; "))
  local down = sess:call("input", { kind = "keydown", key = "W" })
  assert(down.ok and down.binding == "MOVEFORWARD", "W is not bound to MOVEFORWARD: " .. tostring(down.binding))
  local world = sess:call("sim", { action = "step", seconds = 0.25 })
  for _ = 1, 3 do
    world = sess:call("sim", { action = "step", seconds = 0.25 })
  end
  local walked = world.world.player.pos.y - SPAWN_Y
  assert(math.abs(walked - 7) < EPSILON, "walked " .. walked .. " yd, expected 7")

  return errors
end

local sess = Session.new({
  addonDir = ADDON_DIR,
  flavor = flavor,
  sessionDir = Tmp.dir("proof"),
  extract = extract,
  blizzardUi = true,
  sim = {},
})
local ok, result = pcall(check, sess)
sess:shutdown()
if not ok then
  error(result, 0)
end
print("PROOF " .. flavor .. " ok")
print("blizzard load errors " .. result .. " (not asserted)")

return 0
