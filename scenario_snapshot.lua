-- Scenario snapshots: s:snapshot(name, target) checks a frame, tooltip or menu snapshot against its golden file.
local M = {}

local Golden = require("golden")
local Snapshot = require("snapshot")

local function snapshotText(target)
  if target.kind == "menu" then
    return Snapshot.menu(target)
  end
  if target:GetObjectType() == "GameTooltip" then
    return Snapshot.tooltip(target)
  end
  return Snapshot.frame(target)
end

function M.extend(Scenario)
  -- Checks target's snapshot against the golden file "<name>.<flavor>.txt". A mismatch is recorded as an error
  -- (failing the report) instead of thrown; a newly written golden adds a note. The snapshot's own widget reads
  -- are not counted as unscripted.
  function Scenario:snapshot(name, target)
    local w = self.w
    if type(target) ~= "table" then
      error("s:snapshot: no target to snapshot (got " .. type(target) .. "); s:menu() is nil when no menu is open", 2)
    end
    if not self.goldenRoot then
      error("s:snapshot needs a golden root; run the scenario through Scenario.runFile", 2)
    end
    local unscripted = {}
    for key, count in pairs(w.unscripted) do
      unscripted[key] = count
    end
    local text = snapshotText(target)
    w.unscripted = unscripted
    local ok, result = pcall(Golden.check, self.goldenRoot, self.scenarioName, name, self.flavor, text, self.update)
    if not ok then
      w:recordError(result)
    elseif result == "written" then
      self:note("golden written: " .. self.scenarioName .. "/" .. name .. "." .. self.flavor .. ".txt")
    end
  end
end

return M
