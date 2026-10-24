-- Layout test helper: a retail world with widgets installed and a physical screen, always destroyed.
local H = require("tests.helpers.world")
local Widgets = require("ui.widgets")

local M = {}

-- screen is { width, height } in physical pixels.
function M.withLayout(screen, fn)
  H.withWorld("retail", function(w)
    Widgets.install(w)
    fn(w)
  end, { screen = screen })
end

return M
