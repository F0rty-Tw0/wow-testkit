-- P2: layout and render, on a world built once (the addon logged in, a unit hovered, 5 s advanced, as smoke.lua drive does).
-- Usage (python tools/run51.py --script): bench_render.lua <addonDir> [runs]
--   P2a.<addon>  Layout.invalidate, then Layout.screenRect for every key of w.ui.state (cold cache)
--   P2b.<addon>  Layout.invalidate, then Render.snapshot (cold)
--   P2c.<addon>  Render.snapshot straight after a snapshot (warm)
local Bench = require("tests.bench.bench")
local Layout = require("ui.layout")
local Render = require("render")
local Scenario = require("scenario")
local Toc = require("toc")

local addonDir, runsText = ...
local runs = Bench.runs(runsText)
local runtime = Bench.runtime()
local name = assert(Toc.addonName(addonDir))

-- smoke.lua's unit fixtures for the built-in scenario.
local VIEWER = {
  name = "Viewer",
  isPlayer = true,
  className = "Mage",
  classFile = "MAGE",
  raceName = "Human",
  raceFile = "Human",
  level = 60,
  reaction = 4,
  faction = "Alliance",
  pvp = false,
  isFriend = true,
  inParty = false,
  inRaid = false,
  health = 4000,
  healthMax = 4000,
  power = 6000,
  powerMax = 6000,
  guild = "Kirin Tor Exiles",
  guildRank = "Member",
}
local OTHER = {
  name = "Grukmar",
  isPlayer = true,
  className = "Warrior",
  classFile = "WARRIOR",
  raceName = "Orc",
  raceFile = "Orc",
  level = 60,
  reaction = 2,
  faction = "Horde",
  pvp = true,
  isFriend = false,
  inParty = false,
  inRaid = false,
  health = 5200,
  healthMax = 5200,
  power = 0,
  powerMax = 100,
  guild = "Blood Pact",
  guildRank = "Raider",
  mythicScore = 1500,
}

local s = Scenario.new({ addon = name, root = addonDir, flavor = "retail", silencePrint = true })
s:unit("player", VIEWER)
s:login()
s:unit("mouseover", OTHER)
s:hover("mouseover")
s:advance(5)
local w = s.w

local function layoutCold()
  Layout.invalidate(w)
  for region in pairs(w.ui.state) do
    Layout.screenRect(w, region)
  end
end

local function snapshotCold()
  Layout.invalidate(w)
  Render.snapshot(w)
end

local function snapshotWarm()
  Render.snapshot(w)
end

local ok, err = pcall(function()
  Bench.measure("P2a." .. name, runtime, runs, layoutCold)
  Bench.measure("P2b." .. name, runtime, runs, snapshotCold)
  Render.snapshot(w)
  Bench.measure("P2c." .. name, runtime, runs, snapshotWarm)
end)
w:destroy()
if not ok then
  error(err, 0)
end

return 0
