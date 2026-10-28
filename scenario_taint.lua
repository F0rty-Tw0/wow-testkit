-- Scenario taint step: s:taintLog() reads the world's taint log (the blocked calls and global writes the taint module
-- recorded) as plain data.
local M = {}

local Taint = require("taint")

function M.extend(Scenario)
  -- A copy of the log, oldest first: each entry { seq, time, kind, addon, name?, event?, text }; changing it changes nothing.
  function Scenario:taintLog()
    return Taint.copyLog(self.w)
  end
end

return M
