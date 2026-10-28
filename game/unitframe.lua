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
  -- source: assumed (row G20) nobody is in a vehicle.
  for _, name in ipairs({ "UnitHasVehicleUI", "UnitInVehicle" }) do
    define(w, name, function()
      return false
    end)
  end
end

return M
