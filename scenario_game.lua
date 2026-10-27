-- Scenario game state: s:mock(patch) merges patch into the world's w.mock (locale, realm, CVars, keys, buttons...).
-- It fires no events; a scenario fires the matching event itself.
local M = {}

function M.extend(Scenario)
  function Scenario:mock(patch)
    if type(patch) ~= "table" then
      error("s:mock: patch must be a table", 2)
    end
    self.w:setMock(patch)
  end
end

return M
