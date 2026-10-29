-- Smoke scoreboard: runs every addon in a folder through one built-in scenario on each flavor, with a runaway
-- guard so a looping addon fails instead of hanging, and writes one scoreboard for the whole folder.
local M = {}

local Flavors = require("tools.flavors")
local Scenario = require("scenario")
local SmokeJson = require("smoke_json")
local SmokeScoreboard = require("smoke_scoreboard")
local Toc = require("toc")
local fs = require("fs")

M.BUDGET = 10000000
-- Layer ticks trip at LAYER_FACTOR budgets (R-debt-1, below).
M.LAYER_FACTOR = 10
M.format = SmokeScoreboard.format
M.formatJson = SmokeJson.format

local BLIZZARD_PREFIX = "Blizzard_"

-- Unit fixtures for the built-in scenario. realm is unset: same-realm units have a nil realm.
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

-- Runaway guard. Captured at load so an addon that reassigns debug, coroutine or error cannot break it.
local BUDGET_MESSAGE = "smoke: instruction budget exceeded"
-- A layer trip names the layer, so a catalog does not blame the addon whose next function dies with it.
local LAYER_MESSAGE = "smoke: Blizzard UI layer instruction budget exceeded"
local ADDON_SOURCE = "@addon:"
local C_SOURCE = "=[C]"
local TAIL_SOURCE = "=(tail call)"
local TRIPPED_MASK, TRIPPED_COUNT = "c", 1000
-- source: R-debt-1 (lead ruling 2026-10-29) the budget counts addon-owned execution only; Blizzard UI layer chunks are
-- excluded, since layer fidelity grew s:login from 7.7M to 22M instructions against the 10M budget. The count hook fires
-- every TICK instructions and charges them to the first non-kit function on the stack. Layer ticks only trip at
-- M.LAYER_FACTOR budgets, so a Blizzard loop the kit sends into a spin still ends the run.
-- 10000, not 1000: the stack walk per tick doubled the CPU of a Blizzard-layer smoke run at 1000 (+7% at 10000).
local TICK = 10000
local ADDON_OWNER = "^@addon:([^/\r\n]+)/"
local coroutineLib = coroutine
local sethook, getinfo = debug.sethook, debug.getinfo
local cocreate, cowrap, coresume = coroutine.create, coroutine.wrap, coroutine.resume
local raise, unpackList, select, pcall, type = error, unpack, select, pcall, type
-- Every kit module loads from the same package.path root as this file, so they share its source prefix.
local KIT_SOURCE = getinfo(1, "S").source:match("^(@.*[/\\])smoke%.lua$") or "@"

local armedBudget, tripped, tripMessage = 0, false, BUDGET_MESSAGE
local spent, layerSpent, layerBudget, layerAddons = 0, 0, 0, {}

