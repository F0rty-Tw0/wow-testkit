-- Edit Mode layouts read from w.mock.editMode = { layouts = { layoutInfo... }, active = n } at call time. layoutInfo is
-- { layoutName, layoutType, systems = { { system, systemIndex?, isInDefaultPosition, anchorInfo, anchorInfo2?, settings
-- } } } (api/retail/EditModeManager.lua). layouts holds the saved layouts only; active is the client's activeLayout,
-- which counts the PRESET_COUNT preset layouts the client prepends, so active 3 is layouts[1]. Profile strings
-- (ConvertLayoutInfoToString and back) stay unscripted.
local M = {}

local State = require("game.state")
local define = State.define

M.DEFAULTS = { editMode = { layouts = {}, active = 1 } }

local ENGINE = "blizzard"
-- source: assumed (row BU5) the client prepends two preset layouts (Modern, Classic) to the saved ones.
local PRESET_COUNT = 2
-- Enum.EditModeLayoutType.Preset (api/retail/EditModeManagerConstants.lua).
local PRESET_TYPE = 0

-- C_EditMode.GetLayouts answers a fresh table each call, so an addon editing it never edits the mock.
local function layoutsOf(w)
  local mock = w.mock.editMode
  return State.merge({}, { layouts = mock.layouts, activeLayout = mock.active })
end

local function fireUpdated(w, info)
  w:run(ENGINE, w.fire, w, "EDIT_MODE_LAYOUTS_UPDATED", info, false)
end

local function installLayouts(w)
  define(w, "C_EditMode.GetLayouts", function()
    return layoutsOf(w)
  end)
  -- source: assumed (row G22) a save replaces the stored layouts with the non-preset ones it is given (and the active
  -- one when given) and fires EDIT_MODE_LAYOUTS_UPDATED(layouts, false).
  define(w, "C_EditMode.SaveLayouts", function(info)
    local mock = w.mock.editMode
    local saved = {}
    for _, layout in ipairs(info.layouts or {}) do
      if layout.layoutType ~= PRESET_TYPE then
        saved[#saved + 1] = layout
      end
    end
    mock.layouts = State.merge({}, saved)
    mock.active = info.activeLayout or mock.active
    fireUpdated(w, layoutsOf(w))
  end)
  -- source: assumed (row G22) an index outside 1 .. #layouts + presets is ignored, no event.
  define(w, "C_EditMode.SetActiveLayout", function(index)
    local mock = w.mock.editMode
    if index < 1 or index > #mock.layouts + PRESET_COUNT then
      return
    end
    mock.active = index
    fireUpdated(w, layoutsOf(w))
  end)
end

local function installQueries(w)
  define(w, "C_EditMode.GetAccountSettings", function()
    return {}
  end)
  -- source: assumed (row G22) a name is valid when it is not empty after trimming.
  define(w, "C_EditMode.IsValidLayoutName", function(name)
    return name:match("%S") ~= nil
  end)
end

function M.install(w)
  installLayouts(w)
  installQueries(w)
end

M.layoutsOf = layoutsOf
M.PRESET_COUNT = PRESET_COUNT

return M
