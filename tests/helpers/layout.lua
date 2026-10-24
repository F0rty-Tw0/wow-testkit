-- Layout test helper: a retail world with widgets installed and a physical screen, always destroyed.
local HW = require("tests.helpers.widgets")

local M = {}

-- screen is { width, height } in physical pixels.
function M.withLayout(screen, fn)
  HW.withWidgets("retail", function(w)
    w.screen = screen
    fn(w)
  end)
end

return M
