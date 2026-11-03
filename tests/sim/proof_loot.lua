-- Real-extract loot proof (a script, not a suite test): a sim session with Blizzard's UI loaded from a client extract
-- kills a mob, loots it through the real Blizzard LootFrame and writes the render snapshot for tools/preview.py.
-- Usage (python tools/run51.py --script), environment: PROOF_FLAVOR (retail | tbc), PROOF_EXTRACT (extract dir),
-- PROOF_OUT (output dir).
-- Prints `PROOF <flavor> shown=<bool> rows=<n> warnings=<n>`, then `ESC closed=<bool>` (observed, not asserted).
local Json = require("json")
local Resolve = require("combat_resolve")
local Session = require("session")
local SimMobs = require("sim_mobs")
local SimTarget = require("sim_target")
local Tmp = require("tests.helpers.tmp")
local fs = require("fs")

local getenv, print = os.getenv, print

local ADDON_DIR = "tests/fixtures/addons/SessionDemo"
local MOB_YARDS = 3
local EXPECTED_ROWS = 3
local STEP = 0.25

local function openLoot(sess)
  local w = sess.w
  local player = w.sim.player
  local pos = { x = player.pos.x, y = player.pos.y + MOB_YARDS }
  local mob = SimMobs.spawn(w, { pos = pos, health = 1 })
  Resolve.damage(w, player, mob, { amount = 1 })
  SimTarget.interact(w, mob, "RightButton")
  sess:call("sim", { action = "step", seconds = STEP })
  sess:call("sim", { action = "step", seconds = STEP })
end

local function check(sess, flavor, out)
  openLoot(sess)
  local shown = _G.LootFrame:IsShown()
  local rows = _G.GetNumLootItems()
  print(string.format("PROOF %s shown=%s rows=%d warnings=%d", flavor, tostring(shown), rows, #sess.w.warnings))
  fs.writeFile(out .. "/snapshot.json", Json.encode(sess:call("snapshot", {})))
  assert(shown and rows == EXPECTED_ROWS, "LootFrame shown=" .. tostring(shown) .. " rows=" .. rows)
  sess:call("input", { kind = "press", key = "ESCAPE" })
  print("ESC closed=" .. tostring(not _G.LootFrame:IsShown()))
end

local flavor, extract, out = getenv("PROOF_FLAVOR"), getenv("PROOF_EXTRACT"), getenv("PROOF_OUT")
local sess = Session.new({
  addonDir = ADDON_DIR,
  flavor = flavor,
  sessionDir = Tmp.dir("proof"),
  extract = extract,
  blizzardUi = true,
  sim = {},
})
local ok, result = pcall(check, sess, flavor, out)
sess:shutdown()
if not ok then
  error(result, 0)
end

return 0
