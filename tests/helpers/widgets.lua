-- Widget test helpers: a world with ui.widgets installed, always destroyed.
local H = require("tests.helpers.world")
local Widgets = require("ui.widgets")

local M = {}

function M.withWidgets(flavor, fn)
  H.withWorld(flavor, function(w)
    Widgets.install(w)
    fn(w)
  end)
end

return M
