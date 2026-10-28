-- Scenario hooks for the Blizzard UI layer (blizzard_ui.lua): the client extract a layered scenario's world reads, and
-- the load step s:login runs before the addon under test.
local M = {}

local BlizzardUi = require("blizzard_ui")
local Client = require("client")
local EditMode = require("game.editmode")

local ENGINE = "blizzard"

-- The client extract for Scenario.new opts: opts.client, else, with opts.blizzardUi, opts.findClient(flavor) (default
-- Client.find; tests pass a stub so a developer's own extract never leaks in).
function M.client(opts)
  if opts.client or not opts.blizzardUi then
    return opts.client
  end
  return (opts.findClient or Client.find)(opts.flavor)
end

function M.extend(Scenario)
  -- Loads the layer s.blizzardUi asks for (true, or { targets }) under engine context; a no-op without it and once it
  -- loaded (smoke loads it before s:login does). The layer's notes become scenario notes.
  function Scenario:loadBlizzard()
    local layer = self.blizzardUi
    if not layer or self.blizzardLoaded then
      return
    end
    self.blizzardLoaded = true
    local w = self.w
    local opts = { targets = type(layer) == "table" and layer.targets or nil }
    function opts.fire(...)
      self:fireIfKnown(...)
    end
    local report = w:run(ENGINE, BlizzardUi.load, w, w.client, opts)
    for _, text in ipairs(report.notes) do
      self:note(text)
    end
  end

  -- Fires EDIT_MODE_LAYOUTS_UPDATED(<C_EditMode.GetLayouts()>, false) once, in engine context.
  local function fireLayouts(self)
    self:fireIfKnown("EDIT_MODE_LAYOUTS_UPDATED", EditMode.layoutsOf(self.w), false)
  end

  -- Patches w.mock.editMode ({ layouts?, active? }, see game/editmode.lua) and fires the event once. A patched layouts
  -- list replaces the old one, it does not merge into it.
  function Scenario:editMode(patch)
    if type(patch) ~= "table" then
      error("s:editMode: patch must be a table", 2)
    end
    if patch.layouts then
      self.w.mock.editMode.layouts = {}
    end
    self.w:setMock({ editMode = patch })
    fireLayouts(self)
  end

  -- What s:login runs between PLAYER_LOGIN and PLAYER_ENTERING_WORLD: the client announces its layouts to the loaded
  -- Blizzard UI. Silent without the layer or with no saved layouts.
  function Scenario:fireEditMode()
    if self.blizzardUi and #self.w.mock.editMode.layouts > 0 then
      fireLayouts(self)
    end
  end
end

return M
