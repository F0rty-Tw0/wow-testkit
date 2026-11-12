-- Unit frame fakes: the portrait stand-in, a unit's group role, and the vehicle answers. The raid marker and tap-denied
-- answers are unit fixture fields (units.lua FIELD_ANSWERS).
local M = {}

local State = require("game.state")
local Units = require("units")
local define = State.define

M.DEFAULTS = {}

-- source: assumed (row G20) no 3D portraits (spec 15): every portrait is this labelled stand-in texture.
local PORTRAIT = "Interface\\CharacterFrame\\TempPortrait"
-- Flavors with no group roles; combat_group.lua holds the same list for Combat's own UnitGroupRolesAssigned.
local ROLE_LESS = { vanilla = true, tbc = true }

function M.install(w)
  define(w, "SetPortraitTexture", function(texture)
    texture:SetTexture(PORTRAIT)
  end)
  -- source: assumed (row G20) the fixture's role, "NONE" when unset or on a flavor without roles. Combat's install
  -- (an actor's role) replaces it.
  define(w, "UnitGroupRolesAssigned", function(unit)
    local data = not ROLE_LESS[w.flavor] and w.unitState and Units.fixture(w.unitState, unit)
    return data and data.role or "NONE"
  end)
  -- source: row G54 (confirmed) the forever and tbc extracts call C_UnitAurasPrivate at load (privateaurainit.lua:14,
  -- blizzard_auracontainer.lua:8); no api doc lists it, so those two get it by name. Assumed: the kit models no private
  -- auras, so lists are empty, lookups nil, every aura filtered out, and registrations and anchors accepted and unused.
  local privateFlavors = { "forever", "tbc" }
  local function none() end
  local function empty()
    return {}
  end
  for _, name in ipairs({ "GetAllPrivateAuras", "GetAllPrivateAuraInstanceIDs", "GetPrivateAuraAnchors" }) do
    define(w, "C_UnitAurasPrivate." .. name, empty, privateFlavors)
  end
  define(w, "C_UnitAurasPrivate.IsPrivateAuraFilteredOutByInstanceID", function()
    return true
  end, privateFlavors)
  for _, name in ipairs({
    "GetAuraDataByAuraInstanceIDPrivate",
    "GetPrivateAuraCasterGUID",
    "AddPrivateAuraUpdateCallback",
    "RemovePrivateAuraUpdateCallback",
    "AnchorPrivateAura",
    "SetPrivateAuraAnchorAddedCallback",
    "SetPrivateAuraAnchorRemovedCallback",
    "SetPrivateRaidBossMessageCallback",
    "SetPrivateWarningTextFrame",
  }) do
    define(w, "C_UnitAurasPrivate." .. name, none, privateFlavors)
  end
  -- source: assumed (row G20) nobody is in a vehicle.
  for _, name in ipairs({ "UnitHasVehicleUI", "UnitInVehicle" }) do
    define(w, name, function()
      return false
    end)
  end
end

return M
