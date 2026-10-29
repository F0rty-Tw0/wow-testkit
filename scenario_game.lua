-- Scenario game state: s:mock(patch) merges patch into the world's w.mock (locale, realm, CVars, keys, buttons...) by
-- State.merge's rules (a list merges index by index) and fires no event; a scenario fires the matching event itself,
-- or uses s:actions for action bar slots.
local M = {}

function M.extend(Scenario)
  function Scenario:mock(patch)
    if type(patch) ~= "table" then
      error("s:mock: patch must be a table", 2)
    end
    self.w:setMock(patch)
  end

  -- Patches the action bar slots ({ [slot] = fields | false }, see game/actionbar.lua) and fires
  -- ACTIONBAR_SLOT_CHANGED(slot) once per patched slot, ascending, in engine context.
  function Scenario:actions(patch)
    if type(patch) ~= "table" then
      error("s:actions: patch must be a table", 2)
    end
    self.w:setMock({ actions = patch })
    local slots = {}
    for slot in pairs(patch) do
      slots[#slots + 1] = slot
    end
    table.sort(slots)
    for _, slot in ipairs(slots) do
      self:fireIfKnown("ACTIONBAR_SLOT_CHANGED", slot)
    end
  end
end

return M
