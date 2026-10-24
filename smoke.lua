-- Smoke scoreboard: runs every addon in a folder through one built-in scenario on each flavor, with a runaway
-- guard so a looping addon fails instead of hanging, and writes one scoreboard for the whole folder.
local M = {}

local Flavors = require("tools.flavors")
local Scenario = require("scenario")
local SmokeScoreboard = require("smoke_scoreboard")
local Toc = require("toc")
local fs = require("fs")

M.BUDGET = 10000000
M.format = SmokeScoreboard.format

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
local ADDON_SOURCE = "@addon:"
local C_SOURCE = "=[C]"
local TRIPPED_MASK, TRIPPED_COUNT = "c", 1000
local coroutineLib = coroutine
local sethook, getinfo = debug.sethook, debug.getinfo
local cocreate, cowrap, coresume = coroutine.create, coroutine.wrap, coroutine.resume
local raise, unpackList, select, pcall, type = error, unpack, select, pcall, type
-- Every kit module loads from the same package.path root as this file, so they share its source prefix.
local KIT_SOURCE = getinfo(1, "S").source:match("^(@.*[/\\])smoke%.lua$") or "@"

local armedBudget, tripped = 0, false

-- True when source is the kit's own code: a C function or a file under the kit root. Fixture addons live under
-- the kit root too, so addon chunks are ruled out first.
local function isKit(source)
  if source:sub(1, #ADDON_SOURCE) == ADDON_SOURCE then
    return false
  end
  return source == C_SOURCE or source:sub(1, #KIT_SOURCE) == KIT_SOURCE
end

-- Budget error. The first trip raises whatever runs; after that every thread that reaches the hook switches to the
-- tripped hook (every call and every 1000 instructions) and every non-kit function dies at once, so kit code (error
-- handlers, disarm, w:destroy) runs normally and a looping 0-second ticker dies on entry to each callback.
local function onBudget()
  sethook(onBudget, TRIPPED_MASK, TRIPPED_COUNT)
  if tripped then
    local info = getinfo(2, "S")
    if info and isKit(info.source) then
      return
    end
  end
  tripped = true
  raise(BUDGET_MESSAGE, 0)
end

-- Hooks are per thread: every coroutine created while armed gets its own budget hook, the tripped one once tripped.
local function hookedCreate(fn)
  local co = cocreate(fn)
  if tripped then
    sethook(co, onBudget, TRIPPED_MASK, TRIPPED_COUNT)
  else
    sethook(co, onBudget, "", armedBudget)
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

local function arm(budget)
  armedBudget, tripped = budget, false
  coroutineLib.create, coroutineLib.wrap = hookedCreate, hookedWrap
  sethook(onBudget, "", budget)
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
  s:unit("player", VIEWER)
  s:login()
  s:unit("mouseover", OTHER)
  s:hover("mouseover")
  s:advance(5)
end

-- The guard is disarmed on every exit path; err is rethrown unchanged so Scenario's SKIPPED sentinel keeps its
-- identity. sethook() runs first thing after pcall to keep the window where a stray hook could fire small.
local function smokeScenario(budget)
  return function(s)
    arm(budget)
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
-- a folder whose addon name cannot be told fails every flavor with the name rule's message.
function M.runAddon(root, flavors, budget)
  local name, message = Toc.addonName(root)
  if not name then
    return { name = folderName(root), results = failedEverywhere(flavors, message) }
  end
  local results = Scenario.matrix(flavors, smokeScenario(budget or M.BUDGET), { addon = name, root = root })
  return { name = name, results = results }
end

-- opts: { dir, flavors?, budget? }. Runs every addon folder in dir, then writes the scoreboard once. Returns 0 when
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
  write(M.format(results, flavors))
  return 0
end

return M
