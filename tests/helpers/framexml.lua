-- FrameXML test helpers: a world with widgets and the stage-1 FrameXML fakes installed, always destroyed.
local H = require("tests.helpers.world")
local FrameXML = require("framexml.fakes")
local Units = require("units")

local M = {}

-- opts: World.new options (screen).
function M.withFrameXML(flavor, fn, opts)
  H.withWorld(flavor, function(w)
    FrameXML.installStage1(w)
    fn(w)
  end, opts)
end

-- withFrameXML plus unit fixtures (w:unit, w:mouseover) for the tooltip fakes.
function M.withUnits(flavor, fn)
  M.withFrameXML(flavor, function(w)
    Units.install(w)
    fn(w)
  end)
end

return M
