-- Spell facts read from w.mock.spells at call time: { [id] = { name, icon, originalIcon, castTime, minRange, maxRange,
-- known, cooldown = { start, duration, enabled } } }. A known id with an absent field returns nothing for that value;
-- an unknown id returns the API's default and counts as unscripted.
local M = {}

local State = require("game.state")
local WorldApi = require("world_api")
local define = State.define

M.DEFAULTS = { spells = {} }

-- source: assumed (row G13) the kit's link format, the client's colour and the zero data after the id.
local function spellLink(id, record)
  if record.name == nil then
    return nil
  end
  return string.format("|cff71d5ff|Hspell:%d:0|h[%s]|h|r", id, record.name)
end

local function installInfo(w, find)
  -- source: confirmed (row G13) the table fields; nothing for an unknown spell.
  local function info(ident)
    local id, record = find(ident, "C_Spell.GetSpellInfo")
    if not id then
      return nil
    end
    return {
      name = record.name,
      iconID = record.icon,
      originalIconID = record.originalIcon or record.icon,
      castTime = record.castTime,
      minRange = record.minRange,
      maxRange = record.maxRange,
      spellID = id,
    }
  end
  define(w, "C_Spell.GetSpellInfo", info)
  -- source: confirmed (row G13) the old global answers name, subtext, icon, castTime, minRange, maxRange, spellID,
  -- originalIcon: not the table's order.
  define(w, "GetSpellInfo", function(ident)
    local id, record = find(ident, "GetSpellInfo")
    if not id then
      return
    end
    return record.name, record.subtext, record.icon, record.castTime, record.minRange, record.maxRange, id, record.originalIcon or record.icon
  end)
end

local function installTextureAndLink(w, find)
  define(w, "C_Spell.GetSpellTexture", function(ident)
    local id, record = find(ident, "C_Spell.GetSpellTexture")
    if id then
      return record.icon, record.originalIcon or record.icon
    end
  end)
  define(w, "GetSpellTexture", function(ident)
    local id, record = find(ident, "GetSpellTexture")
    if id then
      return record.icon
    end
  end)
  define(w, "C_Spell.GetSpellLink", function(ident)
    local id, record = find(ident, "C_Spell.GetSpellLink")
    return id and spellLink(id, record) or nil
  end)
  define(w, "GetSpellLink", function(ident)
    local id, record = find(ident, "GetSpellLink")
    return id and spellLink(id, record) or nil
  end)
end

-- source: assumed (row G13) a spell with no cooldown data is off cooldown: start 0, duration 0, enabled, rate 1 (the
-- client answers that for a ready spell; no page lists it).
local function cooldownOf(record)
  local cd = record.cooldown or {}
  return cd.start or 0, cd.duration or 0, cd.enabled ~= false, cd.modRate or 1
end

local function installCooldownAndKnown(w, find)
  define(w, "C_Spell.GetSpellCooldown", function(ident)
    local id, record = find(ident, "C_Spell.GetSpellCooldown")
    if not id then
      return nil
    end
    local start, duration, enabled, rate = cooldownOf(record)
    return { startTime = start, duration = duration, isEnabled = enabled, modRate = rate }
  end)
  define(w, "GetSpellCooldown", function(ident)
    local id, record = find(ident, "GetSpellCooldown")
    if not id then
      return
    end
    local start, duration, enabled, rate = cooldownOf(record)
    return start, duration, enabled and 1 or 0, rate
  end)
  -- source: confirmed (row G1) the deprecation fallback exists on every flavor; assumed (row G13) a spell the mock
  -- holds is known unless it says known = false.
  define(w, "IsSpellKnown", function(id)
    local record = type(id) == "number" and w.mock.spells[id]
    if not record then
      WorldApi.markUnscripted(w, "IsSpellKnown")
      return false
    end
    return record.known ~= false
  end, State.ALL)
end

function M.install(w)
  local function find(ident, name)
    local id, record = State.findRecord(w.mock.spells, ident)
    if not id then
      WorldApi.markUnscripted(w, name)
    end
    return id, record
  end
  installInfo(w, find)
  installTextureAndLink(w, find)
  installCooldownAndKnown(w, find)
end

return M
