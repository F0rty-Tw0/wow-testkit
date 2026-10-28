-- Action bar slots read from w.mock.actions at call time: { [slot] = { type, id, texture, count, text, start, duration,
-- usable } | false }, slots 1-180; false (or no entry) is an empty slot. Names are the retail C_ActionBar ones, which
-- every flavor's API data holds, plus the one bare global GetActionInfo. A table patch merges into the slot's table,
-- so a patch to one field keeps the rest; false empties the slot.
local M = {}

local State = require("game.state")
local define = State.define

M.DEFAULTS = { actions = {} }

-- source: assumed (row G19) the idle cooldown: nothing running, enabled, normal rate; the field names are the
-- SpellCooldownInfo struct of api/retail/Spell.lua.
local IDLE = { start = 0, duration = 0 }
-- source: assumed (row G19) GetActionDisplayCount's own defaults, from the api/retail argument list.
local MAX_DISPLAY_COUNT = 9999
local REPLACEMENT = "*"

local function slotOf(w, slot)
  local entry = w.mock.actions[slot]
  return type(entry) == "table" and entry or nil
end

local function installSlotReads(w)
  define(w, "C_ActionBar.HasAction", function(slot)
    return slotOf(w, slot) ~= nil
  end)
  -- source: assumed (row G19) a spell answers "spell", id, "spell"; any other type answers its type and id; an empty
  -- slot answers nothing.
  define(w, "GetActionInfo", function(slot)
    local entry = slotOf(w, slot)
    if not entry then
      return
    end
    return entry.type, entry.id, entry.type == "spell" and "spell" or nil
  end)
  define(w, "C_ActionBar.GetActionTexture", function(slot)
    local entry = slotOf(w, slot)
    return entry and entry.texture
  end)
  define(w, "C_ActionBar.GetActionText", function(slot)
    local entry = slotOf(w, slot)
    return entry and entry.text
  end)
end

local function installState(w)
  define(w, "C_ActionBar.GetActionCooldown", function(slot)
    local entry = slotOf(w, slot) or IDLE
    return { startTime = entry.start or 0, duration = entry.duration or 0, isEnabled = true, modRate = 1 }
  end)
  -- source: assumed (row G19) a count above 1 shows, above maxDisplayCount it shows replacementString, else "".
  define(w, "C_ActionBar.GetActionDisplayCount", function(slot, maxDisplayCount, replacementString)
    local entry = slotOf(w, slot)
    local count = entry and entry.count
    if not count or count <= 1 then
      return ""
    end
    return count > (maxDisplayCount or MAX_DISPLAY_COUNT) and (replacementString or REPLACEMENT) or tostring(count)
  end)
  -- source: assumed (row G19) a filled slot is usable unless its fixture says false; resources are never short.
  define(w, "C_ActionBar.IsUsableAction", function(slot)
    local entry = slotOf(w, slot)
    return entry ~= nil and entry.usable ~= false, false
  end)
  for _, name in ipairs({ "IsCurrentAction", "IsAutoRepeatAction", "IsAttackAction" }) do
    define(w, "C_ActionBar." .. name, function()
      return false
    end)
  end
end

function M.install(w)
  installSlotReads(w)
  installState(w)
end

return M
