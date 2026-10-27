-- Unit events for the combat world: listens to the actor hooks and fires the client's events once per unit token that
-- names the actor, in the client's token test order.
local M = {}

local Actors = require("combat_actors")
local Auras = require("combat_auras")
local Combat = require("combat")

local ENGINE = "blizzard"
local PLAYER = "player"
-- actor -> the absorb total its last UNIT_ABSORB_AMOUNT_CHANGED announced.
local announcedAbsorbs = setmetatable({}, { __mode = "k" })

local function fire(w, event, ...)
  w:run(ENGINE, w.fire, w, event, ...)
end

-- source: assumed (row C7) one event per token naming the actor, in TOKEN_ORDER. makeArgs(token) gives the payload after
-- the unit; it runs per token so every handler gets its own tables.
local function fanOut(w, actor, event, makeArgs)
  for _, token in ipairs(Actors.tokens(w, actor)) do
    if makeArgs then
      fire(w, event, token, makeArgs(token))
    else
      fire(w, event, token)
    end
  end
end

local function copyList(list, map)
  if not list then
    return nil
  end
  local out = {}
  for i, item in ipairs(list) do
    out[i] = map and map(item) or item
  end
  return out
end

-- source: confirmed (row C8) UnitAuraUpdateInfo is { isFullUpdate, addedAuras, updatedAuraInstanceIDs,
-- removedAuraInstanceIDs }; the added auras are AuraData copies without the kit's fields.
local function auraInfo(update)
  return {
    isFullUpdate = false,
    addedAuras = copyList(update.addedAuras, Auras.publicCopy),
    updatedAuraInstanceIDs = copyList(update.updatedAuraInstanceIDs),
    removedAuraInstanceIDs = copyList(update.removedAuraInstanceIDs),
  }
end

-- source: confirmed (row C9) the payloads end with castBarID; INTERRUPTED and CHANNEL_STOP carry interruptedBy before it.
-- Assumed the kit has no cast bar ids, so castBarID is nil.
local function castArgs(phase, cast)
  if phase == "INTERRUPTED" or phase == "CHANNEL_STOP" then
    return function()
      return cast.castGUID, cast.spellID, cast.interruptedBy, nil
    end
  end
  return function()
    return cast.castGUID, cast.spellID, nil
  end
end

function M.install(w)
  Combat.listen(w, "health", function(actor)
    fanOut(w, actor, "UNIT_HEALTH")
  end)
  Combat.listen(w, "healthmax", function(actor)
    fanOut(w, actor, "UNIT_MAXHEALTH")
  end)
  Combat.listen(w, "power", function(actor, powerType)
    fanOut(w, actor, "UNIT_POWER_UPDATE", function()
      return powerType
    end)
  end)
  Combat.listen(w, "aura", function(actor, update)
    fanOut(w, actor, "UNIT_AURA", function()
      return auraInfo(update)
    end)
    if actor.absorbs ~= (announcedAbsorbs[actor] or 0) then
      announcedAbsorbs[actor] = actor.absorbs
      fanOut(w, actor, "UNIT_ABSORB_AMOUNT_CHANGED")
    end
  end)
  Combat.listen(w, "flags", function(actor)
    fanOut(w, actor, "UNIT_FLAGS")
  end)
  -- source: assumed (row C7) PLAYER_TARGET_CHANGED fires before UNIT_TARGET.
  Combat.listen(w, "target", function(actor)
    if w.unitState.byToken[PLAYER] == actor then
      fire(w, "PLAYER_TARGET_CHANGED")
    end
    fanOut(w, actor, "UNIT_TARGET")
  end)
  Combat.listen(w, "cast", function(actor, phase, cast)
    fanOut(w, actor, "UNIT_SPELLCAST_" .. phase, castArgs(phase, cast))
  end)
end

return M
