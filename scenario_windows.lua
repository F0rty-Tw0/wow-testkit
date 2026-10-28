-- Scenario hooks for the Blizzard windows (blizzard_windows.lua): s:openWindow and s:closeWindow fire what the flavor's
-- window code listens for (B2). Tasks 12.3-12.7 register an opener and a closer per window in ScenarioWindows.openers /
-- .closers; a window without one uses the default (load the addon, then the open path).
local M = {}

local BlizzardData = require("blizzard_data")
local BlizzardWindows = require("blizzard_windows")
local TalentsClassic = require("game.talents_classic")
local TalentsDb2 = require("game.talents_db2")

local ENGINE = "blizzard"
local SHOW, HIDE = "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"

-- openers[window](s, data) and closers[window](s)
M.openers, M.closers = {}, {}

-- Calls the global name (a function) with the global frame under engine context; nothing when either is missing.
local function callOn(s, name, frame)
  local fn, target = _G[name], frame and _G[frame]
  if type(fn) == "function" and target then
    s.w:run(ENGINE, fn, target)
  end
end

-- source: assumed (B2) the order: the window path first (the interaction event, else the window's show global, else its
-- toggle), then the legacy event addons listen for. The show global and the toggle need the layer.
function M.show(s, window)
  local w, spec = s.w, BlizzardWindows.spec(s.w, window)
  if w.blizzard then
    local ok = w:run(ENGINE, BlizzardWindows.loadFor, w, window)
    if not ok then
      s:note("openWindow: " .. spec.addon .. " missing")
    end
  end
  if spec.interaction then
    s:fireIfKnown(SHOW, BlizzardWindows.interaction(spec.interaction))
  end
  if spec.show and w.blizzard and type(_G[spec.show]) == "function" then
    w:run(ENGINE, _G[spec.show])
  end
  if spec.open then
    s:fireIfKnown(spec.open)
  end
  if spec.toggle and w.blizzard and not (spec.interaction or spec.show or spec.open) then
    if type(_G[spec.toggle]) == "function" then
      w:run(ENGINE, _G[spec.toggle])
    elseif spec.frame and _G[spec.frame] then
      w:run(ENGINE, _G[spec.frame].Show, _G[spec.frame])
    end
  end
end

-- source: confirmed (B2) retail handles PLAYER_INTERACTION_MANAGER_FRAME_HIDE in playerinteractionframemanager.lua:174;
-- assumed the show and toggle windows hide through HideUIPanel(<frame>), with the layer on.
function M.hide(s, window)
  local w, spec = s.w, BlizzardWindows.spec(s.w, window)
  if spec.interaction then
    s:fireIfKnown(HIDE, BlizzardWindows.interaction(spec.interaction))
  end
  local frame = spec.frame and _G[spec.frame]
  if w.blizzard and frame and (spec.show or (spec.toggle and frame:IsShown())) then
    callOn(s, "HideUIPanel", spec.frame)
  end
end

local function checked(s, window, verb)
  if not BlizzardWindows.spec(s.w, window) then
    error(verb .. ": unknown window '" .. tostring(window) .. "'", 3)
  end
end

-- The classic store keys an opener's data may carry; the retail ones are treeID, configID and traits.
local CLASSIC_KEYS = { "unspent", "groups", "activeGroup", "tabs", "grid" }

local function picked(data, keys)
  local out = {}
  for _, key in ipairs(keys) do
    out[key] = data[key]
  end
  return out
end

local function openClassicTalents(s, data)
  local w = s.w
  w:setMock({ talents = picked(data, CLASSIC_KEYS) })
  BlizzardData.fill(w, "talents", function()
    return TalentsDb2.classic(w, data.classFile)
  end)
  if #w.mock.talents.tabs == 0 and data.kit then
    w:setMock({ talents = picked(data.kit, CLASSIC_KEYS) })
  end
  for _, tab in ipairs(w.mock.talents.tabs) do
    for _, talent in ipairs(tab.talents or {}) do
      talent.rank = data.ranks and data.ranks[talent.talentID] or talent.rank
    end
  end
end

-- The trait tree: data.treeID, else the first tree of the active config. A tree with a config of no store gets a kit
-- config, so C_Traits answers for it.
local function openTraitTalents(s, data)
  local w = s.w
  w:setMock({ traits = data.traits })
  local traits = w.mock.traits
  traits.configID = data.configID or traits.configID or 1
  local config = traits.configs[traits.configID]
  local treeID = data.treeID or config and config.treeIDs and config.treeIDs[1]
  if treeID and not config then
    traits.configs[traits.configID] = { name = "Kit Build", type = 1, treeIDs = { treeID } }
  end
  BlizzardData.fill(w, "traits", function()
    return treeID and TalentsDb2.traits(w, treeID)
  end)
  if treeID and not traits.trees[treeID] and data.kit then
    w:setMock({ traits = data.kit.traits })
  end
  for nodeID, rank in pairs(data.ranks or {}) do
    traits.nodes[nodeID] = traits.nodes[nodeID] or {}
    traits.nodes[nodeID].ranksPurchased = rank
  end
end

-- Opens talents: the classic family (tabs, grid, unspent) or the trait window (treeID, configID, traits), each ignoring
-- the other's keys. Scenario keys win over the extract's DB2 geometry; ranks = { [talentID or nodeID] = rank } set after;
-- kit = a stand-in store used only when the extract builds nothing (no extract, or a tree it lacks).
function M.openers.talents(s, data)
  data = data or {}
  if TalentsClassic.isClassic(s.w) then
    openClassicTalents(s, data)
  else
    openTraitTalents(s, data)
  end
  M.show(s, "talents")
end
M.closers.talents = function(s)
  M.hide(s, "talents")
end

function M.extend(Scenario)
  -- Opens window (the flavor's name for it: talents, map, merchant, mail, auction, transmog) with the data its opener
  -- takes; raises for a window the flavor has no spec for.
  function Scenario:openWindow(window, data)
    checked(self, window, "openWindow")
    local opener = M.openers[window]
    if opener then
      opener(self, data)
    else
      M.show(self, window)
    end
  end

  function Scenario:closeWindow(window)
    checked(self, window, "closeWindow")
    local closer = M.closers[window]
    if closer then
      closer(self)
    else
      M.hide(self, window)
    end
  end
end

return M
