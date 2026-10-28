-- Window test helpers: a world or scenario over a kit-authored mini client extract (DB2 tables, DB2 index files and empty
-- Blizzard addon folders written from strings, never from a Blizzard file), always destroyed.
local Combat = require("tests.helpers.combat")
local Game = require("game")
local H = require("tests.helpers.client")
local Scenario = require("scenario")
local Tmp = require("tests.helpers.tmp")
local Units = require("units")
local Widgets = require("ui.widgets")
local World = require("world")

local M = {}

local BUILD = "1"

-- The mini extract opts describes, or nil when it names no table, index or addon (no extract). opts = { db2? = {
-- [lowername] = "<lua source>" }, index? = { ["<lowername>.<column lowercased>"] = "<lua source>" }, addons? = { "Blizzard_Name" } }.
local function extractOf(flavor, opts)
  local files, any = {}, false
  for name, source in pairs(opts.db2 or {}) do
    files["db2/" .. name .. ".lua"], any = source, true
  end
  for name, source in pairs(opts.index or {}) do
    files["db2/index/" .. name .. ".lua"], any = source, true
  end
  for _, addon in ipairs(opts.addons or {}) do
    local key = addon:lower()
    files["code/addons/" .. key .. "/" .. key .. ".toc"], any = "", true
  end
  return any and H.extract(Tmp.dir("win"), flavor, BUILD, files) or nil
end

local function finish(destroy, ok, err)
  destroy()
  if not ok then
    error(err, 0)
  end
end

-- Runs fn(w) on a world of flavor over the mini extract opts describes, with Units, Widgets and Game installed.
function M.withWindows(flavor, opts, fn)
  local w = World.new({ flavor = flavor, client = extractOf(flavor, opts) })
  local ok, err = pcall(function()
    Units.install(w)
    Widgets.install(w)
    Game.install(w)
    fn(w)
  end)
  finish(function()
    w:destroy()
  end, ok, err)
end

-- Runs fn(s) on a Scenario of flavor over the same mini extract (no layer unless the caller sets s.blizzardUi).
function M.scenario(flavor, opts, fn)
  local s = Scenario.new({ addon = "T", root = "T", flavor = flavor, client = extractOf(flavor, opts) })
  local ok, err = pcall(fn, s)
  finish(function()
    s.w:destroy()
  end, ok, err)
end

-- A frame registered for events; log[i] = { event, n, ... } in firing order (Task 8.2's watcher).
M.watch = Combat.watch

-- The event names of a watch log, in fire order.
function M.names(log)
  local out = {}
  for i, entry in ipairs(log) do
    out[i] = entry[1]
  end
  return out
end

return M
