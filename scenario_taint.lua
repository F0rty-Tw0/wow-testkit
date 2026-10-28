-- Scenario taint step: s:taintLog() reads the world's taint log (the blocked calls and global writes the taint module
-- recorded) as plain data.
local M = {}

local TaintLog = require("taint_log")

function M.extend(Scenario)
  -- A copy of the log, oldest first: each entry { seq, time, kind, addon, name?, event?, text }; changing it changes nothing.
  function Scenario:taintLog()
    return TaintLog.copyLog(self.w)
  end
end

return M