-- True when source is the kit's own code: a C function or a file under the kit root. Fixture addons live under
-- the kit root too, so addon chunks are ruled out first.
local function isKit(source)
  if source:sub(1, #ADDON_SOURCE) == ADDON_SOURCE then
    return false
  end
  return source == C_SOURCE or source:sub(1, #KIT_SOURCE) == KIT_SOURCE
end

-- True when the first non-kit function at stack level 3 and up (the code the hook interrupted, seen from inside
-- onBudget) is a chunk of a layer addon. Kit code counts for whoever called it; a stack of kit code only counts too.
-- Tail-call frames are skipped like kit code: widget methods reach the kit through them.
local function inLayer()
  local level = 3
  local info = getinfo(level, "S")
  while info and (isKit(info.source) or info.source == TAIL_SOURCE) do
    level = level + 1
    info = getinfo(level, "S")
  end
  local owner = info and info.source:match(ADDON_OWNER)
  return owner ~= nil and layerAddons[owner] == true
end

-- Charges a tick and returns, until the addon's ticks reach the budget (or the layer's, layerBudget). Then the
-- budget error: the first trip raises whatever runs; after that every thread that reaches the hook switches to the
-- tripped hook (every call and every 1000 instructions) and every non-kit function dies at once, so kit code (error
-- handlers, disarm, w:destroy) runs normally and a looping 0-second ticker dies on entry to each callback.
local function onBudget()
  if not tripped then
    if inLayer() then
      layerSpent = layerSpent + TICK
    else
      spent = spent + TICK
    end
    if spent < armedBudget and layerSpent < layerBudget then
      -- Lua 5.1 counts this hook's own instructions toward the next tick; setting the hook again restarts the count.
      sethook(onBudget, "", TICK)
      return
    end
    tripMessage = spent < armedBudget and LAYER_MESSAGE or BUDGET_MESSAGE
  end
  sethook(onBudget, TRIPPED_MASK, TRIPPED_COUNT)
  if tripped then
    local info = getinfo(2, "S")
    if info and isKit(info.source) then
      return
    end
  end
  tripped = true
  raise(tripMessage, 0)
end

-- Hooks are per thread: every coroutine created while armed gets its own budget hook, the tripped one once tripped. All
-- threads charge the same counters, so the budget is per run, not per coroutine.
local function hookedCreate(fn)
  local co = cocreate(fn)
  if tripped then
    sethook(co, onBudget, TRIPPED_MASK, TRIPPED_COUNT)
  else
    sethook(co, onBudget, "", TICK)
  end
  return co
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- Like Lua 5.1's coroutine.wrap, a string error gains the caller's position (luaL_where(L, 1)).
local function hookedWrap(fn)
  local co = hookedCreate(fn)
  return function(...)
    local results = pack(coresume(co, ...))
    if not results[1] then
      local err = results[2]
      raise(err, type(err) == "string" and 2 or 0)
    end
    return unpackList(results, 2, results.n)
  end
end

-- secureAddons: the world's w.taint.secureAddons, the layer addons whose chunks the budget does not count (R-debt-1).
local function arm(budget, secureAddons)
  armedBudget, tripped, spent, layerSpent = budget, false, 0, 0
  layerBudget, layerAddons = budget * M.LAYER_FACTOR, secureAddons
  coroutineLib.create, coroutineLib.wrap = hookedCreate, hookedWrap
  sethook(onBudget, "", TICK)
end

local function hasToc(root)
  for _, file in ipairs(fs.list(root)) do
    if file:lower():match("%.toc$") then
      return true
    end
  end
  return false
end

-- Direct subfolders of dir holding at least one .toc, except the client's own Blizzard_ addons; sorted. Second value:
-- { name, reason } for each folder skipped because listing it raised (without the fs bridge on windows the shell
-- fallback refuses a path such as "50%Off").
function M.addonFolders(dir)
  local folders, skipped = {}, {}
  for _, name in ipairs(fs.list(dir)) do
    local root = dir .. "/" .. name
    if name:sub(1, #BLIZZARD_PREFIX) ~= BLIZZARD_PREFIX and fs.isdir(root) then
      local listed, found = pcall(hasToc, root)
      if listed and found then
        folders[#folders + 1] = name
      elseif not listed then
        skipped[#skipped + 1] = { name = name, reason = tostring(found) }
      end
    end
  end
  table.sort(folders)
  return folders, skipped
end

local function drive(s)
  s:login()
  s:unit("mouseover", OTHER)
  s:hover("mouseover")
  s:advance(5)
end

-- The guard is disarmed on every exit path; err is rethrown unchanged so Scenario's SKIPPED sentinel keeps its
-- identity. sethook() runs first thing after pcall to keep the window where a stray hook could fire small. The Blizzard UI
-- layer (opts.blizzardUi) loads before the guard arms: its closure of dozens of addons is not the addon under test, and
-- s:login skips a layer already loaded. Once armed, the layer's own chunks still run outside the budget (R-debt-1).
local function smokeScenario(budget)
  return function(s)
    s:unit("player", VIEWER)
    s:loadBlizzard()
    arm(budget, s.w.taint.secureAddons)
    local ok, err = pcall(drive, s)
    sethook()
    coroutineLib.create, coroutineLib.wrap = cocreate, cowrap
    if not ok then
      raise(err, 0)
    end
  end
end

local function folderName(root)
  return root:gsub("\\", "/"):match("([^/]+)/*$")
end

local function failedEverywhere(flavors, message)
  local results = {}
  for _, flavor in ipairs(flavors) do
    results[flavor] = { status = "fail", errors = { { message = message } }, unscripted = {} }
  end
  return results
end

-- Runs the smoke scenario for the addon at root on each flavor. Returns { name, results = { [flavor] = report } };
-- a folder whose addon name cannot be told fails every flavor with the name rule's message. extra: more Scenario.matrix
-- opts (blizzardUi, findClient, client).
function M.runAddon(root, flavors, budget, extra)
  local name, message = Toc.addonName(root)
  if not name then
    return { name = folderName(root), results = failedEverywhere(flavors, message) }
  end
  local opts = { addon = name, root = root, silencePrint = true }
  for key, value in pairs(extra or {}) do
    opts[key] = value
  end
  local results = Scenario.matrix(flavors, smokeScenario(budget or M.BUDGET), opts)
  return { name = name, results = results }
end

-- opts: { dir, flavors?, budget?, json? }. Runs every addon folder in dir, then writes the scoreboard (the JSON document
-- with json) once. Returns 0 when
-- the run completes whatever the results, 2 when dir is missing or holds no addon folder.
function M.run(opts, write)
  local dir = opts.dir
  if not (dir and fs.isdir(dir)) then
    write("smoke: no such directory: " .. tostring(dir) .. "\n")
    return 2
  end
  local folders, skipped = M.addonFolders(dir)
  for _, folder in ipairs(skipped) do
    write("smoke: skipped " .. folder.name .. ": " .. folder.reason .. "\n")
  end
  if #folders == 0 then
    write("smoke: no addon folders in " .. dir .. "\n")
    return 2
  end
  local flavors = opts.flavors or Flavors.list
  local results = {}
  for i, name in ipairs(folders) do
    results[i] = M.runAddon(dir .. "/" .. name, flavors, opts.budget)
  end
  write((opts.json and M.formatJson or M.format)(results, flavors))
  return 0
end

return M
