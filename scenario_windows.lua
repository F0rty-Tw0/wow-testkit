-- Scenario hooks for the Blizzard windows (blizzard_windows.lua): s:openWindow and s:closeWindow fire what the flavor's
-- window code listens for (B2). Tasks 12.3-12.7 register an opener and a closer per window in ScenarioWindows.openers /
-- .closers; a window without one uses the default (load the addon, then the open path).
local M = {}

local BlizzardData = require("blizzard_data")
local BlizzardWindows = require("blizzard_windows")
local Items = require("game.items")
local Mail = require("game.mail")
local Merchant = require("game.merchant")
local ScenarioAuction = require("scenario_auction")
local State = require("game.state")
local TalentsClassic = require("game.talents_classic")
local TalentsDb2 = require("game.talents_db2")

local ENGINE = "blizzard"
local FRAME = 1 / 60 -- seconds of one frame (assumed, 60 fps)
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
-- toggle), then the legacy event addons listen for. The show global and the toggle need the layer; an error they raise
-- goes to the error handler (w.blizzard.errors), as in the client, and the legacy event still fires.
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
    w:run(ENGINE, w.try, w, _G[spec.show])
  end
  if spec.open then
    s:fireIfKnown(spec.open)
  end
  if spec.toggle and w.blizzard and not (spec.interaction or spec.show or spec.open) then
    if type(_G[spec.toggle]) == "function" then
      w:run(ENGINE, w.try, w, _G[spec.toggle])
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

-- Fires OnUpdate once (elapsed FRAME) on frame and its shown descendants, in child order.
local function frameTick(w, frame)
  w:callScript(frame, "OnUpdate", FRAME)
  for _, child in ipairs(w.ui.state[frame].children) do
    if w.ui.state[child].shown then
      frameTick(w, child)
    end
  end
end

-- Opens map. data = { mapID? | mapIDs? = { [flavor] = uiMapID }, position? = { x, y }, maps? }: the map the player stands on
-- (a mapIDs entry for the flavor when mapID is unset; none leaves the zone as it was), the player's place on it (0-1) and
-- scenario map records. The extract's map list and art fill at world install and on first read, so scenario maps win.
function M.openers.map(s, data)
  data = data or {}
  local mapID = data.mapID or data.mapIDs and data.mapIDs[s.w.flavor]
  s.w:setMock({ maps = data.maps, zone = { mapID = mapID, position = data.position } })
  M.show(s, "map")
  -- source: assumed (B2) the client's first frame after the window shows: the kit has no frame loop, and a tbc detail layer
  -- keeps alpha 0 until its OnUpdate sees its tiles loaded (blizzard_mapcanvasdetaillayer.lua OnUpdate).
  local spec = BlizzardWindows.spec(s.w, "map")
  if spec.frame and _G[spec.frame] and s.w.ui.state[_G[spec.frame]].shown then
    s.w:run(ENGINE, frameTick, s.w, _G[spec.frame])
  end
end

-- Replaces w.mock[key] with a copy of data over the area's defaults (a list in a patch merges by index, so a second open
-- would keep the first one's tail).
local function replaceStore(w, key, data, defaults)
  w.mock[key] = State.merge({}, data or {})
  State.fill(w.mock[key], defaults[key])
end

-- Copies the item ids of rows into w.mock.items from the extract (B17). source: assumed without an extract a row left
-- unnamed is called "Kit item <id>", so the demo's id-only rows still read as items.
local function hydrate(w, rows)
  local ids = {}
  for _, row in ipairs(rows) do
    ids[#ids + 1] = row.itemID
  end
  BlizzardData.items(w, ids)
  for _, row in ipairs(w.client == nil and rows or {}) do
    if row.itemID and not Items.rowFacts(w, row) then
      row.name = "Kit item " .. row.itemID
    end
  end
end

-- Opens merchant. data = the w.mock.merchant store (game/merchant.lua); it replaces the last one.
-- source: assumed (B10) the order: the window path, MERCHANT_SHOW, then MERCHANT_UPDATE; MERCHANT_CLOSED on close.
function M.openers.merchant(s, data)
  local w = s.w
  replaceStore(w, "merchant", data, Merchant.DEFAULTS)
  local rows = {}
  for _, list in ipairs({ w.mock.merchant.items, w.mock.merchant.buyback }) do
    for _, row in ipairs(list) do
      rows[#rows + 1] = row
    end
  end
  hydrate(w, rows)
  M.show(s, "merchant")
  s:fireIfKnown("MERCHANT_UPDATE")
end
M.closers.merchant = function(s)
  M.hide(s, "merchant")
  s:fireIfKnown("MERCHANT_CLOSED")
end

-- Opens mail. data = the w.mock.mail store (game/mail.lua); it replaces the last one.
-- source: confirmed (B12) the classic window handles MAIL_INBOX_UPDATE; assumed MAIL_SHOW before it and MAIL_CLOSED on close.
function M.openers.mail(s, data)
  local w = s.w
  replaceStore(w, "mail", data, Mail.DEFAULTS)
  local rows = {}
  for _, mail in ipairs(w.mock.mail.inbox) do
    for _, item in ipairs(mail.items or {}) do
      rows[#rows + 1] = item
    end
  end
  hydrate(w, rows)
  M.show(s, "mail")
  s:fireIfKnown("MAIL_INBOX_UPDATE")
end
M.closers.mail = function(s)
  M.hide(s, "mail")
  s:fireIfKnown("MAIL_CLOSED")
end

function M.extend(Scenario)
  ScenarioAuction.extend(Scenario, M)
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
