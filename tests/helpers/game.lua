-- Game-state test helper: a world with unit fixtures, widgets and the game-state fakes, always destroyed.
local H = require("tests.helpers.world")
local Game = require("game")
local Units = require("units")
local Widgets = require("ui.widgets")

local M = {}

-- Runs fn(w) on a fresh world of flavor with Units.install, Widgets.install and Game.install done.
function M.withGame(flavor, fn)
  H.withWorld(flavor, function(w)
    Units.install(w)
    Widgets.install(w)
    Game.install(w)
    fn(w)
  end)
end

return M
