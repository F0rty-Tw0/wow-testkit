-- Input test helper: records script calls on a widget.
local M = {}

-- Sets a recording handler per script on obj; each call appends { "<tag>:<script>" | "<script>", args... } to log
-- (a new list when nil). Returns log.
function M.record(obj, scripts, log, tag)
  log = log or {}
  for _, script in ipairs(scripts) do
    local label = tag and (tag .. ":" .. script) or script
    obj:SetScript(script, function(_, ...)
      log[#log + 1] = { label, ... }
    end)
  end
  return log
end

return M
