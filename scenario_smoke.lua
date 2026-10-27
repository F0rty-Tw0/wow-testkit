-- Scenario smoke support: ScenarioSmoke.silencePrint(w, opts) replaces the addon's print with a counter when
-- opts.silencePrint is set, so a smoke run of many addons is not buried in their chat output. The count reaches the
-- report as `printed`.
local M = {}

function M.silencePrint(w, opts)
  if not opts.silencePrint then
    return
  end
  w:install("print", function()
    w.printed = (w.printed or 0) + 1
  end)
end

return M
