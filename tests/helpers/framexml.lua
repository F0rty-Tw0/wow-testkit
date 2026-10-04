-- FrameXML test helpers: a world with widgets and the stage-1 FrameXML fakes installed, always destroyed.
local H = require("tests.helpers.world")
local FrameXML = require("framexml.fakes")
local Units = require("units")

local M = {}

function M.withFrameXML(flavor, fn)
  H.withWorld(flavor, function(w)
    FrameXML.installStage1(w)
    fn(w)
  end)
end

-- withFrameXML plus unit fixtures (w:unit, w:mouseover) for the tooltip fakes.
function M.withUnits(flavor, fn)
  M.withFrameXML(flavor, function(w)
    Units.install(w)
    fn(w)
  end)
end

return M
